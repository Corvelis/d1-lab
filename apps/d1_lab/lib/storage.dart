import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'domain.dart';

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Future<String> hashFile(String path) => Isolate.run(() async {
  final sink = _DigestSink();
  final conversion = sha256.startChunkedConversion(sink);
  await for (final bytes in File(path).openRead()) {
    conversion.add(bytes);
  }
  conversion.close();
  return sink.value.toString();
});

class ModelStore {
  ModelStore(this.directory);
  final Directory directory;
  HttpClient? _client;
  bool _cancelled = false;
  File file(ModelAsset asset) => File('${directory.path}/${asset.filename}');

  /// Identity of the verified file, so replaced weights are never reused.
  Future<String> identity(ModelAsset asset) async {
    final stat = await file(asset).stat();
    return '${file(asset).path}:${asset.sha256}:${stat.size}:'
        '${stat.modified.microsecondsSinceEpoch}:${stat.changed.microsecondsSinceEpoch}';
  }

  Future<bool> present(ModelAsset asset) async {
    if (!await file(asset).exists()) return false;
    final bytes = await file(asset).length();
    return asset.supportedVersions.any((version) => version.bytes == bytes);
  }

  Iterable<File> _ownedFiles(ModelAsset asset) sync* {
    final path = file(asset).path;
    for (final suffix in [
      '',
      '.part',
      '.part.json',
      '.import',
      '.verified.json',
    ]) {
      yield File('$path$suffix');
    }
  }

  Future<int> occupiedBytes(ModelAsset asset) async {
    var bytes = 0;
    for (final owned in _ownedFiles(asset)) {
      if (await owned.exists()) bytes += await owned.length();
    }
    return bytes;
  }

  /// Remove only the selected asset and its download/import/verification files.
  Future<void> remove(ModelAsset asset) async {
    for (final owned in _ownedFiles(asset)) {
      if (await owned.exists()) await owned.delete();
    }
  }

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<ModelAsset> verify(ModelAsset asset) async {
    final target = file(asset);
    if (!await present(asset)) {
      throw const FormatException('モデルが未取得、または容量が一致しません');
    }
    final stat = await target.stat();
    final candidates = asset.supportedVersions
        .where((version) => version.bytes == stat.size)
        .toList();
    final receipt = File('${target.path}.verified.json');
    if (await receipt.exists()) {
      try {
        final data = jsonDecode(await receipt.readAsString());
        if (data['modified'] == stat.modified.microsecondsSinceEpoch &&
            data['bytes'] == stat.size) {
          for (final candidate in candidates) {
            if (data['sha256'] == candidate.sha256) return candidate;
          }
        }
      } catch (_) {
        /* An incomplete receipt must trigger verification. */
      }
    }
    final digest = await hashFile(target.path);
    final matches = candidates.where((version) => version.sha256 == digest);
    if (matches.isEmpty) {
      throw const FormatException('SHA-256が一致しません。モデルを再取得してください');
    }
    await receipt.writeAsString(
      jsonEncode({
        'sha256': digest,
        'modified': stat.modified.microsecondsSinceEpoch,
        'bytes': stat.size,
      }),
      flush: true,
    );
    return matches.first;
  }

  Future<void> download(
    ModelAsset asset,
    void Function(double?, String) progress,
  ) async {
    _cancelled = false;
    await directory.create(recursive: true);
    final part = File('${file(asset).path}.part');
    final partReceipt = File('${part.path}.json');
    int offset = await part.exists() ? await part.length() : 0;
    var sameVersion = asset.previousVersions.isEmpty;
    if (await partReceipt.exists()) {
      try {
        final data = jsonDecode(await partReceipt.readAsString());
        sameVersion =
            data['sha256'] == asset.sha256 && data['bytes'] == asset.bytes;
      } catch (_) {
        sameVersion = false;
      }
    }
    // Never append bytes from an updated release to an older partial file.
    if (offset > asset.bytes || (offset > 0 && !sameVersion)) {
      await part.delete();
      if (await partReceipt.exists()) await partReceipt.delete();
      if (!sameVersion) progress(null, '配布版の変更に合わせて取得をやり直しています');
      offset = 0;
    }
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    IOSink? sink;
    try {
      if (offset < asset.bytes) {
        final request = await _client!.getUrl(asset.uri);
        if (offset > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        }
        final response = await request.close();
        if (response.statusCode != 200 && response.statusCode != 206) {
          if (response.statusCode == 403) {
            throw const HttpException(
              '配布先へのアクセスが拒否されました（HTTP 403）。時間をおいて再試行してください。公式GGUFのファイル取り込みも使えます。',
            );
          }
          throw HttpException('取得失敗: HTTP ${response.statusCode}');
        }
        if (response.statusCode == 200) offset = 0;
        if (response.statusCode == 206 &&
            !(response.headers.value(HttpHeaders.contentRangeHeader) ?? '')
                .startsWith('bytes $offset-')) {
          throw const HttpException('再開位置が一致しません');
        }
        await partReceipt.writeAsString(
          jsonEncode({'sha256': asset.sha256, 'bytes': asset.bytes}),
          flush: true,
        );
        sink = part.openWrite(
          mode: offset == 0 ? FileMode.write : FileMode.append,
        );
        int received = offset;
        await for (final chunk in response) {
          if (_cancelled) throw const HttpException('ダウンロードを中止しました');
          received += chunk.length;
          if (received > asset.bytes) {
            throw const HttpException('配布ファイル容量が一致しません');
          }
          sink.add(chunk);
          progress(
            received / asset.bytes,
            '${(received / 1000000).toStringAsFixed(0)} / ${(asset.bytes / 1000000).toStringAsFixed(0)} MB',
          );
        }
        await sink.flush();
        await sink.close();
        sink = null;
      }
      if (_cancelled) throw const HttpException('ダウンロードを中止しました');
      if (await part.length() != asset.bytes) {
        throw const HttpException('取得が途中で終了しました。再開できます');
      }
      progress(null, 'SHA-256を検証中');
      if (await hashFile(part.path) != asset.sha256) {
        await part.delete();
        if (await partReceipt.exists()) await partReceipt.delete();
        throw const FormatException('SHA-256が一致しません');
      }
      if (_cancelled) throw const HttpException('ダウンロードを中止しました');
      await part.rename(file(asset).path);
      if (await partReceipt.exists()) await partReceipt.delete();
      await verify(asset);
    } finally {
      await sink?.close();
      _client?.close(force: true);
      _client = null;
    }
  }

  Future<void> import(
    ModelAsset asset,
    String path,
    void Function(double?, String) progress,
  ) async {
    if (path == file(asset).path) {
      await verify(asset);
      return;
    }
    await directory.create(recursive: true);
    final source = File(path);
    final size = await source.length();
    final candidates = asset.supportedVersions.where(
      (version) => version.bytes == size,
    );
    if (candidates.isEmpty) {
      throw const FormatException('この配布モデルとファイル容量が一致しません');
    }
    progress(null, 'SHA-256を検証中');
    final digest = await hashFile(path);
    if (!candidates.any((version) => version.sha256 == digest)) {
      throw const FormatException('指定の公式GGUFとSHA-256が一致しません');
    }
    final part = await source.copy('${file(asset).path}.import');
    await part.rename(file(asset).path);
    await verify(asset);
  }
}
