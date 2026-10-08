import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d1_lab/l10n/strings.dart';
import 'package:d1_lab/lab_controller.dart';
import 'package:d1_lab/main.dart';
import 'package:d1_lab/tasks.dart';
import 'package:d1_lab/domain.dart';

class MemorySettingsController extends LabController {
  MemorySettingsController() : super(language: 'ja') {
    initialized = true;
    loadTask(builtinTasks.first);
    available = {
      for (final spec in modelSpecs)
        for (final asset in [spec.base, spec.projector]) asset.filename: true,
    };
  }
  @override
  Future<void> settingsChanged() async => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('language resolution uses device preferences with English fallback', () {
    expect(resolveLanguage('system', [const Locale('ja', 'JP')]), 'ja');
    expect(resolveLanguage('en', [const Locale('ja')]), 'en');
    expect(
      resolveLanguage('system', [const Locale('fr'), const Locale('ja')]),
      'ja',
    );
    expect(resolveLanguage('system', [const Locale('fr')]), 'en');
  });

  test('messages preserve inserted user text and localize dynamic errors', () {
    const english = AppStrings('en');
    expect(
      english.text('判断材料：{p0}', {'p0': '日本語の入力 {p1}'}),
      'Input: 日本語の入力 {p1}',
    );
    expect(
      english.status('FormatException: 判定指示を入力してください'),
      'Enter an instruction',
    );
    expect(english.status('d1-3B：Metalで読み込み中'), 'd1-3B: Loading with Metal');
    expect(
      english.status('d1-3B-Q4_K_M.gguf · SHA-256を検証中'),
      'd1-3B-Q4_K_M.gguf · Verifying SHA-256',
    );
    expect(
      english.progress('d1-3B-Q4_K_M.gguf · SHA-256を検証中'),
      'Checking the file',
    );
    expect(english.progress('d1-3B：SHA-256を確認中'), 'd1-3B: Checking the model');
    expect(
      english.status('d1-omniのプロジェクターをモデル画面で取得してください'),
      'Download the d1-omni projector from Models',
    );
    expect(
      english.status(
        'HttpException: 配布先へのアクセスが拒否されました（HTTP 403）。時間をおいて再試行してください。公式GGUFのファイル取り込みも使えます。',
      ),
      'The download server denied access (HTTP 403). Try again later. You can also import the official GGUF files.',
    );
  });

  test('every localized message keeps its placeholder names', () {
    Set<String> placeholders(String s) =>
        RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m[1]!).toSet();
    for (final entry in englishMessages.entries) {
      expect(entry.value, isNotEmpty, reason: entry.key);
      expect(
        placeholders(entry.value),
        placeholders(entry.key),
        reason: entry.key,
      );
    }
    for (final task in englishTasks) {
      task.validate();
    }
  });

  test(
    'language changes are saved atomically and restored after restart',
    () async {
      final temp = await Directory.systemTemp.createTemp('d1-locale-');
      final lab = LabController(language: 'ja', supportDirectory: temp);
      try {
        await lab.init();
        await Future.wait([
          lab.setLanguage('en'),
          lab.setLanguage('ja'),
          lab.setLanguage('en'),
        ]);
        await lab.settingsSaved;
        final settings = jsonDecode(
          await File('${lab.directory.path}/settings.json').readAsString(),
        );
        expect(settings['language'], 'en');
        final restarted = LabController(supportDirectory: temp);
        await restarted.init();
        expect(restarted.language, 'en');
        expect(restarted.taskId, 'inquiry-en-start');
        expect(restarted.error, isEmpty);
        restarted.dispose();
      } finally {
        lab.dispose();
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'image long-edge preference persists and unsupported values are ignored',
    () async {
      final temp = await Directory.systemTemp.createTemp('d1-image-settings-');
      final lab = LabController(supportDirectory: temp);
      try {
        await lab.init();
        await lab.setImageMaxPixels(768);
        await lab.setImageMaxPixels(999);
        expect(lab.imageMaxPixels, 768);
        final restarted = LabController(supportDirectory: temp);
        await restarted.init();
        expect(restarted.imageMaxPixels, 768);
        restarted.dispose();
      } finally {
        lab.dispose();
        await temp.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'switching languages preserves drafts and offers English samples',
    (tester) async {
      final lab = MemorySettingsController();
      lab.state = '編集中の日本語';
      lab.questions.single.instructions = '自分の指示';
      lab.draftChanged();
      try {
        await tester.pumpWidget(D1Lab(controller: lab));
        await tester.tap(find.byKey(const ValueKey('language-menu')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(CheckedPopupMenuItem<String>, 'English'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Run decision'), findsOneWidget);
        expect(find.text('Choose a task'), findsOneWidget);
        expect(lab.state, '編集中の日本語');
        expect(lab.questions.single.instructions, '自分の指示');
        expect(lab.taskModified, true);
        expect(lab.error, isEmpty);
        await tester.tap(find.text('Choose a task'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Review sentiment'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review sentiment'));
        await tester.pumpAndSettle();
        expect(lab.state, contains('delicious'));
        expect(lab.questions.single.instructions, contains('sentiment'));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        lab.dispose();
      }
    },
  );
}
