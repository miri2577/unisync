/// Connection management for remote synchronization.
///
/// Handles SSH process spawning and bidirectional stream communication.
/// Mirrors OCaml Unison's remote connection establishment.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../util/trace.dart';

/// A bidirectional connection to a remote Unison instance.
class RemoteConnection {
  /// Input stream (data FROM remote).
  final Stream<List<int>> input;

  /// Output sink (data TO remote).
  final IOSink output;

  /// Stderr stream (error messages from remote).
  final Stream<List<int>>? stderr;

  /// The underlying process (if SSH-based).
  final Process? _process;

  /// Whether this connection is still alive.
  bool _closed = false;

  RemoteConnection({
    required this.input,
    required this.output,
    this.stderr,
    Process? process,
  }) : _process = process;

  bool get isClosed => _closed;

  /// Close the connection and kill the process.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    try {
      output.close();
    } catch (_) {}

    if (_process != null) {
      _process.kill(ProcessSignal.sigterm);
      // Give it a moment, then force kill
      await Future.delayed(const Duration(seconds: 2));
      _process.kill(ProcessSignal.sigkill);
    }

    Trace.debug(TraceCategory.remote, 'Connection closed');
  }
}

/// Establishes remote connections via SSH or direct socket.
class ConnectionManager {
  const ConnectionManager();

  /// Connect to a remote host via SSH.
  ///
  /// Spawns an SSH process running the Unison server on the remote side.
  /// Communication happens via the process's stdin/stdout.
  Future<RemoteConnection> connectByShell({
    String shell = 'ssh',
    required String host,
    String? user,
    int? port,
    String? sshArgs,
    required String remoteCommand,
  }) async {
    final args = <String>[];

    // SSH-specific options
    if (shell == 'ssh') {
      args.add('-e');
      args.add('none');
    }

    // Port
    if (port != null) {
      args.add('-p');
      args.add('$port');
    }

    // User@host
    if (user != null) {
      args.add('$user@$host');
    } else {
      args.add(host);
    }

    // Additional SSH args
    if (sshArgs != null && sshArgs.isNotEmpty) {
      args.addAll(sshArgs.split(' '));
    }

    // Remote command
    args.add(remoteCommand);

    Trace.info(
      TraceCategory.remote,
      'Connecting: $shell ${args.join(" ")}',
    );

    final process = await Process.start(shell, args);

    // Forward stderr
    _forwardStderr(process.stderr);

    return RemoteConnection(
      input: process.stdout,
      output: process.stdin,
      stderr: process.stderr,
      process: process,
    );
  }

  /// Connect to a remote host via direct TCP socket.
  Future<RemoteConnection> connectBySocket({
    required String host,
    required int port,
  }) async {
    Trace.info(
      TraceCategory.remote,
      'Connecting via socket: $host:$port',
    );

    final socket = await Socket.connect(host, port);

    return RemoteConnection(
      input: socket,
      output: socket,
    );
  }

  /// Create a loopback connection using two pipes.
  ///
  /// Used for testing: creates a pair of connected streams
  /// simulating a remote connection within the same process.
  static (RemoteConnection, RemoteConnection) createLoopback() {
    final pipe1to2 = StreamController<List<int>>.broadcast();
    final pipe2to1 = StreamController<List<int>>.broadcast();

    final sink1 = _ControllerIOSink(pipe1to2);
    final sink2 = _ControllerIOSink(pipe2to1);

    final conn1 = RemoteConnection(
      input: pipe2to1.stream,
      output: sink1,
    );

    final conn2 = RemoteConnection(
      input: pipe1to2.stream,
      output: sink2,
    );

    return (conn1, conn2);
  }

  void _forwardStderr(Stream<List<int>> stderr) {
    stderr.listen(
      (data) {
        final msg = String.fromCharCodes(data).trim();
        if (msg.isNotEmpty) {
          Trace.warning(TraceCategory.remote, 'Remote stderr: $msg');
        }
      },
      onError: (_) {},
    );
  }
}

/// An IOSink backed by a StreamController, for loopback testing.
class _ControllerIOSink implements IOSink {
  final StreamController<List<int>> _controller;

  _ControllerIOSink(this._controller);

  @override
  void add(List<int> data) => _controller.add(List.of(data));

  @override
  void write(Object? object) =>
      add(utf8.encode(object.toString()));

  @override
  void writeln([Object? object = '']) =>
      add(utf8.encode('${object ?? ''}\n'));

  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => add([charCode]);

  @override
  Future flush() async {}

  @override
  Future close() async => _controller.close();

  @override
  Future get done => _controller.done;

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding value) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _controller.addError(error, stackTrace);

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }
}
