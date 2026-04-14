import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;
  late Fspath root;

  setUp(() {
    currentCaseMode = CaseMode.sensitive;
    tempDir = Directory.systemTemp.createTempSync('unison_remote_sync_test_');
    root = Fspath.fromLocal(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Helper: create a loopback client+server pair.
  (RpcClient, RpcServer, RemoteSyncClient) _setup() {
    final (conn1, conn2) = ConnectionManager.createLoopback();
    final registry = CommandRegistry();
    registerSyncCommands(registry, root);
    final server = RpcServer(conn2.input, conn2.output, registry);
    server.start();
    final client = RpcClient(conn1.input, conn1.output);
    return (client, server, RemoteSyncClient(client));
  }

  Future<void> _teardown(RpcClient client, RpcServer server) async {
    await client.close();
    await server.stop();
  }

  group('Remote sync commands via loopback', () {
    test('ping', () async {
      final (client, server, remote) = _setup();
      expect(await remote.ping(), isTrue);
      await _teardown(client, server);
    });

    test('version', () async {
      final (client, server, remote) = _setup();
      final (ver, name) = await remote.version();
      expect(ver, protocolVersion);
      expect(name, contains('unison-dart'));
      await _teardown(client, server);
    });

    test('stat for existing file', () async {
      File('${tempDir.path}/hello.txt').writeAsStringSync('Hello!');
      final (client, server, remote) = _setup();

      final info = await remote.stat(SyncPath.fromString('hello.txt'));
      expect(info.typ, FileType.file);
      expect(info.desc.length, 6);

      await _teardown(client, server);
    });

    test('stat for missing file', () async {
      final (client, server, remote) = _setup();
      final info = await remote.stat(SyncPath.fromString('nope.txt'));
      expect(info.typ, FileType.absent);
      await _teardown(client, server);
    });

    test('children lists directory', () async {
      File('${tempDir.path}/a.txt').writeAsStringSync('a');
      File('${tempDir.path}/b.txt').writeAsStringSync('b');
      Directory('${tempDir.path}/sub').createSync();

      final (client, server, remote) = _setup();
      final names = await remote.children(SyncPath.empty);
      final rawNames = names.map((n) => n.raw).toSet();
      expect(rawNames, containsAll(['a.txt', 'b.txt', 'sub']));
      await _teardown(client, server);
    });

    test('exists', () async {
      File('${tempDir.path}/exists.txt').writeAsStringSync('yes');
      final (client, server, remote) = _setup();

      expect(await remote.exists(SyncPath.fromString('exists.txt')), isTrue);
      expect(await remote.exists(SyncPath.fromString('nope.txt')), isFalse);

      await _teardown(client, server);
    });

    test('readFile + writeFile roundtrip', () async {
      final (client, server, remote) = _setup();

      await remote.writeFile(
        SyncPath.fromString('written.txt'),
        Uint8List.fromList(utf8.encode('Remote write!')),
      );

      expect(
        File('${tempDir.path}/written.txt').readAsStringSync(),
        'Remote write!',
      );

      final data = await remote.readFile(SyncPath.fromString('written.txt'));
      expect(utf8.decode(data), 'Remote write!');

      await _teardown(client, server);
    });

    test('mkdir + exists', () async {
      final (client, server, remote) = _setup();

      await remote.mkdir(SyncPath.fromString('new_dir/sub'));
      expect(
        Directory('${tempDir.path}/new_dir/sub').existsSync(),
        isTrue,
      );

      await _teardown(client, server);
    });

    test('delete file', () async {
      File('${tempDir.path}/todel.txt').writeAsStringSync('bye');
      final (client, server, remote) = _setup();

      await remote.delete(SyncPath.fromString('todel.txt'));
      expect(File('${tempDir.path}/todel.txt').existsSync(), isFalse);

      await _teardown(client, server);
    });

    test('rename', () async {
      File('${tempDir.path}/old.txt').writeAsStringSync('data');
      final (client, server, remote) = _setup();

      await remote.rename(
        SyncPath.fromString('old.txt'),
        SyncPath.fromString('new.txt'),
      );

      expect(File('${tempDir.path}/old.txt').existsSync(), isFalse);
      expect(File('${tempDir.path}/new.txt').readAsStringSync(), 'data');

      await _teardown(client, server);
    });

    test('copyFileAtomic', () async {
      final (client, server, remote) = _setup();

      await remote.copyFileAtomic(
        SyncPath.fromString('atomic.txt'),
        Uint8List.fromList(utf8.encode('Atomic content')),
        Props(
          permissions: 0x1ED,
          modTime: DateTime(2024, 6, 15),
          length: 14,
        ),
      );

      expect(
        File('${tempDir.path}/atomic.txt').readAsStringSync(),
        'Atomic content',
      );

      await _teardown(client, server);
    });

    test('readFileStream for large file', () async {
      // Create a 200KB file
      final bigData = Uint8List.fromList(
        List.generate(200000, (i) => i % 256),
      );
      File('${tempDir.path}/big.bin').writeAsBytesSync(bigData);

      final (client, server, remote) = _setup();

      final stream =
          await remote.readFileStream(SyncPath.fromString('big.bin'));
      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }

      expect(chunks.length, bigData.length);
      expect(Uint8List.fromList(chunks), equals(bigData));

      await _teardown(client, server);
    });

    test('buildArchive', () async {
      Directory('${tempDir.path}/tree').createSync();
      File('${tempDir.path}/tree/a.txt').writeAsStringSync('a');
      File('${tempDir.path}/tree/b.txt').writeAsStringSync('b');

      final (client, server, remote) = _setup();

      final archive =
          await remote.buildArchive(SyncPath.fromString('tree'), false);
      expect(archive, isA<ArchiveDir>());
      final dir = archive as ArchiveDir;
      expect(dir.children.length, 2);

      await _teardown(client, server);
    });

    test('multiple sequential commands', () async {
      final (client, server, remote) = _setup();

      for (var i = 0; i < 10; i++) {
        await remote.writeFile(
          SyncPath.fromString('seq_$i.txt'),
          Uint8List.fromList(utf8.encode('data $i')),
        );
      }

      for (var i = 0; i < 10; i++) {
        final data =
            await remote.readFile(SyncPath.fromString('seq_$i.txt'));
        expect(utf8.decode(data), 'data $i');
      }

      await _teardown(client, server);
    });
  });
}
