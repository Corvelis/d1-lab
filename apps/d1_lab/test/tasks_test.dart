import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:d1_lab/tasks.dart';
import 'package:d1_lab/lab_controller.dart';

void main() {
  late Directory directory;
  late LabController lab;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('d1-task-test-');
    lab = LabController()..directory = directory;
    lab.loadTask(builtinTasks[1]);
  });
  tearDown(() async {
    lab.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'Japanese custom tasks persist, stay independent of edits and can be deleted',
    () async {
      lab.state = '接客が親切で、また行きたいです。';
      await lab.saveTask('お店の口コミ');
      final id = lab.savedTasks.single.id;
      lab.state = 'あとから書き換えた文章';
      lab.questions.first.criteria = '別の候補\nもう1つ';
      await lab.readTasks();
      lab.loadTask(lab.savedTasks.single);
      expect(lab.state, '接客が親切で、また行きたいです。');
      expect(lab.taskTitle, 'お店の口コミ');
      expect(lab.questions.first.toJson()['options'][0]['name'], '好意的');
      expect(lab.questions.first.instructions, 'この口コミの印象を選んでください。');
      await lab.deleteTask(id);
      await lab.readTasks();
      expect(lab.savedTasks, isEmpty);
      expect(builtinTasks[1].title, '口コミの印象');
    },
  );

  test('invalid candidates cannot overwrite a saved task', () async {
    await lab.saveTask('有効なタスク');
    final file = File('${directory.path}/tasks.json');
    final before = await file.readAsString();
    lab.questions.first.criteria = '同じ候補\n同じ候補';
    await expectLater(lab.saveTask('不正な候補'), throwsFormatException);
    expect(await file.readAsString(), before);
    expect(lab.savedTasks, hasLength(1));
  });
  test(
    'automatic category uses the current task or attached media type',
    () async {
      for (final kind in ['text', 'image', 'audio']) {
        lab.loadTask(builtinTasks[1]);
        lab.inputKind = kind;
        lab.state = kind == 'text' ? '親切なお店でした。' : '';
        await lab.saveTask('自動-$kind', kind: 'auto');
        expect(lab.savedTasks.first.inputKind, kind);
      }
      for (final kind in ['image', 'audio']) {
        lab.loadTask(builtinTasks[1]);
        lab.state = '';
        lab.mediaType = kind;
        lab.mediaPath = '${directory.path}/attachment';
        await lab.saveTask('添付-$kind', kind: 'auto');
        expect(lab.savedTasks.first.inputKind, kind);
      }
      await lab.readTasks();
      expect(lab.savedTasks.map((t) => t.inputKind), [
        'audio',
        'image',
        'audio',
        'image',
        'text',
      ]);
      expect(lab.savedTasks.any((t) => t.inputKind == 'auto'), false);
    },
  );
  test('chosen text, image and audio categories survive reopening', () async {
    for (final kind in ['text', 'image', 'audio']) {
      lab.loadTask(builtinTasks[1]);
      lab.state = kind == 'text' ? '親切なお店でした。' : '';
      await lab.saveTask('自分の$kindタスク', kind: kind);
      expect(lab.savedTasks.first.inputKind, kind);
      expect(lab.inputKind, kind);
      expect(lab.mediaPath, isNull);
      if (kind == 'audio') expect(lab.modelId, 'omni');
    }
    await lab.readTasks();
    expect(lab.savedTasks.map((t) => t.inputKind), ['audio', 'image', 'text']);
    final before = await File('${directory.path}/tasks.json').readAsString();
    await expectLater(
      lab.saveTask('不正な種類', kind: 'video'),
      throwsFormatException,
    );
    expect(await File('${directory.path}/tasks.json').readAsString(), before);
    for (final task in lab.savedTasks) {
      lab.loadTask(task);
      expect(lab.inputKind, task.inputKind);
      expect(lab.missingInput == null, task.inputKind == 'text');
    }
  });
  test(
    'saving an audio category releases the photo attachment but preserves its file',
    () async {
      lab.loadTask(builtinTasks.firstWhere((t) => t.inputKind == 'image'));
      final photo = File('${directory.path}/private-photo.png');
      await photo.writeAsString('photo');
      lab.mediaPath = photo.path;
      lab.imageSourcePath = photo.path;
      lab.mediaHash = 'photo-hash';
      lab.mediaInfo = {'width': 256, 'height': 256};
      await lab.saveTask('声で判定', kind: 'audio');
      expect(lab.inputKind, 'audio');
      expect(lab.modelId, 'omni');
      expect(lab.mediaPath, isNull);
      expect(lab.imageSourcePath, isNull);
      expect(lab.mediaHash, isNull);
      expect(lab.mediaInfo, isNull);
      expect(lab.missingInput, contains('録音'));
      expect(await photo.readAsString(), 'photo');
      await lab.readTasks();
      expect(lab.savedTasks.single.inputKind, 'audio');
    },
  );
  test(
    'audio-only tasks can be saved without recording or supplementary text',
    () async {
      lab.loadTask(builtinTasks.firstWhere((t) => t.inputKind == 'audio'));
      expect(lab.state, isEmpty);
      await lab.saveTask('音声だけで操作');
      await lab.readTasks();
      lab.loadTask(lab.savedTasks.single);
      expect(lab.inputKind, 'audio');
      expect(lab.state, isEmpty);
      expect(lab.questions.first.instructions, isNotEmpty);
      expect(lab.missingInput, contains('録音'));
      lab.inputKind = 'text';
      await expectLater(lab.saveTask('材料なし'), throwsFormatException);
      expect(lab.savedTasks, hasLength(1));
    },
  );
  test(
    'media task saves its modality without saving a captured file',
    () async {
      lab.loadTask(builtinTasks.firstWhere((t) => t.inputKind == 'image'));
      lab.mediaPath = '${directory.path}/private-photo.png';
      await lab.saveTask('写真の分類');
      final json = await File('${directory.path}/tasks.json').readAsString();
      expect(json, isNot(contains('private-photo.png')));
      await lab.readTasks();
      lab.loadTask(lab.savedTasks.single);
      expect(lab.inputKind, 'image');
      expect(lab.mediaPath, null);
      expect(lab.missingInput, isNotNull);
    },
  );
  test('old tasks default to text and every bundled media task is valid', () {
    final legacy = builtinTasks.first.toJson()..remove('inputKind');
    expect(D1Task.fromJson(legacy).inputKind, 'text');
    for (final task in builtinTasks) {
      task.validate();
    }
    expect(builtinTasks.where((t) => t.inputKind == 'image'), hasLength(4));
    lab.loadTask(builtinTasks.firstWhere((t) => t.inputKind == 'audio'));
    expect(lab.modelId, 'omni');
    expect(lab.missingInput, contains('録音'));
    lab.loadTask(builtinTasks.firstWhere((t) => t.inputKind == 'image'));
    expect(lab.modelId, '3b');
  });
}
