import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d1_lab/domain.dart';
import 'package:d1_lab/storage.dart';

class LocalAsset extends ModelAsset {
  LocalAsset(this.endpoint, List<int> bytes, {super.previousVersions})
    : super(
        'test',
        'revision',
        'test.gguf',
        bytes.length,
        sha256.convert(bytes).toString(),
      );
  final Uri endpoint;
  @override
  Uri get uri => endpoint;
}

void main() {
  late Directory temp;
  setUp(
    () async =>
        temp = await Directory.systemTemp.createTemp('d1-storage-test-'),
  );
  tearDown(() async => temp.delete(recursive: true));
  test(
    'a resumed download validates content before promoting the partial file',
    () async {
      final bytes = utf8.encode('known model bytes for a range test');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final asset = LocalAsset(
        Uri.parse('http://127.0.0.1:${server.port}/model'),
        bytes,
      );
      final store = ModelStore(temp);
      await File(
        '${store.file(asset).path}.part',
      ).writeAsBytes(bytes.sublist(0, 5));
      server.listen((request) async {
        expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=5-');
        request.response.statusCode = 206;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 5-${bytes.length - 1}/${bytes.length}',
        );
        request.response.add(bytes.sublist(5));
        await request.response.close();
      });
      try {
        await store.download(asset, (_, __) {});
        expect(await store.file(asset).readAsBytes(), bytes);
        expect(await File('${store.file(asset).path}.part').exists(), false);
        expect(
          await File('${store.file(asset).path}.verified.json').exists(),
          true,
        );
      } finally {
        await server.close(force: true);
      }
    },
  );
  test('a changed file invalidates a cached verification receipt', () async {
    final bytes = utf8.encode('abc');
    final asset = LocalAsset(Uri.parse('http://unused'), bytes);
    final store = ModelStore(temp);
    await store.file(asset).writeAsBytes(bytes);
    await store.verify(asset);
    await store.file(asset).writeAsString('bad');
    await store.file(asset).setLastModified(DateTime.utc(2030));
    await expectLater(store.verify(asset), throwsFormatException);
  });
  test('a corrupt import cannot overwrite an installed model', () async {
    final bytes = utf8.encode('abc');
    final asset = LocalAsset(Uri.parse('http://unused'), bytes);
    final store = ModelStore(temp);
    await store.file(asset).writeAsBytes(bytes);
    final corrupt = await File(
      '${temp.path}/corrupt.gguf',
    ).writeAsString('bad');
    await expectLater(
      store.import(asset, corrupt.path, (_, __) {}),
      throwsFormatException,
    );
    expect(await store.file(asset).readAsBytes(), bytes);
  });

  test(
    'an installed earlier release keeps its verification and identity',
    () async {
      final oldBytes = utf8.encode('previous verified release');
      final currentBytes = utf8.encode(
        'new official release with new metadata',
      );
      final old = LocalAsset(Uri.parse('http://unused/old'), oldBytes);
      final asset = LocalAsset(
        Uri.parse('http://unused/new'),
        currentBytes,
        previousVersions: [old],
      );
      final store = ModelStore(temp);
      await store.file(old).writeAsBytes(oldBytes);
      await store.verify(old);
      final modified = (await store.file(old).stat()).modified;
      expect(await store.present(asset), true);
      expect(await store.verify(asset), same(old));
      expect((await store.file(old).stat()).modified, modified);
      final receipt = jsonDecode(
        await File('${store.file(old).path}.verified.json').readAsString(),
      );
      expect(receipt['sha256'], old.sha256);
      // An old-sized file still must match an explicitly supported digest.
      await store.file(asset).writeAsBytes(List.filled(oldBytes.length, 0));
      await store.file(asset).setLastModified(DateTime.utc(2030));
      await expectLater(store.verify(asset), throwsFormatException);
    },
  );

  test(
    'import accepts a known earlier release and rejects an unknown digest',
    () async {
      final oldBytes = utf8.encode('older GGUF');
      final old = LocalAsset(Uri.parse('http://unused'), oldBytes);
      final asset = LocalAsset(
        Uri.parse('http://unused'),
        utf8.encode('updated GGUF'),
        previousVersions: [old],
      );
      final store = ModelStore(temp);
      final imported = await File(
        '${temp.path}/import.gguf',
      ).writeAsBytes(oldBytes);
      await store.import(asset, imported.path, (_, __) {});
      expect(await store.verify(asset), same(old));
      await imported.writeAsBytes(List.filled(oldBytes.length, 1));
      await expectLater(
        store.import(asset, imported.path, (_, __) {}),
        throwsFormatException,
      );
      expect(await store.file(asset).readAsBytes(), oldBytes);
    },
  );

  for (final withReceipt in [false, true]) {
    test(
      'an earlier partial release restarts safely (receipt: $withReceipt)',
      () async {
        final bytes = utf8.encode('new release, verified end to end');
        final old = LocalAsset(
          Uri.parse('http://unused'),
          utf8.encode('old release'),
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final asset = LocalAsset(
          Uri.parse('http://127.0.0.1:${server.port}/model'),
          bytes,
          previousVersions: [old],
        );
        final store = ModelStore(temp);
        final part = File('${store.file(asset).path}.part');
        await part.writeAsString('old');
        if (withReceipt) {
          await File('${part.path}.json').writeAsString(
            jsonEncode({'bytes': old.bytes, 'sha256': old.sha256}),
          );
        }
        server.listen((request) async {
          expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
          request.response.add(bytes);
          await request.response.close();
        });
        try {
          final messages = <String>[];
          await store.download(asset, (_, message) => messages.add(message));
          expect(await store.file(asset).readAsBytes(), bytes);
          expect(messages, contains('配布版の変更に合わせて取得をやり直しています'));
          expect(await File('${part.path}.json').exists(), false);
        } finally {
          await server.close(force: true);
        }
      },
    );
  }

  test('a partial current release resumes across a catalog update', () async {
    final bytes = utf8.encode('new release, range resume');
    final old = LocalAsset(
      Uri.parse('http://unused'),
      utf8.encode('old release'),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final asset = LocalAsset(
      Uri.parse('http://127.0.0.1:${server.port}/model'),
      bytes,
      previousVersions: [old],
    );
    final store = ModelStore(temp);
    final part = File('${store.file(asset).path}.part');
    await part.writeAsBytes(bytes.sublist(0, 5));
    await File(
      '${part.path}.json',
    ).writeAsString(jsonEncode({'bytes': asset.bytes, 'sha256': asset.sha256}));
    server.listen((request) async {
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=5-');
      request.response.statusCode = 206;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 5-${bytes.length - 1}/${bytes.length}',
      );
      request.response.add(bytes.sublist(5));
      await request.response.close();
    });
    try {
      await store.download(asset, (_, __) {});
      expect(await store.file(asset).readAsBytes(), bytes);
      expect(await File('${part.path}.json').exists(), false);
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'HTTP 403 preserves installed models and current partial downloads',
    () async {
      final bytes = utf8.encode('official release');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final asset = LocalAsset(
        Uri.parse('http://127.0.0.1:${server.port}/model'),
        bytes,
      );
      final store = ModelStore(temp);
      await store.file(asset).writeAsBytes(bytes);
      final part = await File(
        '${store.file(asset).path}.part',
      ).writeAsBytes(bytes.sublist(0, 5));
      server.listen((request) async {
        request.response.statusCode = 403;
        request.response.write('<Error>AccessDenied</Error>');
        await request.response.close();
      });
      try {
        await expectLater(
          store.download(asset, (_, __) {}),
          throwsA(
            isA<HttpException>().having(
              (e) => e.message,
              'actionable message',
              contains('HTTP 403'),
            ),
          ),
        );
        expect(await part.readAsBytes(), bytes.sublist(0, 5));
        expect(await store.file(asset).readAsBytes(), bytes);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'deleting an asset removes only its model and temporary files; it can download again',
    () async {
      final bytes = utf8.encode('downloadable model');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final asset = LocalAsset(
        Uri.parse('http://127.0.0.1:${server.port}/model'),
        bytes,
      );
      final store = ModelStore(temp);
      var downloads = 0;
      server.listen((request) async {
        downloads++;
        expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
        request.response.add(bytes);
        await request.response.close();
      });
      try {
        await store.download(asset, (_, __) {});
        for (final suffix in ['.part', '.part.json', '.import']) {
          await File(
            '${store.file(asset).path}$suffix',
          ).writeAsString('partial');
        }
        final untouched = await File(
          '${temp.path}/other-model.gguf',
        ).writeAsString('keep');
        expect(await store.occupiedBytes(asset), greaterThan(bytes.length));
        await store.remove(asset);
        await store.remove(
          asset,
        ); // Also safe if the user deletes a partial download.
        expect(await store.present(asset), false);
        expect(await store.occupiedBytes(asset), 0);
        expect(await untouched.readAsString(), 'keep');
        await store.download(asset, (_, __) {});
        await store.verify(asset);
        expect(await store.file(asset).readAsBytes(), bytes);
        expect(downloads, 2);
      } finally {
        await server.close(force: true);
      }
    },
  );
}
