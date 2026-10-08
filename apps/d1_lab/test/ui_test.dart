import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d1_lab/main.dart';
import 'package:d1_lab/lab_controller.dart';
import 'package:d1_lab/design.dart';
import 'package:d1_lab/results.dart';
import 'package:d1_lab/tasks.dart';
import 'package:d1_lab/task_widgets.dart';
import 'package:d1_lab/media_widgets.dart';
import 'package:d1_lab/domain.dart';
import 'package:d1_lab/l10n/strings.dart';

Map<String, dynamic> run({bool legacy = false, bool omni = false}) => {
  'model': omni ? 'd1-omni-600M' : 'd1-3B',
  'quantization': 'Q4_K_M',
  'placement': {'actual': 'Metal + CPU', 'gpuTensors': 266, 'cpuTensors': 1},
  'loadMs': 900,
  'totalMs': 150,
  if (!legacy) ...{
    'endToEndMs': 1100,
    'forwardMs': 100,
    'inputTokPerSec': 2400,
    'inputTokens': 240,
    'textTokens': 240,
    'mediaTokens': 0,
    'mediaEncodeMs': 0,
    'verifyMs': 2,
    'loadCallMs': 920,
    'inputPrepareMs': 20,
    'postprocessMs': 30,
    'unloadMs': 25,
  },
  'results': [
    {
      'type': 'choice',
      'instructions': 'この問い合わせの担当を選んでください。',
      'selected': '返品交換',
      'tokens': 120,
      'inferenceMs': 75,
      if (!legacy) 'inputTokPerSec': 2400,
      'probabilities': [
        {'label': '配送', 'description': '配送と追跡', 'probability': .02},
        {'label': '返品交換', 'description': '破損と返品', 'probability': .98},
      ],
    },
  ],
};

Map<String, dynamic> entry() => {
  'request': {
    'state': '届いた商品が壊れていました。',
    'questions': [{}],
  },
  'runs': [run()],
  'comparison': false,
};

class PreviewController extends LabController {
  PreviewController() : super(language: 'ja') {
    initialized = true;
    available = {
      for (final m in modelSpecs)
        for (final asset in [m.base, m.projector]) asset.filename: true,
    };
    loadTask(builtinTasks.first);
    questions.add(
      newQuestion(type: 'noul', instructions: 'この問い合わせは商品の交換を求めていますか？'),
    );
  }
  @override
  Future<void> settingsChanged() async => notifyListeners();
  bool prepared = false;
  int preparations = 0;
  @override
  bool get modelReady => prepared;
  @override
  Future<void> prepareModel() async {
    preparations++;
    prepared = true;
    modelPreparationMs = 80;
    notifyListeners();
  }

  @override
  Future<void> releaseRuntime() async {
    prepared = false;
    modelPreparationMs = null;
    notifyListeners();
  }

  String? deletedModel;
  @override
  Future<void> deleteModel(ModelSpec spec) async {
    deletedModel = spec.id;
    for (final asset in [spec.base, spec.projector]) {
      storedBytes[asset.filename] = 0;
      available[asset.filename] = false;
    }
    notifyListeners();
  }

  @override
  Future<void> execute({bool compare = false}) async {
    latest = entry();
    notifyListeners();
  }
}

class TaskSavingController extends PreviewController {
  final savedNames = <String>[];
  final savedKinds = <String?>[];
  @override
  Future<void> saveTask(String name, {String? kind}) async {
    savedNames.add(name);
    savedKinds.add(kind);
    taskId = 'custom-${savedNames.length}';
    taskTitle = name;
    inputKind = kind == null || kind == 'auto' ? automaticTaskKind : kind;
    if (inputKind == 'audio') modelId = 'omni';
    notifyListeners();
  }
}

void main() {
  for (final language in ['ja', 'en']) {
    for (final selection in ['audio', 'auto']) {
      testWidgets(
        'task name and $selection category are passed to saving in $language',
        (tester) async {
          tester.view.physicalSize = const Size(320, 852);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final lab = TaskSavingController()..language = language;
          try {
            await tester.pumpWidget(D1Lab(controller: lab));
            final field = find.byKey(const ValueKey('task-name-field'));
            final category = find.byKey(const ValueKey('task-kind-field'));
            final button = find.byKey(const ValueKey('save-task-button'));
            await tester.scrollUntilVisible(
              field,
              180,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.enterText(field, '  お店の評価  ');
            await tester.ensureVisible(category);
            await tester.pumpAndSettle();
            await tester.tap(category);
            await tester.pumpAndSettle();
            await tester.tap(find.text(language == 'ja' ? '音声' : 'Audio').last);
            await tester.pumpAndSettle();
            if (selection == 'auto') {
              await tester.tap(category);
              await tester.pumpAndSettle();
              await tester.tap(
                find.text(language == 'ja' ? '自動選択' : 'Automatic').last,
              );
              await tester.pumpAndSettle();
            }
            lab.draftChanged();
            await tester.pump();
            expect(
              tester.widget<TextField>(field).controller!.text,
              '  お店の評価  ',
            );
            expect(
              find.text(language == 'ja' ? 'タスク名' : 'Task name'),
              findsOneWidget,
            );
            await tester.enterText(field, '   ');
            await tester.ensureVisible(button);
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(lab.savedNames, isEmpty);
            expect(
              find.text(
                language == 'ja' ? 'タスク名を入力してください' : 'Enter a task name',
              ),
              findsOneWidget,
            );
            await tester.enterText(field, '  お店の評価  ');
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(lab.savedNames, ['お店の評価']);
            expect(lab.savedKinds, [selection]);
            expect(lab.inputKind, selection == 'audio' ? 'audio' : 'text');
            expect(lab.taskTitle, 'お店の評価');
            lab.loadTask(builtinTasks[1]);
            await tester.pump();
            expect(tester.widget<TextField>(field).controller!.text, '口コミの印象');
            expect(
              tester
                  .widget<DropdownButtonFormField<String>>(category)
                  .initialValue,
              'auto',
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            lab.dispose();
          }
        },
      );
    }
  }
  testWidgets(
    'image long edge can be selected and audio tasks omit image sizing',
    (tester) async {
      final lab = PreviewController();
      lab.loadTask(builtinTasks.firstWhere((t) => t.inputKind == 'image'));
      await tester.pumpWidget(D1Lab(controller: lab));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('image-size-2048')),
        100,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('image-size-2048'))),
        alignment: .25,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('image-size-2048')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('512 px').last);
      await tester.pumpAndSettle();
      expect(lab.imageMaxPixels, 512);
      expect(find.text('画像の長辺'), findsOneWidget);
      lab.loadTask(builtinTasks.firstWhere((t) => t.inputKind == 'audio'));
      await tester.pumpAndSettle();
      expect(find.text('画像の長辺'), findsNothing);
      expect(find.text('補足（任意）'), findsOneWidget);
      expect(lab.state, isEmpty);
      await tester.pumpWidget(const SizedBox());
      lab.dispose();
    },
  );
  testWidgets(
    'model preparation stays at the top, changes to ready and can unload',
    (tester) async {
      final lab = PreviewController();
      await tester.pumpWidget(D1Lab(controller: lab));
      final header = find.byKey(const ValueKey('model-readiness'));
      final position = tester.getTopLeft(header);
      expect(find.text('未準備'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(header), position);
      await tester.tap(find.byKey(const ValueKey('prepare-model-button')));
      await tester.pumpAndSettle();
      expect(lab.preparations, 1);
      expect(find.text('準備完了 · 80.0 ms'), findsOneWidget);
      expect(find.text('解放'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('prepare-model-button')));
      await tester.pumpAndSettle();
      expect(find.text('未準備'), findsOneWidget);
      lab.busy = true;
      lab.preparingModel = true;
      lab.changed();
      await tester.pump();
      expect(find.text('準備中…'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('prepare-model-button')),
      );
      expect(button.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      lab.dispose();
    },
  );
  testWidgets(
    'image and audio samples expose acquisition before instructions',
    (tester) async {
      final lab = PreviewController();
      await tester.pumpWidget(D1Lab(controller: lab));
      await tester.tap(find.text('タスクを選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('画像'));
      await tester.pumpAndSettle();
      expect(find.text('写真の主な色'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('カップが写っている？'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('カップが写っている？'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('写真の主な色'),
        -100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('写真の主な色'));
      await tester.pumpAndSettle();
      expect(lab.inputKind, 'image');
      await tester.scrollUntilVisible(find.text('写真から選ぶ'), 100);
      expect(find.text('写真から選ぶ'), findsOneWidget);
      final executeButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('判定を実行する'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(executeButton.onPressed, null);
      expect(find.text('マイクで録音'), findsNothing);
      await tester.ensureVisible(find.text('タスクを選ぶ'));
      await tester.tap(find.text('タスクを選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('音声'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('声で操作を選ぶ'));
      await tester.pumpAndSettle();
      expect(lab.modelId, 'omni');
      await tester.scrollUntilVisible(find.text('マイクで録音'), 100);
      expect(
        find.ancestor(
          of: find.text('マイクで録音'),
          matching: find.byWidgetPredicate((w) => w is OutlinedButton),
        ),
        findsOneWidget,
      );
      expect(find.text('写真から選ぶ'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      lab.dispose();
    },
  );
  testWidgets(
    'recording controls and meter fit small screens and enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 852);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final lab = PreviewController()
        ..recording = true
        ..inputBusy = true
        ..recordingElapsed = const Duration(milliseconds: 12600)
        ..recordingLevel = .7;
      await tester.pumpWidget(
        MaterialApp(
          theme: labTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaInputCard(lab: lab, onImport: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('12.6 / 30 s'), findsOneWidget);
      expect(find.text('停止して使う'), findsOneWidget);
      expect(find.text('録音を破棄'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      lab.dispose();
    },
  );
  testWidgets(
    'choosing a Japanese task fills material, instructions and candidates',
    (tester) async {
      final lab = PreviewController();
      await tester.pumpWidget(D1Lab(controller: lab));
      await tester.tap(find.text('タスクを選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('口コミの印象'));
      await tester.pumpAndSettle();
      expect(lab.state, contains('また行きたい'));
      expect(lab.questions.single.instructions, 'この口コミの印象を選んでください。');
      expect(
        lab.questions.single.toJson()['options'].map((o) => o['name']).toList(),
        ['好意的', '否定的', '中立'],
      );
      expect(find.text('口コミの印象'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      lab.dispose();
    },
  );

  testWidgets('help explains a concrete Japanese task and all three inputs', (
    tester,
  ) async {
    final lab = PreviewController();
    await tester.pumpWidget(D1Lab(controller: lab));
    await tester.tap(find.text('使い方'));
    await tester.pumpAndSettle();
    expect(find.text('はじめての判定'), findsOneWidget);
    expect(find.text('入力を用意する'), findsOneWidget);
    expect(find.textContaining('確率は正解率'), findsNothing);
    await tester.ensureVisible(find.text('結果の見方'));
    await tester.tap(find.text('結果の見方'));
    await tester.pumpAndSettle();
    expect(find.textContaining('確率は正解率'), findsOneWidget);
    expect(find.textContaining('Prefill / Input speed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    lab.dispose();
  });

  testWidgets(
    'editing and deleting candidates preserves other Japanese labels',
    (tester) async {
      final lab = PreviewController()..loadTask(builtinTasks[1]);
      final q = lab.questions.single;
      await tester.pumpWidget(
        MaterialApp(
          theme: labTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CriteriaEditor(
                question: q,
                enabled: true,
                onChanged: lab.draftChanged,
              ),
            ),
          ),
        ),
      );
      final names = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '候補の名前',
      );
      await tester.enterText(names.first, '絶賛');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('この候補を削除').at(1));
      await tester.tap(find.byTooltip('この候補を削除').at(1));
      await tester.pumpAndSettle();
      expect(q.toJson()['options'].map((o) => o['name']).toList(), [
        '絶賛',
        '中立',
      ]);
      expect((tester.widget<TextField>(names.last)).controller!.text, '中立');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      lab.dispose();
    },
  );
  testWidgets(
    'successful execution opens results directly with measured speeds',
    (tester) async {
      final lab = PreviewController();
      await tester.pumpWidget(D1Lab(controller: lab));
      await tester.tap(find.text('判定を実行する'));
      await tester.pumpAndSettle();
      expect(find.text('判断の結果'), findsOneWidget);
      expect(find.text('PREFILL'), findsOneWidget);
      expect(find.text('2400'), findsOneWidget);
      expect(find.text('1.10'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      lab.dispose();
    },
  );

  testWidgets('old history leaves unknown total and throughput blank', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: labTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RunResults(run: run(legacy: true), onJson: () {}),
          ),
        ),
      ),
    );
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('150.0'), findsOneWidget);
    expect(find.text('1600'), findsNothing);
  });

  testWidgets(
    'Total identifies loading and reuse without hiding end-to-end time',
    (tester) async {
      for (final reused in [false, true]) {
        final measured = run()..['runtimeReused'] = reused;
        await tester.pumpWidget(
          MaterialApp(
            theme: labTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: RunResults(
                  key: ValueKey(reused),
                  run: measured,
                  onJson: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.text(reused ? '読み込み済みを再利用' : 'モデル読み込みあり'), findsOneWidget);
        expect(find.text('1.10'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final (width, language) in [
    (320.0, 'ja'),
    (393.0, 'ja'),
    (320.0, 'en'),
    (393.0, 'en'),
  ]) {
    testWidgets(
      'input, results and settings fit $width px in $language with larger text',
      (tester) async {
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final lab = PreviewController()..language = language;
        final strings = AppStrings(language);
        await tester.pumpWidget(D1Lab(controller: lab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(strings.text('判定を実行する')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -450));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(strings.text('計測の内訳')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(strings.text('計測の内訳')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(strings.text('モデル')).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final settings = find.byKey(const ValueKey('advanced-settings'));
        await tester.scrollUntilVisible(settings, 250);
        await Scrollable.ensureVisible(
          tester.element(settings),
          alignment: .25,
        );
        await tester.pumpAndSettle();
        await tester.tap(settings);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('keep-model-loaded')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        lab.dispose();
      },
    );
  }

  testWidgets('a missing model leads to downloading instead of a failed run', (
    tester,
  ) async {
    final lab = PreviewController()..available.clear();
    await tester.pumpWidget(D1Lab(controller: lab));
    await tester.tap(find.text('モデルを取得して始める'));
    await tester.pumpAndSettle();
    expect(find.text('このタスクに必要なモデルを取得'), findsOneWidget);
    expect(find.textContaining('Hugging Faceの公式配布元'), findsOneWidget);
    expect(lab.latest, isNull);
    expect(lab.error, isEmpty);
    await tester.pumpWidget(const SizedBox());
    lab.dispose();
  });

  testWidgets(
    'model deletion asks for confirmation and cancellation preserves the model',
    (tester) async {
      final lab = PreviewController()
        ..storedBytes[modelSpecs.first.base.filename] = 1674456352;
      await tester.pumpWidget(D1Lab(controller: lab, initialTab: 3));
      final button = find.byKey(const ValueKey('delete-model-3b'));
      await tester.scrollUntilVisible(button, 250);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('d1-3Bを削除しますか？'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(lab.deletedModel, isNull);
      expect(lab.available[modelSpecs.first.base.filename], true);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();
      expect(lab.deletedModel, '3b');
      expect(lab.needsDownload, true);
      await tester.pumpWidget(const SizedBox());
      lab.dispose();
    },
  );

  testWidgets('omni speed is labeled as input processing rather than prefill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: labTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RunResults(run: run(omni: true), onJson: () {}),
          ),
        ),
      ),
    );
    expect(find.text('INPUT SPEED'), findsOneWidget);
    expect(find.text('入力の処理速度'), findsOneWidget);
    expect(find.text('PREFILL'), findsNothing);
  });
}
