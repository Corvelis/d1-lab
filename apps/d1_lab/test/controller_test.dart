import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:decision_bridge/decision_bridge.dart';
import 'package:d1_lab/domain.dart';
import 'package:d1_lab/storage.dart';
import 'package:d1_lab/lab_controller.dart';

class VerifiedStore extends ModelStore {
  VerifiedStore(super.directory);
  final generations = <String, int>{};
  final verifications = <String>[];
  @override
  Future<String> identity(ModelAsset asset) async =>
      '${asset.filename}:${generations[asset.filename] ?? 0}';
  @override
  Future<ModelAsset> verify(ModelAsset asset) async {
    verifications.add(asset.filename);
    return asset;
  }
}

class RecordingRuntime implements DecisionRuntime {
  @override
  Future<Map<String, dynamic>> prepareImage(
    String input,
    String output, {
    int maxPixelSize = 2048,
  }) async => {};
  final events = <String>[];
  final requests = <Map<String, dynamic>>[];
  bool failSecond = false;
  int loaded = 0;
  String model = '';
  final loadRequests = <Map<String, dynamic>>[];
  Completer<void>? runStarted, finishRun, loadStarted, finishLoad;
  bool failRun = false;
  @override
  Future<Map<String, dynamic>> load(Map<String, dynamic> request) async {
    expect(events.isEmpty || events.last == 'unload', true);
    events.add('load');
    loaded++;
    model = (request['path'] as String).contains('3B')
        ? 'd1-3B'
        : 'd1-omni-600M';
    loadRequests.add(request);
    loadStarted?.complete();
    await finishLoad?.future;
    if (loaded == 2 && failSecond) throw StateError('allocation failed');
    return {'loadMs': 10};
  }

  @override
  Future<Map<String, dynamic>> run(Map<String, dynamic> request) async {
    events.add('run');
    requests.add(request);
    runStarted?.complete();
    await finishRun?.future;
    if (failRun) throw StateError('evaluation failed');
    return {'results': <dynamic>[], 'model': model};
  }

  @override
  Future<void> cancel() async => events.add('cancel');
  @override
  Future<void> unload() async => events.add('unload');
}

void main() {
  late Directory temp;
  late RecordingRuntime runtime;
  late LabController lab;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('d1-controller-test-');
    runtime = RecordingRuntime();
    lab = LabController(runtime: runtime);
    lab.directory = temp;
    lab.store = VerifiedStore(temp);
    lab.initialized = true;
    lab.questions = [
      lab.newQuestion(type: 'noul', instructions: 'Is this damaged?'),
    ];
    lab.available = {for (final m in modelSpecs) m.base.filename: true};
  });
  tearDown(() async {
    await lab.releaseRuntime();
    lab.dispose();
    await temp.delete(recursive: true);
  });
  test(
    'audio and image inputs reach the runtime without supplementary text',
    () async {
      lab.state = '';
      lab.modelId = 'omni';
      lab.available[modelSpecs.last.projector.filename] = true;
      for (final kind in ['audio', 'image']) {
        lab.inputKind = kind;
        lab.mediaType = kind;
        lab.mediaPath = null;
        await lab.execute();
        expect(lab.error, isNotEmpty);
        expect(runtime.requests, hasLength(kind == 'audio' ? 0 : 1));
        lab.mediaPath = kind == 'audio' ? 'voice.wav' : 'photo.png';
        await lab.execute();
        expect(lab.error, isEmpty);
        expect(runtime.requests.last['state'], '');
        expect(runtime.requests.last['mediaPath'], lab.mediaPath);
        expect(runtime.requests.last['mediaType'], kind);
        expect(lab.latest!['request']['state'], '');
      }
      lab.inputKind = 'text';
      lab.mediaPath = null;
      await lab.execute();
      expect(lab.error, contains('判断材料'));
      expect(runtime.requests, hasLength(2));
    },
  );
  test(
    'deletion releases the runtime, preserves other models and history, and blocks while busy',
    () async {
      final selected = modelSpecs.first;
      for (final asset in [selected.base, selected.projector]) {
        await lab.store.file(asset).writeAsString('model');
        await File(
          '${lab.store.file(asset).path}.part',
        ).writeAsString('partial');
      }
      final other = lab.store.file(modelSpecs.last.base);
      await other.writeAsString('other model');
      final history = File('${temp.path}/history.json');
      await history.writeAsString('[]');
      lab.busy = true;
      await lab.deleteModel(selected);
      expect(runtime.events, isEmpty);
      expect(await lab.store.file(selected.base).exists(), true);
      lab.busy = false;
      await lab.deleteModel(selected);
      expect(runtime.events, ['unload']);
      expect(await lab.store.file(selected.base).exists(), false);
      expect(await lab.store.file(selected.projector).exists(), false);
      expect(await other.readAsString(), 'other model');
      expect(await history.readAsString(), '[]');
      expect(lab.modelStoredBytes(selected), 0);
      expect(lab.needsDownload, true);
      expect(lab.busy, false);
      expect(lab.error, isEmpty);
    },
  );
  test(
    'comparison unloads the first model and sends both the same fixed request',
    () async {
      await lab.execute(compare: true);
      expect(runtime.events, [
        'load',
        'run',
        'unload',
        'load',
        'run',
        'unload',
      ]);
      expect(runtime.requests[0], runtime.requests[1]);
      expect(lab.history.single['runs'].length, 2);
      expect(await File('${temp.path}/history.json').exists(), true);
    },
  );
  test(
    'failed second model releases memory and does not save a partial comparison',
    () async {
      runtime.failSecond = true;
      await lab.execute(compare: true);
      expect(runtime.events.last, 'unload');
      expect(lab.busy, false);
      expect(lab.history, isEmpty);
      expect(lab.error, contains('allocation failed'));
    },
  );

  test(
    'reruns verify files and process changed inputs without reloading',
    () async {
      await lab.execute();
      final first = lab.latest!['runs'][0];
      expect(first['runtimeReused'], false);
      expect(first['runtimeRetained'], true);
      lab.state = 'Different input';
      lab.questions.single.instructions = 'Different question';
      await lab.execute();
      expect(runtime.events, ['load', 'run', 'run']);
      expect(runtime.requests[1]['state'], 'Different input');
      expect(
        runtime.requests[1]['questions'],
        isNot(runtime.requests[0]['questions']),
      );
      final second = lab.latest!['runs'][0];
      expect(second['runtimeReused'], true);
      expect(second['loadMs'], 0);
      expect(second['loadCallMs'], 0);
      expect(second['unloadMs'], 0);
      expect((lab.store as VerifiedStore).verifications.length, 2);
    },
  );
  test(
    'backend, context, model and replaced file identities require a reload',
    () async {
      await lab.execute();
      lab.backend = 'cpu';
      await lab.settingsChanged();
      await lab.execute();
      lab.contextTokens = 1024;
      await lab.execute();
      (lab.store as VerifiedStore).generations[modelSpecs.first.base.filename] =
          1;
      await lab.execute();
      lab.modelId = 'omni';
      await lab.execute();
      expect(runtime.loaded, 5);
      expect(runtime.events.where((e) => e == 'unload').length, 4);
      expect(lab.latest!['runs'][0]['runtimeReused'], false);
    },
  );
  test(
    'projector presence and identity invalidate the runtime; new media reuses it',
    () async {
      lab.available[modelSpecs.first.projector.filename] = true;
      await lab.execute();
      lab.mediaPath = 'first.png';
      lab.mediaType = 'image';
      await lab.execute();
      expect(runtime.loadRequests.last['projectorPath'], isNotNull);
      lab.mediaPath = 'second.png';
      await lab.execute();
      expect(lab.latest!['runs'][0]['runtimeReused'], true);
      expect(runtime.requests.last['mediaPath'], 'second.png');
      (lab.store as VerifiedStore).generations[modelSpecs
              .first
              .projector
              .filename] =
          1;
      await lab.execute();
      lab.mediaPath = null;
      await lab.execute();
      expect(runtime.loaded, 4);
      expect(runtime.loadRequests.last.containsKey('projectorPath'), false);
    },
  );
  test(
    'background and memory release cause the next run to initialize again',
    () async {
      await lab.execute();
      lab.captureBackground(true);
      await lab.releaseRuntime();
      expect(runtime.events.last, 'unload');
      await lab.execute(); // Background runs are blocked.
      expect(runtime.loaded, 1);
      lab.captureBackground(false);
      await lab.execute();
      expect(runtime.loaded, 2);
      await lab.releaseRuntime(); // Used by the memory-pressure callback.
      await lab.execute();
      expect(runtime.loaded, 3);
    },
  );
  test(
    'release waits for an in-flight operation, then discards the retained model',
    () async {
      runtime.runStarted = Completer<void>();
      runtime.finishRun = Completer<void>();
      final execution = lab.execute();
      await runtime.runStarted!.future;
      final released = lab.releaseRuntime();
      expect(runtime.events, ['load', 'run']);
      runtime.finishRun!.complete();
      await Future.wait([execution, released]);
      expect(runtime.events, ['load', 'run', 'unload']);
      expect(lab.latest!['runs'][0]['runtimeRetained'], false);
    },
  );
  test(
    'failed and cancelled passes release the cache and save no new result',
    () async {
      await lab.execute();
      runtime.failRun = true;
      await lab.execute();
      expect(runtime.events.last, 'unload');
      expect(lab.history.length, 1);
      runtime.failRun = false;
      runtime.runStarted = Completer<void>();
      runtime.finishRun = Completer<void>();
      final execution = lab.execute();
      await runtime.runStarted!.future;
      await lab.cancel();
      runtime.finishRun!.complete();
      await execution;
      expect(runtime.events.last, 'unload');
      expect(lab.history.length, 1);
      expect(lab.latest, isNull);
    },
  );
  test(
    'disabling retention persists the preference and restores loading on each run',
    () async {
      await lab.execute();
      lab.keepModelLoaded = false;
      await lab.settingsChanged();
      await lab.execute();
      await lab.execute();
      expect(runtime.events, [
        'load',
        'run',
        'unload',
        'load',
        'run',
        'unload',
        'load',
        'run',
        'unload',
      ]);
      expect(
        await File('${temp.path}/settings.json').readAsString(),
        contains('"keepModelLoaded":false'),
      );
      expect(lab.latest!['runs'][0]['runtimeRetained'], false);
    },
  );
  test(
    'comparison starts with fresh loads even after a retained run',
    () async {
      await lab.execute();
      await lab.execute(compare: true);
      expect(runtime.events, [
        'load',
        'run',
        'unload',
        'load',
        'run',
        'unload',
        'load',
        'run',
        'unload',
      ]);
      for (final run in lab.latest!['runs']) {
        expect(run['runtimeReused'], false);
        expect(run['runtimeRetained'], false);
      }
    },
  );
  test(
    'background during inference cancels, waits for completion and releases memory',
    () async {
      runtime.runStarted = Completer<void>();
      runtime.finishRun = Completer<void>();
      final execution = lab.execute();
      await runtime.runStarted!.future;
      lab.captureBackground(true);
      expect(runtime.events, ['load', 'run', 'cancel']);
      runtime.finishRun!.complete();
      await execution;
      await lab.releaseRuntime();
      expect(runtime.events, ['load', 'run', 'cancel', 'unload']);
      expect(lab.latest, isNull);
      expect(lab.history, isEmpty);
      expect(lab.busy, false);
    },
  );
  test(
    'preparing loads without a decision or history, and the first decision reuses it',
    () async {
      lab.keepModelLoaded = false;
      lab.questions = []; // No input or question is required for preparation.
      final previous = <String, dynamic>{'id': 'previous'};
      lab.latest = previous;
      await lab.prepareModel();
      expect(runtime.events, ['load']);
      expect(lab.modelReady, true);
      expect(lab.keepModelLoaded, true);
      expect(lab.modelPreparationMs, isNotNull);
      expect(lab.latest, same(previous));
      expect(lab.history, isEmpty);
      expect(await File('${temp.path}/history.json').exists(), false);
      expect(
        await File('${temp.path}/settings.json').readAsString(),
        contains('"keepModelLoaded":true'),
      );
      await lab.prepareModel();
      expect(runtime.events, ['load']);
      lab.questions = [
        lab.newQuestion(type: 'noul', instructions: 'Is this damaged?'),
      ];
      await lab.execute();
      expect(runtime.events, ['load', 'run']);
      expect(lab.latest!['runs'][0]['runtimeReused'], true);
      expect(lab.latest!['runs'][0]['loadCallMs'], 0);
      await lab.releaseRuntime();
      expect(lab.modelReady, false);
      expect(lab.modelPreparationMs, isNull);
    },
  );
  test(
    'image and audio models can be prepared before attaching media',
    () async {
      lab.inputKind = 'image';
      lab.available[modelSpecs.first.projector.filename] = true;
      await lab.prepareModel();
      expect(lab.modelReady, true);
      expect(runtime.loadRequests.last['projectorPath'], isNotNull);
      expect((lab.store as VerifiedStore).verifications, [
        modelSpecs.first.base.filename,
        modelSpecs.first.projector.filename,
      ]);
      lab.mediaPath = 'photo.png';
      lab.mediaType = 'image';
      await lab.execute();
      expect(lab.latest!['runs'][0]['runtimeReused'], true);
      lab.modelId = 'omni';
      lab.inputKind = 'audio';
      lab.mediaPath = null;
      lab.available[modelSpecs.last.projector.filename] = true;
      expect(lab.modelReady, false);
      await lab.prepareModel();
      expect(lab.modelReady, true);
      expect(
        runtime.loadRequests.last['projectorPath'],
        endsWith(modelSpecs.last.projector.filename),
      );
      lab.mediaPath = 'voice.wav';
      lab.mediaType = 'audio';
      await lab.execute();
      expect(lab.latest!['runs'][0]['runtimeReused'], true);
      expect(runtime.loaded, 2);
    },
  );
  test(
    'readiness follows model, backend, context and media requirements',
    () async {
      await lab.prepareModel();
      expect(lab.modelReady, true);
      lab.modelId = 'omni';
      expect(lab.modelReady, false);
      lab.modelId = '3b';
      lab.backend = 'cpu';
      expect(lab.modelReady, false);
      lab.backend = 'metal';
      lab.contextTokens = 512;
      expect(lab.modelReady, false);
      lab.contextTokens = 2048;
      lab.inputKind = 'image';
      expect(lab.modelReady, false);
      lab.inputKind = 'text';
      expect(lab.modelReady, true);
    },
  );
  test(
    'missing files cannot be prepared and allocated memory is released on load failure',
    () async {
      lab.available[modelSpecs.first.base.filename] = false;
      await lab.prepareModel();
      expect(runtime.events, isEmpty);
      expect(lab.error, contains('取得'));
      lab.available[modelSpecs.first.base.filename] = true;
      await lab.prepareModel();
      lab.backend = 'cpu';
      runtime.failSecond = true;
      await lab.prepareModel();
      expect(runtime.events, ['load', 'unload', 'load', 'unload']);
      expect(lab.modelReady, false);
      expect(lab.busy, false);
      expect(lab.preparingModel, false);
      expect(lab.history, isEmpty);
    },
  );
  test(
    'backgrounding during preparation cancels and releases after load completes',
    () async {
      runtime.loadStarted = Completer<void>();
      runtime.finishLoad = Completer<void>();
      final preparing = lab.prepareModel();
      await runtime.loadStarted!.future;
      expect(lab.preparingModel, true);
      expect(lab.modelReady, false);
      lab.captureBackground(true);
      runtime.finishLoad!.complete();
      await preparing;
      expect(runtime.events, ['load', 'cancel', 'unload']);
      expect(lab.busy, false);
      expect(lab.preparingModel, false);
      expect(lab.modelReady, false);
      expect(lab.history, isEmpty);
    },
  );
}
