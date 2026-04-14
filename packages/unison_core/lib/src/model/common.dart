/// Common types shared across the sync engine.
///
/// Mirrors OCaml Unison's `common.ml` root/host types.
library;

import 'fspath.dart';

/// A sync endpoint — either local or remote.
sealed class Host {
  const Host();
}

/// Local filesystem.
class Local extends Host {
  const Local();

  @override
  String toString() => 'Local';
}

/// Remote host accessed via SSH or socket.
class Remote extends Host {
  final String hostname;
  const Remote(this.hostname);

  @override
  String toString() => 'Remote($hostname)';
}

/// A synchronization root — a host + absolute path.
typedef Root = ({Host host, Fspath path});

/// Parsed command-line root specification.
sealed class ClRoot {
  const ClRoot();
}

/// Local path root.
class ConnectLocal extends ClRoot {
  final String path;
  const ConnectLocal(this.path);
}

/// SSH-based remote root.
class ConnectByShell extends ClRoot {
  final String shell; // "ssh"
  final String host;
  final String? user;
  final int? port;
  final String path;

  const ConnectByShell({
    this.shell = 'ssh',
    required this.host,
    this.user,
    this.port,
    required this.path,
  });
}

/// Direct TCP socket remote root.
class ConnectBySocket extends ClRoot {
  final String host;
  final int port;
  final String path;

  const ConnectBySocket({
    required this.host,
    required this.port,
    required this.path,
  });
}

/// Parse a root specification string.
///
/// Supports:
/// - `/path/to/dir` or `C:\path` — local
/// - `ssh://user@host:port/path` — SSH
/// - `socket://host:port/path` — TCP socket
ClRoot parseRoot(String spec) {
  // SSH URI
  if (spec.startsWith('ssh://')) {
    return _parseSshUri(spec.substring(6));
  }

  // Socket URI
  if (spec.startsWith('socket://')) {
    return _parseSocketUri(spec.substring(9));
  }

  // Legacy SSH syntax: host:path or user@host:path
  // Only if it contains a colon that's not a Windows drive letter
  if (spec.contains(':') && !(spec.length >= 2 && spec[1] == ':')) {
    final colonIdx = spec.indexOf(':');
    final hostPart = spec.substring(0, colonIdx);
    final pathPart = spec.substring(colonIdx + 1);

    String? user;
    String host;
    if (hostPart.contains('@')) {
      final atIdx = hostPart.indexOf('@');
      user = hostPart.substring(0, atIdx);
      host = hostPart.substring(atIdx + 1);
    } else {
      host = hostPart;
    }

    return ConnectByShell(host: host, user: user, path: pathPart);
  }

  // Local path
  return ConnectLocal(spec);
}

ConnectByShell _parseSshUri(String rest) {
  // user@host:port/path or host/path
  String? user;
  String host;
  int? port;
  String path;

  // Extract user@
  String afterUser;
  if (rest.contains('@')) {
    final atIdx = rest.indexOf('@');
    user = rest.substring(0, atIdx);
    afterUser = rest.substring(atIdx + 1);
  } else {
    afterUser = rest;
  }

  // Extract host:port/path or host/path
  final slashIdx = afterUser.indexOf('/');
  final hostPort = slashIdx == -1 ? afterUser : afterUser.substring(0, slashIdx);
  path = slashIdx == -1 ? '/' : afterUser.substring(slashIdx);

  if (hostPort.contains(':')) {
    final colonIdx = hostPort.indexOf(':');
    host = hostPort.substring(0, colonIdx);
    port = int.tryParse(hostPort.substring(colonIdx + 1));
  } else {
    host = hostPort;
  }

  return ConnectByShell(host: host, user: user, port: port, path: path);
}

ConnectBySocket _parseSocketUri(String rest) {
  final slashIdx = rest.indexOf('/');
  final hostPort = slashIdx == -1 ? rest : rest.substring(0, slashIdx);
  final path = slashIdx == -1 ? '/' : rest.substring(slashIdx);

  final colonIdx = hostPort.indexOf(':');
  if (colonIdx == -1) {
    throw ArgumentError('Socket URI must include port: socket://host:port/path');
  }

  final host = hostPort.substring(0, colonIdx);
  final port = int.parse(hostPort.substring(colonIdx + 1));

  return ConnectBySocket(host: host, port: port, path: path);
}
