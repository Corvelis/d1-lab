import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

/// Kept separate from inference so capture can be tested without native devices.
abstract class CaptureDevice {
  Future<String?> photo({required bool camera});
  Future<bool> microphonePermission();
  Future<void> start(String path);
  Future<String?> stop();
  Future<void> cancel();
  Stream<double> get levels;
  Stream<bool> get interruptions;
  Future<void> dispose();
}

class PluginCaptureDevice implements CaptureDevice {
  final _picker = ImagePicker();
  AudioRecorder? _recorder;
  AudioRecorder get recorder => _recorder ??= AudioRecorder();
  @override
  Future<String?> photo({required bool camera}) async =>
      (await _picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        requestFullMetadata: false,
      ))?.path;
  @override
  Future<bool> microphonePermission() => recorder.hasPermission();
  @override
  Future<void> start(String path) => recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    ),
    path: path,
  );
  @override
  Future<String?> stop() => recorder.stop();
  @override
  Future<void> cancel() async {
    await _recorder?.cancel();
  }

  @override
  Stream<double> get levels => recorder
      .onAmplitudeChanged(const Duration(milliseconds: 150))
      .map((a) => ((a.current + 60) / 60).clamp(0.0, 1.0));
  @override
  Stream<bool> get interruptions => recorder
      .onStateChanged()
      .where((s) => s == RecordState.pause || s == RecordState.stop)
      .map((_) => true);
  @override
  Future<void> dispose() async {
    await _recorder?.dispose();
  }
}

/// Stop latency must not produce a recording longer than the runtime's 30s limit.
/// This only modifies the app's own recording, never a user's imported audio.
Future<double> boundRecording(String path, {int maxSeconds = 30}) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  final data = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
  if (bytes.length < 44 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('録音データを読み込めません。もう一度録音してください。');
  }
  int? rate, align, dataAt, dataSize;
  for (int at = 12; at + 8 <= bytes.length;) {
    final length = data.getUint32(at + 4, Endian.little);
    if (at + 8 + length > bytes.length) break;
    if (tag(at) == 'fmt ' && length >= 16) {
      if (data.getUint16(at + 8, Endian.little) != 1) {
        throw const FormatException('録音はPCM WAV形式で行ってください。');
      }
      rate = data.getUint32(at + 12, Endian.little);
      align = data.getUint16(at + 20, Endian.little);
    }
    if (tag(at) == 'data') {
      dataAt = at;
      dataSize = length;
    }
    at += 8 + length + (length % 2);
  }
  if (rate == null ||
      align == null ||
      rate == 0 ||
      align == 0 ||
      dataAt == null ||
      dataSize == null ||
      dataSize == 0) {
    throw const FormatException('音声が録音されていません。もう一度録音してください。');
  }
  final size = math.min(dataSize, rate * align * maxSeconds);
  if (size < dataSize) {
    data.setUint32(dataAt + 4, size, Endian.little);
    data.setUint32(4, dataAt + 8 + size - 8, Endian.little);
    await file.writeAsBytes(bytes.sublist(0, dataAt + 8 + size), flush: true);
  }
  return size / (rate * align);
}
