import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:d1_lab/lab_controller.dart';
import 'package:d1_lab/media_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late LabController lab;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('d1-media-cleanup-');
    lab = LabController(supportDirectory: temporary);
    await lab.init();
  });
  tearDown(() async {
    lab.dispose();
    await temporary.delete(recursive: true);
  });

  Future<File> media(String name, [int bytes = 10]) async {
    final file = File('${lab.directory.path}/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(bytes, 1));
    return file;
  }

  Map<String, dynamic> entry(String id, File file, [File? original]) => {
    'id': id,
    'request': {
      'mediaPath': file.path,
      if (original != null) 'mediaSourcePath': original.path,
    },
  };

  test(
    'deleting history removes unreferenced images and their originals',
    () async {
      final photo = await media('media/photo.png');
      final original = await media('media/sources/photo.jpg');
      lab.history = [entry('photo', photo, original)];
      lab.latest = lab.history.first;
      await lab.deleteHistory('photo');
      expect(lab.error, isEmpty);
      expect(lab.history, isEmpty);
      expect(lab.latest, isNull);
      expect(await photo.exists(), isFalse);
      expect(await original.exists(), isFalse);
      expect(
        jsonDecode(
          await File('${lab.directory.path}/history.json').readAsString(),
        ),
        isEmpty,
      );
    },
  );

  test(
    'shared history and current input retain both original and resized media',
    () async {
      final shared = await media('media/shared.png');
      final source = await media('media/sources/shared.jpg');
      final draft = await media('media/draft.png');
      final draftSource = await media('media/sources/draft.jpg');
      final discarded = await media('media/discarded.wav');
      final abandonedRecording = await media('recordings/interrupted.wav');
      lab.mediaPath = draft.path;
      lab.imageSourcePath = draftSource.path;
      lab.history = [
        entry('first', shared, source),
        entry('second', shared, source),
      ];
      await lab.deleteHistory('first');
      expect(lab.history.single['id'], 'second');
      for (final file in [shared, source, draft, draftSource]) {
        expect(await file.exists(), isTrue);
      }
      expect(await discarded.exists(), isFalse);
      expect(await abandonedRecording.exists(), isFalse);
      expect(await lab.mediaUsage(), (bytes: 40, files: 4));
    },
  );

  test(
    'cleanup never follows links or deletes files outside media folders',
    () async {
      final outside = await media('outside/private.wav');
      final model = await media('models/model.gguf');
      final tasks = await media('tasks.json');
      final unused = await media('media/unused.wav');
      await Link('${lab.directory.path}/media/link.wav').create(outside.path);
      await Link(
        '${lab.directory.path}/media/linked-folder',
      ).create(outside.parent.path);
      lab.history = [entry('external', outside)];
      await lab.deleteUnusedMedia();
      for (final file in [outside, model, tasks]) {
        expect(await file.exists(), isTrue);
      }
      expect(await unused.exists(), isFalse);
      expect(await MediaStorage(lab.directory).usage(), (bytes: 0, files: 0));
    },
  );

  test(
    'bulk deletion clears attachments, history and media but retains tasks and models',
    () async {
      final photo = await media('media/photo.png');
      final original = await media('media/sources/photo.jpg');
      final voice = await media('media/voice.wav');
      final model = await media('models/model.gguf');
      await lab.saveTask('My task');
      lab.mediaPath = photo.path;
      lab.imageSourcePath = original.path;
      lab.mediaHash = 'test';
      lab.mediaInfo = {'width': 1};
      lab.history = [entry('voice', voice)];
      lab.latest = lab.history.first;
      await lab.deleteHistoryAndMedia();
      expect(lab.error, isEmpty);
      expect(lab.history, isEmpty);
      expect(lab.latest, isNull);
      expect(lab.mediaPath, isNull);
      expect(lab.imageSourcePath, isNull);
      expect(lab.mediaHash, isNull);
      expect(lab.mediaInfo, isNull);
      expect(await lab.mediaUsage(), (bytes: 0, files: 0));
      expect(await model.exists(), isTrue);
      expect(lab.savedTasks.single.title, 'My task');
      expect(await File('${lab.directory.path}/tasks.json').exists(), isTrue);
    },
  );

  test('failed history persistence retains history and its media', () async {
    final photo = await media('media/photo.png');
    lab.history = [entry('photo', photo)];
    await Directory('${lab.directory.path}/history.json.tmp').create();
    await lab.deleteHistory('photo');
    expect(lab.error, isNotEmpty);
    expect(lab.history.single['id'], 'photo');
    expect(await photo.exists(), isTrue);
    expect(lab.locked, isFalse);
  });

  test('deletion is blocked during input capture or inference', () async {
    final photo = await media('media/photo.png');
    lab.history = [entry('photo', photo)];
    for (final capturing in [true, false]) {
      lab.inputBusy = capturing;
      lab.busy = !capturing;
      await lab.deleteHistory('photo');
      await lab.deleteUnusedMedia();
      await lab.deleteHistoryAndMedia();
      expect(lab.history, hasLength(1));
      expect(await photo.exists(), isTrue);
    }
    lab.busy = false;
  });
}
