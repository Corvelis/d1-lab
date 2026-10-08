import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:decision_bridge/decision_bridge.dart';
import 'package:path_provider/path_provider.dart';
import 'domain.dart';
import 'storage.dart';
import 'tasks.dart';
import 'capture.dart';
import 'media_storage.dart';
import 'package:flutter/services.dart';
import 'l10n/strings.dart';

const imageSizeOptions = [256, 512, 768, 1024, 1536, 2048];

class LabController extends ChangeNotifier {
  LabController({
    DecisionRuntime? runtime,
    CaptureDevice? capture,
    this.language = 'system',
    this.supportDirectory,
  }) : runtime = runtime ?? MethodChannelDecisionRuntime(),
       capture = capture ?? PluginCaptureDevice();
  final DecisionRuntime runtime;
  final CaptureDevice capture;
  final Directory? supportDirectory;
  bool inputBusy = false, recording = false;
  bool get locked => busy || inputBusy;
  bool _disposed = false, _backgrounded = false;
  bool keepModelLoaded = true;
  bool preparingModel = false;
  double? modelPreparationMs;
  bool _runtimeAllocated = false, _releaseAfterRun = false;
  String? _loadedKey;
  Map<String, dynamic>? _loadedOptions;
  Future<void> _runtimeRelease = Future<void>.value();
  Completer<void>? _executionDone;
  Future<void> _settingsWrites = Future<void>.value();
  Future<void> get settingsSaved => _settingsWrites;
  Duration recordingElapsed = Duration.zero;
  double recordingLevel = 0;
  Timer? _recordTimer;
  StreamSubscription<double>? _levels;
  StreamSubscription<bool>? _interruptions;
  final _recordClock = Stopwatch();
  String? _recordPath;
  String inputKind = 'text';
  String get automaticTaskKind => mediaPath == null ? inputKind : mediaType;
  String? get missingInput =>
      inputKind != 'text' && (mediaPath == null || mediaType != inputKind)
      ? inputKind == 'image'
            ? '写真を撮るか、写真から選んでください'
            : 'マイクで録音してください'
      : null;
  late ModelStore store;
  late Directory directory;
  bool initialized = false, busy = false, calibrated = true;
  bool deleting = false;
  bool _cancelled = false;
  String modelId = '3b', backend = 'metal', phase = '', error = '';
  String language;
  String get languageCode =>
      resolveLanguage(language, PlatformDispatcher.instance.locales);
  AppStrings get strings => AppStrings(languageCode);
  int contextTokens = 2048;
  int imageMaxPixels = 2048;
  double? progress;
  String state = '届いた商品が壊れていました。交換してもらえますか？';
  List<Question> questions = [];
  List<Map<String, dynamic>> history = [];
  List<D1Task> savedTasks = [];
  String? taskId = 'inquiry-jp';
  String taskTitle = '問い合わせを分類', taskCheck = '';
  bool taskModified = false;
  Map<String, bool> available = {};
  Map<String, int> storedBytes = {};
  ModelSpec get selectedModel => modelSpecs.firstWhere((m) => m.id == modelId);
  bool get needsProjector => inputKind != 'text' || mediaPath != null;
  bool get modelReady {
    final options = _loadedOptions;
    if (!_runtimeAllocated ||
        _loadedKey == null ||
        _releaseAfterRun ||
        options == null) {
      return false;
    }
    final path = options['path'] as String?;
    final projector = options['projectorPath'] as String?;
    return path?.endsWith('/${selectedModel.base.filename}') == true &&
        options['backend'] == backend &&
        options['contextTokens'] == contextTokens &&
        (needsProjector
            ? projector?.endsWith('/${selectedModel.projector.filename}') ==
                  true
            : projector == null);
  }

  bool get needsDownload =>
      available[selectedModel.base.filename] != true ||
      (needsProjector && available[selectedModel.projector.filename] != true);
  int modelStoredBytes(ModelSpec spec) =>
      (storedBytes[spec.base.filename] ?? 0) +
      (storedBytes[spec.projector.filename] ?? 0);
  Map<String, dynamic>? latest;
  String? mediaPath;
  String? imageSourcePath;
  String mediaType = 'image';
  String? mediaHash;
  Map<String, dynamic>? mediaInfo;
  int _nextId = 0;
  Question newQuestion({
    String type = 'choice',
    String instructions = '',
    String criteria = '',
  }) => Question(
    id: '${_nextId++}',
    type: type,
    instructions: instructions,
    criteria: criteria,
  );

  Future<void> init() async {
    try {
      directory = Directory(
        '${(supportDirectory ?? await getApplicationSupportDirectory()).path}/d1-lab',
      );
      await directory.create(recursive: true);
      store = ModelStore(Directory('${directory.path}/models'));
      final saved = File('${directory.path}/history.json');
      if (await saved.exists()) {
        history = List<Map<String, dynamic>>.from(
          (jsonDecode(await saved.readAsString()) as List).map(
            (j) => Map<String, dynamic>.from(j),
          ),
        );
      }
      final settings = File('${directory.path}/settings.json');
      await readTasks();
      if (await settings.exists()) {
        final j = jsonDecode(await settings.readAsString());
        modelId = j['modelId'] == '3b' ? '3b' : 'omni';
        backend = j['backend'] == 'cpu' ? 'cpu' : 'metal';
        calibrated = j['calibrated'] != false;
        keepModelLoaded = j['keepModelLoaded'] != false;
        imageMaxPixels = imageSizeOptions.contains(j['imageMaxPixels'])
            ? j['imageMaxPixels']
            : 2048;
        contextTokens = [512, 1024, 2048, 4096].contains(j['contextTokens'])
            ? j['contextTokens']
            : 2048;
        language = ['system', 'ja', 'en'].contains(j['language'])
            ? j['language']
            : 'system';
      }
      loadTask(languageCode == 'ja' ? builtinTasks.first : englishTasks.first);
      await refresh();
      initialized = true;
    } catch (e) {
      error = e.toString();
      initialized = true;
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    for (final spec in modelSpecs) {
      for (final asset in [spec.base, spec.projector]) {
        available[asset.filename] = await store.present(asset);
        storedBytes[asset.filename] = await store.occupiedBytes(asset);
      }
    }
    notifyListeners();
  }

  void loadTask(D1Task task) {
    if (locked) return;
    taskId = task.id;
    taskTitle = task.title;
    taskCheck = task.check;
    taskModified = false;
    inputKind = task.inputKind;
    if (inputKind == 'audio') modelId = 'omni';
    if (inputKind == 'image') modelId = '3b';
    mediaPath = null;
    imageSourcePath = null;
    mediaHash = null;
    mediaInfo = null;
    state = task.state;
    questions = [
      for (final q in task.questions)
        newQuestion(
          type: q.type,
          instructions: q.instructions,
          criteria: q.criteria,
        ),
    ];
    latest = null;
    error = '';
    notifyListeners();
  }

  Future<void> readTasks() async {
    final file = File('${directory.path}/tasks.json');
    if (await file.exists()) {
      savedTasks = (jsonDecode(await file.readAsString()) as List)
          .map((j) => D1Task.fromJson(Map<String, dynamic>.from(j)))
          .toList();
    }
  }

  Future<void> saveTask(String name, {String? kind}) async {
    if (locked) return;
    if (name.trim().isEmpty) throw const FormatException('タスク名を入力してください');
    final task = D1Task(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      title: name.trim(),
      description: '自分で保存した入力の補足と判定条件',
      inputKind: kind == null || kind == 'auto' ? automaticTaskKind : kind,
      state: state,
      language: '自分のタスク',
      questions: [
        for (final q in questions)
          TaskQuestion(q.type, q.instructions, q.criteria),
      ],
    );
    task.validate();
    final next = [task, ...savedTasks];
    await _writeTasks(next);
    savedTasks = next;
    taskId = task.id;
    taskTitle = task.title;
    taskCheck = '';
    if (inputKind != task.inputKind) latest = null;
    inputKind = task.inputKind;
    if (inputKind == 'audio') modelId = 'omni';
    if (mediaPath != null && mediaType != inputKind) {
      mediaPath = null;
      imageSourcePath = null;
      mediaHash = null;
      mediaInfo = null;
    }
    taskModified = false;
    notifyListeners();
  }

  Future<void> deleteTask(String id) async {
    if (locked) return;
    final next = savedTasks.where((t) => t.id != id).toList();
    await _writeTasks(next);
    savedTasks = next;
    notifyListeners();
  }

  Future<void> _writeTasks(List<D1Task> tasks) async {
    final temp = File('${directory.path}/tasks.json.tmp');
    await temp.writeAsString(
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
      flush: true,
    );
    await temp.rename('${directory.path}/tasks.json');
  }

  void changed() => notifyListeners();
  void draftChanged() {
    taskModified = true;
    taskCheck = '';
    notifyListeners();
  }

  Future<void> choosePhoto({required bool camera}) async {
    if (locked) return;
    inputBusy = true;
    error = '';
    notifyListeners();
    try {
      final path = await capture.photo(camera: camera);
      if (path != null && !_disposed) await attach(path, 'image');
    } catch (e) {
      error = _captureError(e);
    } finally {
      inputBusy = false;
      notifyListeners();
    }
  }

  Future<void> startRecording() async {
    if (locked) return;
    inputBusy = true;
    error = '';
    notifyListeners();
    try {
      if (!await capture.microphonePermission()) {
        throw const FormatException('マイクを使うには、iPhoneの設定でD1 Labのマイクを許可してください。');
      }
      if (_disposed || _backgrounded) return;
      final folder = Directory('${directory.path}/recordings');
      await folder.create(recursive: true);
      _recordPath =
          '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.wav';
      await capture.start(_recordPath!);
      if (_disposed || _backgrounded) {
        await capture.cancel();
        await _deleteRawRecording();
        return;
      }
      recording = true;
      recordingElapsed = Duration.zero;
      recordingLevel = 0;
      _recordClock
        ..reset()
        ..start();
      _levels = capture.levels.listen(
        (level) {
          recordingLevel = level;
          notifyListeners();
        },
        onError: (Object e) {
          error = _captureError(e);
        },
      );
      _interruptions = capture.interruptions.listen(
        (_) {
          if (recording) unawaited(stopRecording());
        },
        onError: (Object e) {
          if (recording) unawaited(stopRecording());
        },
      );
      _recordTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        recordingElapsed = _recordClock.elapsed;
        if (recordingElapsed >= const Duration(seconds: 30)) {
          unawaited(stopRecording());
        } else {
          notifyListeners();
        }
      });
    } catch (e) {
      error = _captureError(e);
      recording = false;
      _recordTimer?.cancel();
      await _levels?.cancel();
      await _interruptions?.cancel();
      try {
        await capture.cancel();
      } catch (_) {}
      await _deleteRawRecording();
    } finally {
      if (!recording) inputBusy = false;
      notifyListeners();
    }
  }

  Future<void> stopRecording({bool discard = false}) async {
    if (!recording) return;
    recording = false;
    _recordClock.stop();
    _recordTimer?.cancel();
    await _levels?.cancel();
    await _interruptions?.cancel();
    notifyListeners();
    try {
      if (discard) {
        await capture.cancel();
      } else {
        final path = await capture.stop() ?? _recordPath;
        if (path == null) throw const FormatException('録音を保存できませんでした。');
        final seconds = await boundRecording(path);
        if (!_disposed && await attach(path, 'audio')) {
          mediaInfo = {'durationSeconds': seconds, 'source': 'microphone'};
        }
      }
    } catch (e) {
      error = _captureError(e);
      try {
        await capture.cancel();
      } catch (_) {}
    } finally {
      await _deleteRawRecording();
      inputBusy = false;
      recordingLevel = 0;
      notifyListeners();
    }
  }

  void captureBackground(bool backgrounded) {
    _backgrounded = backgrounded;
    if (backgrounded && recording) unawaited(stopRecording());
    if (backgrounded) {
      if (_executionDone != null) {
        _cancelled = true;
        unawaited(
          runtime.cancel().catchError((Object e) {
            error = e.toString();
            notifyListeners();
          }),
        );
      }
      unawaited(releaseRuntime());
    }
  }

  Future<void> _deleteRawRecording() async {
    final path = _recordPath;
    _recordPath = null;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        /* Cleanup must not keep the input locked. */
      }
    }
  }

  String _captureError(Object e) {
    if (e is PlatformException) {
      if (e.code.toLowerCase().contains('denied') ||
          e.code.toLowerCase().contains('restricted')) {
        return 'カメラ・写真・マイクの使用が許可されていません。iPhoneの設定からD1 Labの権限を確認してください。';
      }
      return '入力を取得できませんでした。${e.message ?? e.code}';
    }
    return e.toString();
  }

  void removeMedia() {
    if (locked) return;
    mediaPath = null;
    imageSourcePath = null;
    mediaHash = null;
    mediaInfo = null;
    latest = null;
    notifyListeners();
  }

  Future<bool> attach(String path, String type) async {
    if (busy || _disposed) return false;
    final pending = <File>[];
    try {
      final folder = Directory('${directory.path}/media');
      await folder.create(recursive: true);
      final source = File(path);
      if (await source.length() > 50000000) {
        throw const FormatException('入力ファイルは50 MB以内にしてください');
      }
      final suffix = path.split('.').last.toLowerCase();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final target =
          '${folder.path}/$stamp.${type == 'image' ? 'png' : suffix}';
      pending.add(File(target));
      Map<String, dynamic>? info;
      String? original;
      if (type == 'image') {
        final originals = Directory('${folder.path}/sources');
        await originals.create(recursive: true);
        final extension =
            ['png', 'jpg', 'jpeg', 'heic', 'heif', 'webp'].contains(suffix)
            ? suffix
            : 'img';
        original = '${originals.path}/$stamp.$extension';
        pending.add(File(original));
        await source.copy(original);
        info = await runtime.prepareImage(
          original,
          target,
          maxPixelSize: imageMaxPixels,
        );
      } else {
        await source.copy(target);
      }
      final copied = File(target);
      final hash = await hashFile(copied.path);
      if (_disposed) return false;
      mediaPath = copied.path;
      imageSourcePath = original;
      mediaType = type;
      mediaHash = hash;
      mediaInfo = info;
      if (type == 'audio') modelId = 'omni';
      error = '';
      latest = null;
      pending.clear();
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    } finally {
      for (final file in pending) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          /* Keep the previous attachment if preparation fails. */
        }
      }
    }
  }

  Future<void> setImageMaxPixels(int value) async {
    if (locked ||
        _disposed ||
        !imageSizeOptions.contains(value) ||
        value == imageMaxPixels) {
      return;
    }
    inputBusy = true;
    error = '';
    notifyListeners();
    File? pending;
    final previousSize = imageMaxPixels;
    try {
      String? path, hash, retainedSource;
      Map<String, dynamic>? info;
      if (mediaPath != null && mediaType == 'image') {
        final original = imageSourcePath;
        final source = original != null && await File(original).exists()
            ? original
            : mediaPath!;
        retainedSource = source;
        final folder = Directory('${directory.path}/media');
        await folder.create(recursive: true);
        pending = File(
          '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.png',
        );
        info = await runtime.prepareImage(
          source,
          pending.path,
          maxPixelSize: value,
        );
        hash = await hashFile(pending.path);
        path = pending.path;
      }
      if (_disposed) return;
      imageMaxPixels = value;
      try {
        await settingsChanged();
      } catch (_) {
        imageMaxPixels = previousSize;
        rethrow;
      }
      if (path != null) {
        mediaPath = path;
        imageSourcePath = retainedSource;
        mediaHash = hash;
        mediaInfo = info;
        latest = null;
        pending = null;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (pending != null) {
        try {
          if (await pending.exists()) await pending.delete();
        } catch (_) {}
      }
      inputBusy = false;
      notifyListeners();
    }
  }

  Future<void> settingsChanged() {
    if (!keepModelLoaded ||
        (_loadedOptions != null &&
            (_loadedOptions!['backend'] != backend ||
                _loadedOptions!['contextTokens'] != contextTokens))) {
      unawaited(releaseRuntime());
    }
    notifyListeners();
    if (!initialized) return Future<void>.value();
    final encoded = jsonEncode({
      'modelId': modelId,
      'backend': backend,
      'calibrated': calibrated,
      'contextTokens': contextTokens,
      'language': language,
      'keepModelLoaded': keepModelLoaded,
      'imageMaxPixels': imageMaxPixels,
    });
    final write = _settingsWrites.then((_) async {
      final temporary = File('${directory.path}/settings.json.tmp');
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename('${directory.path}/settings.json');
    });
    _settingsWrites = write.catchError((Object e) {
      error = e.toString();
      if (!_disposed) notifyListeners();
    });
    return write;
  }

  void _update(double? p, String label) {
    progress = p;
    phase = label;
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    if (locked || !['system', 'ja', 'en'].contains(value)) return;
    language = value;
    try {
      await settingsChanged();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> acquireRequired() async {
    if (locked || !initialized) return;
    final spec = selectedModel;
    final assets = [spec.base, if (needsProjector) spec.projector];
    busy = true;
    _cancelled = false;
    error = '';
    phase = '取得を準備中';
    progress = null;
    notifyListeners();
    try {
      await _unloadRuntime();
      for (final asset in assets) {
        if (_cancelled) break;
        if (available[asset.filename] == true) continue;
        await store.download(
          asset,
          (p, label) => _update(p, '${asset.filename} · $label'),
        );
      }
      phase = _cancelled ? 'ダウンロードを中止しました' : '取得・検証が完了しました';
    } catch (e) {
      error = e.toString();
    } finally {
      await refresh();
      busy = false;
      progress = null;
      notifyListeners();
    }
  }

  Future<void> deleteModel(ModelSpec spec) async {
    if (locked || !initialized) return;
    busy = true;
    deleting = true;
    progress = null;
    error = '';
    phase = 'モデルファイルを削除中';
    notifyListeners();
    try {
      // Release native file handles before deleting the selected model's files.
      await _unloadRuntime(force: true);
      for (final asset in [spec.base, spec.projector]) {
        await store.remove(asset);
      }
      phase = 'モデルファイルを削除しました';
    } catch (e) {
      error = e.toString();
    } finally {
      await refresh();
      busy = false;
      deleting = false;
      notifyListeners();
    }
  }

  Future<void> acquire(ModelAsset asset, {String? importPath}) async {
    if (locked) return;
    busy = true;
    error = '';
    phase = '取得を準備中';
    progress = null;
    notifyListeners();
    try {
      await _unloadRuntime();
      if (importPath == null) {
        await store.download(asset, _update);
      } else {
        await store.import(asset, importPath, _update);
      }
      phase = '取得・検証が完了しました';
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      progress = null;
      await refresh();
    }
  }

  Future<void> cancel() async {
    if (deleting) return;
    _cancelled = true;
    store.cancel();
    phase = '中止を待っています…';
    notifyListeners();
    await runtime.cancel();
  }

  /// Release immediately when idle, or after the active native operation.
  Future<void> releaseRuntime() {
    _loadedKey = null;
    notifyListeners();
    if (_executionDone != null) {
      _releaseAfterRun = true;
      return _executionDone!.future;
    }
    return _unloadRuntime();
  }

  Future<void> _unloadRuntime({bool force = false}) {
    _loadedKey = null;
    _loadedOptions = null;
    modelPreparationMs = null;
    if (!_runtimeAllocated && !force) return _runtimeRelease;
    _runtimeAllocated = false;
    notifyListeners();
    _runtimeRelease = _runtimeRelease.then((_) => runtime.unload()).catchError((
      Object e,
    ) {
      error = e.toString();
      notifyListeners();
    });
    return _runtimeRelease;
  }

  void _checkActive() {
    if (_cancelled || _disposed || _backgrounded) {
      throw StateError('実行を中止しました');
    }
  }

  Future<
    ({
      bool reused,
      double verifyMs,
      double loadCallMs,
      double loadMs,
      double unloadMs,
      ModelAsset baseAsset,
    })
  >
  _ensureRuntime(
    ModelSpec spec, {
    required String usedBackend,
    required int usedContext,
    required bool projector,
    required bool allowReuse,
  }) async {
    final stage = Stopwatch()..start();
    await _runtimeRelease;
    _checkActive();
    _update(null, '${spec.name}：SHA-256を確認中');
    final baseAsset = await store.verify(spec.base);
    if (projector) await store.verify(spec.projector);
    final options = {
      'path': store.file(spec.base).path,
      'backend': usedBackend,
      'contextTokens': usedContext,
      if (projector) 'projectorPath': store.file(spec.projector).path,
    };
    final key = jsonEncode([
      options,
      await store.identity(spec.base),
      if (projector) await store.identity(spec.projector),
    ]);
    final verifyMs = stage.elapsedMicroseconds / 1000;
    _checkActive();
    final reused =
        allowReuse &&
        !_releaseAfterRun &&
        _runtimeAllocated &&
        _loadedKey == key;
    double loadCallMs = 0, unloadMs = 0, loadMs = 0;
    if (!reused) {
      stage.reset();
      await _unloadRuntime();
      unloadMs = stage.elapsedMicroseconds / 1000;
      _checkActive();
      _update(null, '${spec.name}：$usedBackendで読み込み中');
      stage.reset();
      _runtimeAllocated = true;
      final load = await runtime.load(options);
      loadCallMs = stage.elapsedMicroseconds / 1000;
      loadMs = (load['loadMs'] as num?)?.toDouble() ?? 0;
      _loadedKey = key;
      _loadedOptions = options;
    }
    _checkActive();
    return (
      reused: reused,
      verifyMs: verifyMs,
      loadCallMs: loadCallMs,
      loadMs: loadMs,
      unloadMs: unloadMs,
      baseAsset: baseAsset,
    );
  }

  /// Load the selected model before entering inputs, without running a decision.
  Future<void> prepareModel() async {
    if (locked || !initialized || _disposed || _backgrounded) return;
    if (!Platform.isIOS && !Platform.isMacOS) {
      error = 'この版の推論はiOS・macOSに対応しています';
      notifyListeners();
      return;
    }
    if (needsDownload) {
      error = '${selectedModel.name}をモデル画面で取得してください';
      notifyListeners();
      return;
    }
    busy = true;
    preparingModel = true;
    _executionDone = Completer<void>();
    _releaseAfterRun = false;
    _cancelled = false;
    error = '';
    progress = null;
    final wall = Stopwatch()..start();
    final spec = selectedModel;
    final usedBackend = backend;
    final usedContext = contextTokens;
    final projector = needsProjector;
    var succeeded = false;
    notifyListeners();
    try {
      if (!keepModelLoaded) {
        keepModelLoaded = true;
        await settingsChanged();
      }
      await _ensureRuntime(
        spec,
        usedBackend: usedBackend,
        usedContext: usedContext,
        projector: projector,
        allowReuse: true,
      );
      modelPreparationMs = wall.elapsedMicroseconds / 1000;
      phase = 'モデルの準備が完了しました';
      succeeded = true;
    } catch (e) {
      error = e.toString();
    } finally {
      if (!succeeded || _releaseAfterRun || _disposed || _backgrounded) {
        await _unloadRuntime();
      }
      _executionDone!.complete();
      _executionDone = null;
      busy = false;
      preparingModel = false;
      progress = null;
      notifyListeners();
    }
  }

  Future<void> execute({bool compare = false}) async {
    if (locked || _disposed || _backgrounded) return;
    if (missingInput != null) {
      error = missingInput!;
      notifyListeners();
      return;
    }
    final wall = Stopwatch()..start();
    Map<String, dynamic> request;
    try {
      request = snapshot(
        state,
        questions,
        calibrated,
        allowEmptyState: mediaPath != null,
      );
      request['taskTitle'] = taskTitle;
      request['taskId'] = taskId;
      request['taskModified'] = taskModified;
      request['inputKind'] = inputKind;
      if (mediaPath != null) {
        request['mediaPath'] = mediaPath;
        request['mediaType'] = mediaType;
        request['mediaSha256'] = mediaHash;
        request['mediaInfo'] = mediaInfo;
        if (imageSourcePath != null) {
          request['mediaSourcePath'] = imageSourcePath;
        }
      }
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return;
    }
    if (!Platform.isIOS && !Platform.isMacOS) {
      error = 'この版の推論はiOS・macOSに対応しています';
      notifyListeners();
      return;
    }
    final selected = compare
        ? modelSpecs
        : modelSpecs.where((m) => m.id == modelId).toList();
    if (mediaPath != null &&
        mediaType == 'audio' &&
        (compare || modelId != 'omni')) {
      error = '音声はomniで実行してください。3Bとの比較には対応していません';
      notifyListeners();
      return;
    }
    for (final spec in selected) {
      if (available[spec.base.filename] != true) {
        error = '${spec.name}をモデル画面で取得してください';
        notifyListeners();
        return;
      }
    }
    for (final spec in selected) {
      if (mediaPath != null && available[spec.projector.filename] != true) {
        error = '${spec.name}のプロジェクターをモデル画面で取得してください';
        notifyListeners();
        return;
      }
    }
    busy = true;
    _executionDone = Completer<void>();
    _releaseAfterRun = false;
    _cancelled = false;
    error = '';
    latest = null;
    progress = null;
    final runs = <Map<String, dynamic>>[];
    final draft = questions.map((q) => q.draft).toList();
    final usedBackend = backend;
    final usedContext = contextTokens;
    final retain = keepModelLoaded && !compare;
    var succeeded = false;
    notifyListeners();
    try {
      for (final spec in selected) {
        final modelWall = Stopwatch()..start();
        final prepared = await _ensureRuntime(
          spec,
          usedBackend: usedBackend,
          usedContext: usedContext,
          projector: request['mediaPath'] != null,
          allowReuse: retain,
        );
        var unloadMs = prepared.unloadMs;
        final stage = Stopwatch()..start();
        _update(null, '${spec.name}：判定中');
        stage.reset();
        final result = await runtime.run(request);
        final runCallMs = stage.elapsedMicroseconds / 1000;
        if (_cancelled || _disposed || _backgrounded) {
          throw StateError('実行を中止しました');
        }
        result['loadMs'] = prepared.loadMs;
        result['runtimeReused'] = prepared.reused;
        result['quantization'] = spec.quantization;
        result['revision'] = prepared.baseAsset.revision;
        result['sha256'] = prepared.baseAsset.sha256;
        result['contextTokens'] = usedContext;
        runs.add(result);
        if (!retain || _releaseAfterRun || _disposed || _backgrounded) {
          stage.reset();
          await _unloadRuntime();
          unloadMs += stage.elapsedMicroseconds / 1000;
        }
        result['runtimeRetained'] = _runtimeAllocated;
        result['verifyMs'] = prepared.verifyMs;
        result['loadCallMs'] = prepared.loadCallMs;
        result['runCallMs'] = runCallMs;
        result['unloadMs'] = unloadMs;
        result['endToEndMs'] = modelWall.elapsedMicroseconds / 1000;
      }
      final entry = <String, dynamic>{
        'version': 3,
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'at': DateTime.now().toIso8601String(),
        'request': request,
        'draft': draft,
        'runs': runs,
        'comparison': compare,
        'wallTotalMs': wall.elapsedMicroseconds / 1000,
      };
      history.insert(0, entry);
      if (history.length > 100) history.removeLast();
      latest = entry;
      await _saveHistory();
      phase = '判定が完了しました';
      succeeded = true;
    } catch (e) {
      error = e.toString();
    } finally {
      if (!succeeded ||
          !retain ||
          _releaseAfterRun ||
          _disposed ||
          _backgrounded) {
        await _unloadRuntime();
      }
      _executionDone!.complete();
      _executionDone = null;
      busy = false;
      progress = null;
      notifyListeners();
    }
  }

  Future<void> _saveHistory() async {
    final temp = File('${directory.path}/history.json.tmp');
    await temp.writeAsString(jsonEncode(history), flush: true);
    await temp.rename('${directory.path}/history.json');
  }

  Set<String> get _mediaReferences => {
    if (mediaPath != null) mediaPath!,
    if (imageSourcePath != null) imageSourcePath!,
    for (final entry in history)
      for (final key in ['mediaPath', 'mediaSourcePath'])
        if (entry['request']?[key] is String) entry['request'][key] as String,
  };

  Future<({int bytes, int files})> mediaUsage() =>
      MediaStorage(directory).usage();

  Future<void> _deleteData(Future<void> Function() action) async {
    if (locked || !initialized) return;
    busy = true;
    deleting = true;
    error = '';
    phase = '保存データを削除中';
    notifyListeners();
    try {
      await action();
      phase = '保存データを削除しました';
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      deleting = false;
      notifyListeners();
    }
  }

  Future<void> deleteHistory(String id) => _deleteData(() async {
    final previous = history;
    history = history.where((entry) => entry['id'] != id).toList();
    try {
      await _saveHistory();
    } catch (_) {
      history = previous;
      rethrow;
    }
    if (latest?['id'] == id) latest = null;
    await MediaStorage(directory).removeUnused(_mediaReferences);
  });

  Future<void> deleteUnusedMedia() =>
      _deleteData(() => MediaStorage(directory).removeUnused(_mediaReferences));

  Future<void> deleteHistoryAndMedia() => _deleteData(() async {
    final previous = history;
    history = [];
    try {
      await _saveHistory();
    } catch (_) {
      history = previous;
      rethrow;
    }
    latest = null;
    mediaPath = null;
    imageSourcePath = null;
    mediaHash = null;
    mediaInfo = null;
    await MediaStorage(directory).removeUnused({});
  });

  void restore(Map<String, dynamic> entry) {
    if (locked) return;
    taskId = entry['request']['taskId'];
    taskTitle = entry['request']['taskTitle'] ?? '履歴から読み込んだタスク';
    taskCheck = '';
    taskModified = entry['request']['taskModified'] == true;
    state = entry['request']['state'];
    mediaPath = entry['request']['mediaPath'];
    imageSourcePath = entry['request']['mediaSourcePath'];
    mediaType = entry['request']['mediaType'] ?? 'image';
    inputKind =
        entry['request']['inputKind'] ??
        (mediaPath == null ? 'text' : mediaType);
    mediaHash = entry['request']['mediaSha256'];
    mediaInfo = entry['request']['mediaInfo'];
    if (mediaType == 'image' &&
        imageSizeOptions.contains(mediaInfo?['maxPixelSize'])) {
      imageMaxPixels = mediaInfo!['maxPixelSize'];
    }
    calibrated = entry['request']['calibrated'] != false;
    questions = (entry['draft'] as List)
        .map(
          (q) => newQuestion(
            type: q['type'],
            instructions: q['instructions'],
            criteria: q['criteria'],
          ),
        )
        .toList();
    latest = entry;
    error = '';
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(releaseRuntime());
    _recordTimer?.cancel();
    unawaited(_levels?.cancel());
    unawaited(_interruptions?.cancel());
    unawaited(() async {
      try {
        await capture.cancel();
        await _deleteRawRecording();
        await capture.dispose();
      } catch (_) {}
    }());
    super.dispose();
  }
}
