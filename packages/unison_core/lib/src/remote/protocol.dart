/// RPC protocol for remote synchronization.
///
/// Implements message framing, command registration, and version negotiation
/// for the Unison remote protocol. Messages have a 5-byte header
/// (4-byte length + 1-byte checksum) followed by message ID and payload.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../util/marshal.dart';
import '../util/trace.dart';

/// Minimum payload size to trigger compression (512 bytes).
const _compressionThreshold = 512;

/// Protocol version supported by this implementation.
const protocolVersion = 1;

/// Magic header sent at connection start.
const protocolMagic = 'Unison Dart RPC\n';

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

/// Type of RPC message.
enum MessageType {
  request(0),
  normalResult(1),
  transientError(2),
  fatalError(3),
  streamData(4),
  streamEnd(5),
  streamAbort(6);

  final int code;
  const MessageType(this.code);

  static MessageType fromCode(int code) {
    return MessageType.values.firstWhere(
      (t) => t.code == code,
      orElse: () => throw FormatException('Unknown message type: $code'),
    );
  }
}

/// An RPC message.
class RpcMessage {
  final MessageType type;
  final int messageId;
  final String? commandName; // only for requests
  final Uint8List payload;

  const RpcMessage({
    required this.type,
    required this.messageId,
    this.commandName,
    required this.payload,
  });
}

// ---------------------------------------------------------------------------
// Message framing: encode/decode
// ---------------------------------------------------------------------------

/// Encode a message for wire transmission.
///
/// Format: [4-byte length LE] [1-byte checksum] [payload]
/// Payload: [1-byte type] [4-byte msgId LE] [optional cmdName\0] [data]
Uint8List encodeMessage(RpcMessage msg) {
  final bodyEnc = MarshalEncoder();
  bodyEnc.writeByte(msg.type.code);

  // Message ID as 4 bytes LE
  bodyEnc.writeByte(msg.messageId & 0xFF);
  bodyEnc.writeByte((msg.messageId >> 8) & 0xFF);
  bodyEnc.writeByte((msg.messageId >> 16) & 0xFF);
  bodyEnc.writeByte((msg.messageId >> 24) & 0xFF);

  // Command name (null-terminated) for requests
  if (msg.type == MessageType.request && msg.commandName != null) {
    bodyEnc.writeBytes(Uint8List.fromList(utf8.encode(msg.commandName!)));
    bodyEnc.writeByte(0); // null terminator
  }

  // Payload
  bodyEnc.writeBytes(msg.payload);

  final body = bodyEnc.toBytes();

  // Header: 4-byte length + 1-byte checksum
  final header = Uint8List(5);
  final bd = ByteData.sublistView(header);
  bd.setUint32(0, body.length, Endian.little);
  header[4] = _checksum(body);

  // Combine
  final result = Uint8List(5 + body.length);
  result.setRange(0, 5, header);
  result.setRange(5, result.length, body);
  return result;
}

/// Encode a message with optional zlib compression.
///
/// Format: [4-byte length LE] [1-byte flags] [body]
/// Flags byte: bit 0 = compressed (replaces checksum when compression enabled).
/// When compressed, body is zlib-deflated.
Uint8List encodeMessageCompressed(RpcMessage msg) {
  final raw = encodeMessage(msg);

  // Only compress if payload is large enough
  if (msg.payload.length < _compressionThreshold) return raw;

  // Extract body (after 5-byte header)
  final body = Uint8List.sublistView(raw, 5);
  final compressed = zlib.encode(body);

  // Only use compression if it actually saves space
  if (compressed.length >= body.length) return raw;

  final header = Uint8List(5);
  final bd = ByteData.sublistView(header);
  bd.setUint32(0, compressed.length, Endian.little);
  header[4] = 0x80 | _checksum(Uint8List.fromList(compressed)); // bit 7 = compressed flag

  final result = Uint8List(5 + compressed.length);
  result.setRange(0, 5, header);
  result.setRange(5, result.length, compressed);
  return result;
}

/// Decode a message that may be zlib-compressed.
RpcMessage decodeMessageCompressed(Uint8List data) {
  if (data.length < 5) {
    throw FormatException('Message too short: ${data.length} bytes');
  }

  final flags = data[4];
  final isCompressed = (flags & 0x80) != 0;

  if (!isCompressed) {
    return decodeMessage(data);
  }

  final bd = ByteData.sublistView(data);
  final bodyLen = bd.getUint32(0, Endian.little);

  if (data.length < 5 + bodyLen) {
    throw FormatException('Incomplete compressed message');
  }

  final compressedBody = Uint8List.sublistView(data, 5, 5 + bodyLen);

  // Verify checksum of compressed data
  final expectedCs = flags & 0x7F;
  if (_checksum(compressedBody) != expectedCs) {
    throw FormatException('Compressed checksum mismatch');
  }

  // Decompress
  final body = Uint8List.fromList(zlib.decode(compressedBody));

  // Rebuild uncompressed message and decode
  final uncompressed = Uint8List(5 + body.length);
  final ubd = ByteData.sublistView(uncompressed);
  ubd.setUint32(0, body.length, Endian.little);
  uncompressed[4] = _checksum(body);
  uncompressed.setRange(5, uncompressed.length, body);

  return decodeMessage(uncompressed);
}

/// Decode a message from wire bytes.
///
/// [data] must include the header (5 bytes) + body.
RpcMessage decodeMessage(Uint8List data) {
  if (data.length < 5) {
    throw FormatException('Message too short: ${data.length} bytes');
  }

  final bd = ByteData.sublistView(data);
  final bodyLen = bd.getUint32(0, Endian.little);
  final expectedChecksum = data[4];

  if (data.length < 5 + bodyLen) {
    throw FormatException(
      'Incomplete message: expected ${5 + bodyLen}, got ${data.length}',
    );
  }

  final body = Uint8List.sublistView(data, 5, 5 + bodyLen);
  final actualChecksum = _checksum(body);
  if (actualChecksum != expectedChecksum) {
    throw FormatException(
      'Checksum mismatch: expected $expectedChecksum, got $actualChecksum',
    );
  }

  final dec = MarshalDecoder(body);
  final type = MessageType.fromCode(dec.readByte());
  final msgId = dec.readByte() |
      (dec.readByte() << 8) |
      (dec.readByte() << 16) |
      (dec.readByte() << 24);

  String? cmdName;
  if (type == MessageType.request) {
    final nameBytes = <int>[];
    while (dec.hasMore) {
      final b = dec.readByte();
      if (b == 0) break;
      nameBytes.add(b);
    }
    cmdName = utf8.decode(nameBytes);
  }

  final payload = dec.hasMore
      ? dec.readBytes(body.length - dec.position)
      : Uint8List(0);

  return RpcMessage(
    type: type,
    messageId: msgId,
    commandName: cmdName,
    payload: payload,
  );
}

/// Simple checksum: XOR fold of all bytes.
int _checksum(Uint8List data) {
  var sum = 0;
  for (final b in data) {
    sum = (sum + b) & 0xFF;
  }
  return sum;
}

// ---------------------------------------------------------------------------
// Command Registry
// ---------------------------------------------------------------------------

/// A registered RPC command handler.
typedef CommandHandler = Future<Uint8List> Function(Uint8List payload);

/// A streaming command handler that sends chunks back.
typedef StreamCommandHandler = Future<void> Function(
    Uint8List payload, void Function(Uint8List chunk) sendChunk);

/// Registry of RPC commands for the server side.
class CommandRegistry {
  final Map<String, CommandHandler> _handlers = {};
  final Map<String, StreamCommandHandler> _streamHandlers = {};

  /// Register a command handler (request → single response).
  void register(String name, CommandHandler handler) {
    _handlers[name] = handler;
    Trace.debug(TraceCategory.remote, 'Registered command: $name');
  }

  /// Register a streaming command handler (request → multiple chunks).
  void registerStream(String name, StreamCommandHandler handler) {
    _streamHandlers[name] = handler;
    Trace.debug(TraceCategory.remote, 'Registered stream command: $name');
  }

  /// Look up a command handler.
  CommandHandler? get(String name) => _handlers[name];

  /// Look up a streaming handler.
  StreamCommandHandler? getStream(String name) => _streamHandlers[name];

  /// All registered command names.
  Iterable<String> get names =>
      {..._handlers.keys, ..._streamHandlers.keys};
}

// ---------------------------------------------------------------------------
// RPC Client/Server
// ---------------------------------------------------------------------------

/// RPC client — sends requests and receives responses over a connection.
class RpcClient {
  final Stream<List<int>> _input;
  final IOSink _output;
  int _nextMessageId = 1;
  final Map<int, Completer<RpcMessage>> _pending = {};
  late final StreamSubscription _subscription;
  final _readBuffer = BytesBuilder(copy: false);

  RpcClient(this._input, this._output) {
    _subscription = _input.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
    );
  }

  /// Perform version negotiation handshake.
  Future<int> negotiate() async {
    // Send our magic + version
    _output.add(utf8.encode(protocolMagic));
    _output.add(utf8.encode('VERSION $protocolVersion\n'));
    await _output.flush();

    // Wait for response — simplified: just assume compatible
    // Full implementation would parse the server's version response
    Trace.info(TraceCategory.remote, 'Sent version $protocolVersion');
    return protocolVersion;
  }

  /// Send a request and wait for the response.
  Future<Uint8List> call(String command, Uint8List payload) async {
    final msgId = _nextMessageId++;
    final msg = RpcMessage(
      type: MessageType.request,
      messageId: msgId,
      commandName: command,
      payload: payload,
    );

    final completer = Completer<RpcMessage>();
    _pending[msgId] = completer;

    _output.add(encodeMessage(msg));
    await _output.flush();

    final response = await completer.future;

    if (response.type == MessageType.transientError) {
      throw RpcTransientError(utf8.decode(response.payload));
    }
    if (response.type == MessageType.fatalError) {
      throw RpcFatalError(utf8.decode(response.payload));
    }

    return response.payload;
  }

  void _onData(List<int> chunk) {
    _readBuffer.add(chunk);
    _processBuffer();
  }

  void _processBuffer() {
    final data = _readBuffer.toBytes();
    var offset = 0;

    while (offset + 5 <= data.length) {
      final bd = ByteData.sublistView(data, offset);
      final bodyLen = bd.getUint32(0, Endian.little);
      final totalLen = 5 + bodyLen;

      if (offset + totalLen > data.length) break; // incomplete

      final msgData = Uint8List.sublistView(data, offset, offset + totalLen);
      try {
        final msg = decodeMessage(msgData);
        _handleResponse(msg);
      } catch (e) {
        Trace.error(TraceCategory.remote, 'Failed to decode message: $e');
      }

      offset += totalLen;
    }

    // Keep remaining bytes
    if (offset > 0) {
      _readBuffer.clear();
      if (offset < data.length) {
        _readBuffer.add(Uint8List.sublistView(data, offset));
      }
    }
  }

  void _onError(Object error) {
    for (final c in _pending.values) {
      c.completeError(error);
    }
    _pending.clear();
  }

  void _onDone() {
    for (final c in _pending.values) {
      c.completeError(StateError('Connection closed'));
    }
    _pending.clear();
  }

  /// Send a streaming request — returns a stream of chunks from the server.
  ///
  /// The server responds with StreamData messages until StreamEnd.
  Future<Stream<Uint8List>> callStream(
      String command, Uint8List payload) async {
    final msgId = _nextMessageId++;
    final msg = RpcMessage(
      type: MessageType.request,
      messageId: msgId,
      commandName: command,
      payload: payload,
    );

    final controller = StreamController<Uint8List>();
    _streamPending[msgId] = controller;

    _output.add(encodeMessage(msg));
    await _output.flush();

    return controller.stream;
  }

  /// Stream data TO the server for a given message ID.
  void sendStreamChunk(int messageId, Uint8List data) {
    final msg = RpcMessage(
      type: MessageType.streamData,
      messageId: messageId,
      payload: data,
    );
    _output.add(encodeMessage(msg));
  }

  /// Signal end of stream to server.
  void sendStreamEnd(int messageId) {
    final msg = RpcMessage(
      type: MessageType.streamEnd,
      messageId: messageId,
      payload: Uint8List(0),
    );
    _output.add(encodeMessage(msg));
  }

  final Map<int, StreamController<Uint8List>> _streamPending = {};

  void _handleResponse(RpcMessage msg) {
    // Check if this is a stream response
    if (msg.type == MessageType.streamData) {
      final controller = _streamPending[msg.messageId];
      if (controller != null) {
        controller.add(msg.payload);
      }
      return;
    }
    if (msg.type == MessageType.streamEnd) {
      final controller = _streamPending.remove(msg.messageId);
      controller?.close();
      return;
    }
    if (msg.type == MessageType.streamAbort) {
      final controller = _streamPending.remove(msg.messageId);
      controller?.addError(
          RpcTransientError(utf8.decode(msg.payload)));
      controller?.close();
      return;
    }

    final completer = _pending.remove(msg.messageId);
    if (completer != null) {
      completer.complete(msg);
    } else {
      Trace.warning(
        TraceCategory.remote,
        'Received response for unknown message ID: ${msg.messageId}',
      );
    }
  }

  /// Close the client.
  Future<void> close() async {
    await _subscription.cancel();
    _pending.clear();
    for (final c in _streamPending.values) {
      c.close();
    }
    _streamPending.clear();
  }
}

/// RPC server — listens for requests and dispatches to handlers.
class RpcServer {
  final Stream<List<int>> _input;
  final IOSink _output;
  final CommandRegistry _registry;
  late final StreamSubscription _subscription;
  final _readBuffer = BytesBuilder(copy: false);
  bool _running = false;

  RpcServer(this._input, this._output, this._registry);

  /// Start serving requests.
  void start() {
    _running = true;
    _subscription = _input.listen(
      _onData,
      onError: (e) {
        Trace.error(TraceCategory.remote, 'Server input error: $e');
      },
      onDone: () {
        _running = false;
        Trace.info(TraceCategory.remote, 'Server connection closed');
      },
    );
  }

  void _onData(List<int> chunk) {
    _readBuffer.add(chunk);
    _processBuffer();
  }

  void _processBuffer() {
    final data = _readBuffer.toBytes();
    var offset = 0;

    while (offset + 5 <= data.length) {
      final bd = ByteData.sublistView(data, offset);
      final bodyLen = bd.getUint32(0, Endian.little);
      final totalLen = 5 + bodyLen;

      if (offset + totalLen > data.length) break;

      final msgData = Uint8List.sublistView(data, offset, offset + totalLen);
      try {
        final msg = decodeMessage(msgData);
        _handleRequest(msg);
      } catch (e) {
        Trace.error(TraceCategory.remote, 'Failed to decode request: $e');
      }

      offset += totalLen;
    }

    if (offset > 0) {
      _readBuffer.clear();
      if (offset < data.length) {
        _readBuffer.add(Uint8List.sublistView(data, offset));
      }
    }
  }

  Future<void> _handleRequest(RpcMessage msg) async {
    if (msg.type != MessageType.request) return;

    final cmdName = msg.commandName ?? '';

    // Check stream handlers first
    final streamHandler = _registry.getStream(cmdName);
    if (streamHandler != null) {
      try {
        await streamHandler(msg.payload, (chunk) {
          _sendResponse(msg.messageId, MessageType.streamData, chunk);
        });
        _sendResponse(msg.messageId, MessageType.streamEnd, Uint8List(0));
      } catch (e) {
        _sendResponse(msg.messageId, MessageType.streamAbort,
            Uint8List.fromList(utf8.encode('$e')));
      }
      return;
    }

    // Regular handlers
    final handler = _registry.get(cmdName);
    if (handler == null) {
      _sendResponse(msg.messageId, MessageType.fatalError,
          Uint8List.fromList(utf8.encode('Unknown command: $cmdName')));
      return;
    }

    try {
      final result = await handler(msg.payload);
      _sendResponse(msg.messageId, MessageType.normalResult, result);
    } catch (e) {
      _sendResponse(msg.messageId, MessageType.transientError,
          Uint8List.fromList(utf8.encode('$e')));
    }
  }

  void _sendResponse(int messageId, MessageType type, Uint8List payload) {
    final response = RpcMessage(
      type: type,
      messageId: messageId,
      payload: payload,
    );
    _output.add(encodeMessage(response));
  }

  /// Stop the server.
  Future<void> stop() async {
    _running = false;
    await _subscription.cancel();
  }

  bool get isRunning => _running;
}

// ---------------------------------------------------------------------------
// RPC Errors
// ---------------------------------------------------------------------------

class RpcTransientError implements Exception {
  final String message;
  RpcTransientError(this.message);

  @override
  String toString() => 'RpcTransientError: $message';
}

class RpcFatalError implements Exception {
  final String message;
  RpcFatalError(this.message);

  @override
  String toString() => 'RpcFatalError: $message';
}
