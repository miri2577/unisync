import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('Message framing', () {
    test('encode/decode request roundtrip', () {
      final msg = RpcMessage(
        type: MessageType.request,
        messageId: 42,
        commandName: 'ping',
        payload: Uint8List.fromList(utf8.encode('hello')),
      );

      final encoded = encodeMessage(msg);
      final decoded = decodeMessage(encoded);

      expect(decoded.type, MessageType.request);
      expect(decoded.messageId, 42);
      expect(decoded.commandName, 'ping');
      expect(utf8.decode(decoded.payload), 'hello');
    });

    test('encode/decode normalResult roundtrip', () {
      final msg = RpcMessage(
        type: MessageType.normalResult,
        messageId: 7,
        payload: Uint8List.fromList([1, 2, 3, 4, 5]),
      );

      final encoded = encodeMessage(msg);
      final decoded = decodeMessage(encoded);

      expect(decoded.type, MessageType.normalResult);
      expect(decoded.messageId, 7);
      expect(decoded.payload, [1, 2, 3, 4, 5]);
    });

    test('encode/decode error roundtrip', () {
      final errorMsg = 'Something went wrong';
      final msg = RpcMessage(
        type: MessageType.transientError,
        messageId: 99,
        payload: Uint8List.fromList(utf8.encode(errorMsg)),
      );

      final encoded = encodeMessage(msg);
      final decoded = decodeMessage(encoded);

      expect(decoded.type, MessageType.transientError);
      expect(utf8.decode(decoded.payload), errorMsg);
    });

    test('empty payload roundtrip', () {
      final msg = RpcMessage(
        type: MessageType.normalResult,
        messageId: 1,
        payload: Uint8List(0),
      );

      final encoded = encodeMessage(msg);
      final decoded = decodeMessage(encoded);

      expect(decoded.payload, isEmpty);
    });

    test('large message ID roundtrip', () {
      final msg = RpcMessage(
        type: MessageType.normalResult,
        messageId: 0x7FFFFFFF,
        payload: Uint8List(0),
      );

      final encoded = encodeMessage(msg);
      final decoded = decodeMessage(encoded);

      expect(decoded.messageId, 0x7FFFFFFF);
    });

    test('checksum detects corruption', () {
      final msg = RpcMessage(
        type: MessageType.normalResult,
        messageId: 1,
        payload: Uint8List.fromList([42]),
      );

      final encoded = encodeMessage(msg);
      // Corrupt one byte in the body
      encoded[6] = encoded[6] ^ 0xFF;

      expect(
        () => decodeMessage(encoded),
        throwsA(isA<FormatException>()),
      );
    });

    test('too short data throws', () {
      expect(
        () => decodeMessage(Uint8List(3)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('CommandRegistry', () {
    test('register and retrieve handler', () {
      final reg = CommandRegistry();
      reg.register('test', (payload) async => Uint8List(0));
      expect(reg.get('test'), isNotNull);
      expect(reg.get('unknown'), isNull);
    });

    test('names returns all registered', () {
      final reg = CommandRegistry();
      reg.register('a', (p) async => Uint8List(0));
      reg.register('b', (p) async => Uint8List(0));
      expect(reg.names, containsAll(['a', 'b']));
    });
  });

  group('RpcClient + RpcServer integration', () {
    test('client calls server and gets response', () async {
      // Create loopback pipes
      final (conn1, conn2) = ConnectionManager.createLoopback();

      // Server side
      final registry = CommandRegistry();
      registry.register('echo', (payload) async {
        return Uint8List.fromList([...payload, ...payload]); // echo doubled
      });
      registry.register('greet', (payload) async {
        final name = utf8.decode(payload);
        return Uint8List.fromList(utf8.encode('Hello, $name!'));
      });

      final server = RpcServer(conn2.input, conn2.output, registry);
      server.start();

      // Client side
      final client = RpcClient(conn1.input, conn1.output);

      // Test echo
      final echoResult = await client.call(
        'echo',
        Uint8List.fromList([1, 2, 3]),
      );
      expect(echoResult, [1, 2, 3, 1, 2, 3]);

      // Test greet
      final greetResult = await client.call(
        'greet',
        Uint8List.fromList(utf8.encode('World')),
      );
      expect(utf8.decode(greetResult), 'Hello, World!');

      await client.close();
      await server.stop();
      await conn1.close();
      await conn2.close();
    });

    test('server returns error for unknown command', () async {
      final (conn1, conn2) = ConnectionManager.createLoopback();

      final registry = CommandRegistry();
      final server = RpcServer(conn2.input, conn2.output, registry);
      server.start();

      final client = RpcClient(conn1.input, conn1.output);

      try {
        await client.call('nonexistent', Uint8List(0));
        fail('Should have thrown');
      } on RpcFatalError catch (e) {
        expect(e.message, contains('Unknown command'));
      } finally {
        await client.close();
        await server.stop();
        await conn1.close();
        await conn2.close();
      }
    });

    test('server returns transient error on handler exception', () async {
      final (conn1, conn2) = ConnectionManager.createLoopback();

      final registry = CommandRegistry();
      registry.register('fail', (payload) async {
        throw Exception('intentional failure');
      });

      final server = RpcServer(conn2.input, conn2.output, registry);
      server.start();

      final client = RpcClient(conn1.input, conn1.output);

      try {
        await client.call('fail', Uint8List(0));
        fail('Should have thrown');
      } on RpcTransientError catch (e) {
        expect(e.message, contains('intentional failure'));
      } finally {
        await client.close();
        await server.stop();
        await conn1.close();
        await conn2.close();
      }
    });

    test('multiple sequential calls work', () async {
      final (conn1, conn2) = ConnectionManager.createLoopback();

      final registry = CommandRegistry();
      registry.register('add', (payload) async {
        final dec = MarshalDecoder(payload);
        final a = dec.readInt();
        final b = dec.readInt();
        final enc = MarshalEncoder();
        enc.writeInt(a + b);
        return enc.toBytes();
      });

      final server = RpcServer(conn2.input, conn2.output, registry);
      server.start();

      final client = RpcClient(conn1.input, conn1.output);

      for (var i = 0; i < 10; i++) {
        final enc = MarshalEncoder();
        enc.writeInt(i);
        enc.writeInt(i * 10);
        final result = await client.call('add', enc.toBytes());
        final dec = MarshalDecoder(result);
        expect(dec.readInt(), i + i * 10);
      }

      await client.close();
      await server.stop();
      await conn1.close();
      await conn2.close();
    });
  });

  group('MessageType', () {
    test('fromCode roundtrip', () {
      for (final t in MessageType.values) {
        expect(MessageType.fromCode(t.code), t);
      }
    });

    test('fromCode throws for unknown', () {
      expect(
        () => MessageType.fromCode(99),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
