import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:decision_bridge/decision_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d1_lab/capture.dart';
import 'package:d1_lab/lab_controller.dart';
import 'package:d1_lab/tasks.dart';

Uint8List wav(int seconds) {
  final size = seconds * 16000 * 2;
  final bytes = Uint8List(44 + size);
  final data = ByteData.sublistView(bytes);
  void text(int at, String value) =>
      bytes.setRange(at, at + value.length, value.codeUnits);
  text(0, 'RIFF');
  text(8, 'WAVE');
  text(12, 'fmt ');
  text(36, 'data');
  data.setUint32(4, 36 + size, Endian.little);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint32(40, size, Endian.little);
  return bytes;
}

class FakeCapture implements CaptureDevice {
  bool permission = true, cancelled = false;
  bool? camera;
  String? photoPath, recordingPath;
  Object? photoError;
  int seconds = 2;
  final events = StreamController<bool>.broadcast();
  @override
  Future<String?> photo({required bool camera}) async {
    this.camera = camera;
    if (photoError != null) throw photoError!;
    return photoPath;
  }

  @override
  Future<bool> microphonePermission() async => permission;
  @override
  Future<void> start(String path) async {
    recordingPath = path;
    await File(path).writeAsBytes(wav(seconds));
  }

  @override
  Future<String?> stop() async => recordingPath;
  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Stream<double> get levels => const Stream.empty();
  @override
  Stream<bool> get interruptions => events.stream;
  @override
  Future<void> dispose() async {
    await events.close();
  }
}

class CopyImageRuntime extends MethodChannelDecisionRuntime {
  final inputs = <String>[];
  final sizes = <int>[];
  bool fail = false;
  Completer<void>? started, finish;
  @override
  Future<Map<String, dynamic>> prepareImage(
    String input,
    String output, {
    int maxPixelSize = 2048,
  }) async {
    inputs.add(input);
    sizes.add(maxPixelSize);
    started?.complete();
    await finish?.future;
    await File(input).copy(output);
    if (fail) throw StateError('image preparation failed');
    return {'width': 100, 'height': 100, 'maxPixelSize': maxPixelSize};
  }
}

void main() {
  late Directory temp;
  late FakeCapture device;
  late LabController lab;
  late CopyImageRuntime runtime;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('d1-capture-');
    device = FakeCapture();
    runtime = CopyImageRuntime();
    lab = LabController(capture: device, runtime: runtime)..directory = temp;
  });
  tearDown(() async {
    if (lab.recording) await lab.stopRecording(discard: true);
    lab.dispose();
    await temp.delete(recursive: true);
  });
  test(
    'camera and library selections are copied; cancel preserves prior input',
    () async {
      device.photoPath = '${temp.path}/source.jpg';
      await File(device.photoPath!).writeAsBytes([1, 2, 3]);
      await lab.choosePhoto(camera: true);
      expect(device.camera, true);
      expect(lab.mediaPath, isNot(device.photoPath));
      expect(lab.mediaHash, isNotEmpty);
      final previous = lab.mediaPath;
      device.photoPath = null;
      await lab.choosePhoto(camera: false);
      expect(device.camera, false);
      expect(lab.mediaPath, previous);
      expect(lab.locked, false);
    },
  );
  test(
    'permission denial releases lock without discarding existing media',
    () async {
      lab.mediaPath = 'previous.png';
      device.permission = false;
      await lab.startRecording();
      expect(lab.error, contains('マイクを許可'));
      expect(lab.mediaPath, 'previous.png');
      expect(device.recordingPath, null);
      expect(lab.locked, false);
      device.photoError = PlatformException(code: 'camera_access_denied');
      await lab.choosePhoto(camera: true);
      expect(lab.error, contains('権限'));
      expect(lab.mediaPath, 'previous.png');
      expect(lab.locked, false);
    },
  );
  test(
    'recording blocks execution and task switching; stop attaches WAV for omni',
    () async {
      lab.loadTask(builtinTasks.first);
      await lab.startRecording();
      expect(lab.recording, true);
      expect(lab.locked, true);
      lab.loadTask(builtinTasks[1]);
      expect(lab.taskId, builtinTasks.first.id);
      await lab.execute();
      expect(lab.history, isEmpty);
      await lab.stopRecording();
      expect(lab.locked, false);
      expect(lab.mediaType, 'audio');
      expect(lab.modelId, 'omni');
      expect(lab.mediaInfo!['durationSeconds'], 2);
      expect(await File(lab.mediaPath!).exists(), true);
      expect(await File(device.recordingPath!).exists(), false);
    },
  );
  test(
    'discard keeps the prior attachment and removes the raw recording',
    () async {
      lab.mediaPath = 'old-image.png';
      await lab.startRecording();
      await lab.stopRecording(discard: true);
      expect(device.cancelled, true);
      expect(lab.mediaPath, 'old-image.png');
      expect(await File(device.recordingPath!).exists(), false);
      expect(lab.locked, false);
    },
  );
  test('late stop trims actual WAV data to the runtime limit', () async {
    device.seconds = 32;
    await lab.startRecording();
    await lab.stopRecording();
    expect(lab.mediaInfo!['durationSeconds'], 30);
    final bytes = await File(lab.mediaPath!).readAsBytes();
    expect(bytes.length, 44 + 30 * 32000);
    expect(
      ByteData.sublistView(bytes).getUint32(40, Endian.little),
      30 * 32000,
    );
  });
  test(
    'backgrounding finalizes the recording; missing photos cannot run as text',
    () async {
      await lab.startRecording();
      final done = Completer<void>();
      lab.addListener(() {
        if (!lab.inputBusy && !done.isCompleted) done.complete();
      });
      lab.captureBackground(true);
      await done.future;
      expect(lab.recording, false);
      expect(lab.mediaType, 'audio');
      lab.captureBackground(false);
      lab.loadTask(builtinTasks.firstWhere((t) => t.inputKind == 'image'));
      await lab.execute();
      expect(lab.error, contains('写真'));
      expect(lab.history, isEmpty);
      expect(lab.mediaPath, null);
    },
  );
  test(
    'image sizes regenerate from the preserved source and leave previous images intact',
    () async {
      final source = File('${temp.path}/source.jpg');
      await source.writeAsBytes([1, 2, 3]);
      await lab.attach(source.path, 'image');
      final original = lab.imageSourcePath;
      final first = lab.mediaPath;
      expect(original, isNot(source.path));
      expect(await File(original!).readAsBytes(), [1, 2, 3]);
      await source.delete(); // OS-provided picker files can disappear.
      await lab.setImageMaxPixels(256);
      final small = lab.mediaPath;
      expect(lab.imageMaxPixels, 256);
      expect(lab.mediaInfo!['maxPixelSize'], 256);
      expect(small, isNot(first));
      await lab.setImageMaxPixels(2048);
      expect(runtime.sizes, [2048, 256, 2048]);
      expect(runtime.inputs, [original, original, original]);
      expect(await File(first!).exists(), true);
      expect(await File(small!).exists(), true);
      expect(lab.imageSourcePath, original);
      expect(lab.error, isEmpty);
    },
  );
  test(
    'failed resizing preserves size, attachment and previous result; partial files are cleaned',
    () async {
      final source = File('${temp.path}/source.jpg');
      await source.writeAsBytes([1, 2, 3]);
      await lab.attach(source.path, 'image');
      final path = lab.mediaPath,
          hash = lab.mediaHash,
          original = lab.imageSourcePath;
      final previous = <String, dynamic>{'id': 'previous'};
      lab.latest = previous;
      final filesBefore = await Directory(
        '${temp.path}/media',
      ).list(recursive: true).length;
      runtime.fail = true;
      await lab.setImageMaxPixels(512);
      expect(lab.imageMaxPixels, 2048);
      expect(lab.mediaPath, path);
      expect(lab.mediaHash, hash);
      expect(lab.imageSourcePath, original);
      expect(lab.latest, same(previous));
      expect(lab.locked, false);
      expect(lab.error, contains('image preparation failed'));
      expect(
        await Directory('${temp.path}/media').list(recursive: true).length,
        filesBefore,
      );
    },
  );
  test(
    'failed image attachment leaves no new source or partial image',
    () async {
      final source = File('${temp.path}/source.jpg');
      await source.writeAsBytes([1, 2, 3]);
      runtime.fail = true;
      expect(await lab.attach(source.path, 'image'), false);
      expect(lab.mediaPath, isNull);
      expect(lab.imageSourcePath, isNull);
      final files = await Directory(
        '${temp.path}/media',
      ).list(recursive: true).where((p) => p is File).toList();
      expect(files, isEmpty);
    },
  );
  test(
    'image preparation blocks decisions, task changes and duplicate resizing',
    () async {
      final source = File('${temp.path}/source.jpg');
      await source.writeAsBytes([1, 2, 3]);
      await lab.attach(source.path, 'image');
      runtime.started = Completer<void>();
      runtime.finish = Completer<void>();
      final changing = lab.setImageMaxPixels(512);
      await runtime.started!.future;
      expect(lab.locked, true);
      final task = lab.taskId;
      lab.loadTask(builtinTasks.last);
      await lab.execute();
      await lab.setImageMaxPixels(1024);
      expect(lab.taskId, task);
      expect(lab.history, isEmpty);
      expect(runtime.sizes, [2048, 512]);
      runtime.finish!.complete();
      await changing;
      expect(lab.imageMaxPixels, 512);
      expect(lab.locked, false);
    },
  );
  test(
    'legacy history keeps its processed source for repeated size changes',
    () async {
      final source = File('${temp.path}/legacy.png');
      await source.writeAsBytes([1, 2, 3]);
      lab.restore({
        'request': {
          'state': 'An image',
          'mediaPath': source.path,
          'mediaType': 'image',
          'mediaInfo': {'maxPixelSize': 2048, 'width': 100, 'height': 100},
        },
        'draft': <dynamic>[],
      });
      await lab.setImageMaxPixels(256);
      await lab.setImageMaxPixels(2048);
      expect(runtime.inputs, [source.path, source.path]);
      expect(lab.imageSourcePath, source.path);
      lab.removeMedia();
      expect(lab.imageSourcePath, isNull);
    },
  );
}
