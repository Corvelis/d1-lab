import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:d1_lab/domain.dart';
import 'package:d1_lab/lab_controller.dart';

void main() {
  test(
    'model catalog pins four distinct models and their input capabilities',
    () {
      expect(modelSpecs.map((m) => m.id), ['2b', 'omni2b', '3b', 'omni']);
      expect(modelSpecs.where((m) => m.supportsAudio).map((m) => m.id), [
        'omni2b',
        'omni',
      ]);
      expect(modelSpecs.where((m) => m.isLfm3).map((m) => m.id), [
        '2b',
        'omni2b',
      ]);
      final names = <String>{};
      for (final model in modelSpecs) {
        for (final asset in [model.base, model.projector]) {
          expect(names.add(asset.filename), true);
          expect(asset.revision, matches(RegExp(r'^[a-f0-9]{40}$')));
          expect(asset.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
          expect(asset.bytes, greaterThan(0));
          expect(asset.uri.path, contains('/resolve/${asset.revision}/'));
        }
      }
    },
  );

  for (final id in ['2b', 'omni2b', '3b', 'omni', 'unknown']) {
    test(
      'saved model $id restores safely without changing old history',
      () async {
        final support = await Directory.systemTemp.createTemp(
          'd1-model-settings-',
        );
        final directory = await Directory('${support.path}/d1-lab').create();
        final history = File('${directory.path}/history.json');
        final original = jsonEncode([
          {
            'id': 'old',
            'runs': [
              {'model': 'd1-3B'},
            ],
          },
        ]);
        await history.writeAsString(original);
        await File(
          '${directory.path}/settings.json',
        ).writeAsString(jsonEncode({'modelId': id}));
        final lab = LabController(supportDirectory: support);
        try {
          await lab.init();
          expect(lab.error, isEmpty);
          expect(lab.modelId, id == 'unknown' ? '2b' : id);
          expect(lab.history.single['id'], 'old');
          expect(await history.readAsString(), original);
        } finally {
          lab.dispose();
          await support.delete(recursive: true);
        }
      },
    );
  }

  test(
    'comparison choices persist and duplicate selection swaps the pair',
    () async {
      final support = await Directory.systemTemp.createTemp('d1-model-pair-');
      final lab = LabController(supportDirectory: support);
      try {
        await lab.init();
        expect(lab.comparisonModels.map((m) => m.id), ['2b', 'omni2b']);
        await lab.selectComparisonModel(0, 'omni2b');
        expect(lab.comparisonModels.map((m) => m.id), ['omni2b', '2b']);
        await lab.selectComparisonModel(1, 'omni');
        final restored = LabController(supportDirectory: support);
        try {
          await restored.init();
          expect(restored.comparisonModels.map((m) => m.id), [
            'omni2b',
            'omni',
          ]);
        } finally {
          restored.dispose();
        }
      } finally {
        lab.dispose();
        await support.delete(recursive: true);
      }
    },
  );

  test('audio comparison offers the two audio-capable models', () {
    final lab = LabController();
    try {
      lab.inputKind = 'audio';
      expect(lab.comparableModels.map((m) => m.id), ['omni2b', 'omni']);
      expect(lab.comparisonModels.map((m) => m.id), ['omni2b', 'omni']);
    } finally {
      lab.dispose();
    }
  });
}
