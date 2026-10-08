import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d1_lab/data_widgets.dart';
import 'package:d1_lab/design.dart';
import 'package:d1_lab/lab_controller.dart';
import 'package:d1_lab/l10n/strings.dart';

class DataPageController extends LabController {
  DataPageController() {
    initialized = true;
  }
  int bulkCalls = 0, unusedCalls = 0;
  @override
  Future<({int bytes, int files})> mediaUsage() async =>
      (bytes: 1000000, files: 2);
  @override
  Future<void> deleteHistoryAndMedia() async {
    bulkCalls++;
  }

  @override
  Future<void> deleteUnusedMedia() async {
    unusedCalls++;
  }
}

Widget localized(String language, Widget child) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStrings.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: labTheme(),
  home: child,
);

void main() {
  for (final language in ['ja', 'en']) {
    testWidgets(
      'data removal needs confirmation and fits small screens in $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final lab = DataPageController();
        await tester.pumpWidget(
          localized(language, DataManagementPage(lab: lab)),
        );
        await tester.pumpAndSettle();
        expect(find.text('1.0 MB'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('delete-history-media')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(language == 'ja' ? 'キャンセル' : 'Cancel'));
        await tester.pumpAndSettle();
        expect(lab.bulkCalls, 0);
        await tester.tap(find.byKey(const ValueKey('delete-unused-media')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(language == 'ja' ? '削除' : 'Delete'));
        await tester.pumpAndSettle();
        expect(lab.unusedCalls, 1);
        expect(lab.bulkCalls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        lab.dispose();
      },
    );

    testWidgets('privacy policy is bundled and readable offline in $language', (
      tester,
    ) async {
      final path = language == 'ja' ? 'docs/privacy.md' : 'docs/privacy.en.md';
      await tester.runAsync(() async {
        await rootBundle.loadString(path);
        await tester.pumpWidget(localized(language, const PrivacyPage()));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(
        find.text(language == 'ja' ? '入力と判定結果' : 'Inputs and results'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
