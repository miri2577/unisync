/// WebDAV client for remote file synchronization.
///
/// Provides file operations over HTTP/HTTPS using the WebDAV protocol
/// (RFC 4918). Supports PROPFIND, GET, PUT, DELETE, MKCOL, MOVE.
/// Works with Nextcloud, Synology, HiDrive, pCloud, Box, and any
/// WebDAV-compatible server.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../model/fileinfo.dart';
import '../model/fspath.dart';
import '../model/name.dart';
import '../model/props.dart';
import '../model/sync_path.dart';
import '../util/trace.dart';

/// WebDAV file/directory entry from PROPFIND response.
class WebDavEntry {
  final String href;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? lastModified;
  final String? etag;
  final String? contentType;

  const WebDavEntry({
    required this.href,
    required this.name,
    required this.isDirectory,
    this.size = 0,
    this.lastModified,
    this.etag,
    this.contentType,
  });

  @override
  String toString() => 'WebDavEntry($name, ${isDirectory ? "dir" : "${size}B"})';
}

/// WebDAV connection configuration.
class WebDavConfig {
  /// Server URL (e.g. https://cloud.example.com/remote.php/dav/files/user/)
  final String baseUrl;

  /// Username for authentication.
  final String username;

  /// Password for authentication.
  final String password;

  /// Connection timeout.
  final Duration timeout;

  const WebDavConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.timeout = const Duration(seconds: 30),
  });

  /// Base URL normalized with trailing slash.
  String get normalizedUrl {
    var url = baseUrl;
    if (!url.endsWith('/')) url += '/';
    return url;
  }
}

/// WebDAV client for remote file operations.
class WebDavClient {
  final WebDavConfig config;
  final http.Client _http;

  WebDavClient(this.config) : _http = http.Client();

  /// Auth header value.
  String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';

  /// Build full URL for a relative path.
  String _url(String relativePath) {
    if (relativePath.isEmpty) return config.normalizedUrl;
    return '${config.normalizedUrl}$relativePath';
  }

  /// Common headers for all requests.
  Map<String, String> get _headers => {
    'Authorization': _authHeader,
  };

  // -----------------------------------------------------------------------
  // Connection test
  // -----------------------------------------------------------------------

  /// Test the connection by sending a PROPFIND to the root.
  Future<bool> testConnection() async {
    try {
      final entries = await listDirectory('');
      return true;
    } catch (e) {
      Trace.warning(TraceCategory.remote, 'WebDAV connection test failed: $e');
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // Directory listing (PROPFIND)
  // -----------------------------------------------------------------------

  /// List directory contents via PROPFIND.
  Future<List<WebDavEntry>> listDirectory(String path) async {
    final url = _url(path.isEmpty ? '' : path + (path.endsWith('/') ? '' : '/'));
    Trace.debug(TraceCategory.remote, 'PROPFIND $url');

    final response = await _http.send(http.Request('PROPFIND', Uri.parse(url))
      ..headers.addAll({
        ..._headers,
        'Depth': '1',
        'Content-Type': 'application/xml',
      })
      ..body = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype/>
    <d:getcontentlength/>
    <d:getlastmodified/>
    <d:getetag/>
    <d:getcontenttype/>
  </d:prop>
</d:propfind>''').timeout(const Duration(seconds: 30));

    final body = await response.stream.bytesToString()
        .timeout(const Duration(seconds: 30), onTimeout: () {
      Trace.warning(TraceCategory.remote, 'PROPFIND body read timeout');
      return '';
    });
    Trace.info(TraceCategory.remote, 'PROPFIND $url -> ${response.statusCode} (body ${body.length}B)');
    // Dump XML to known path for debugging
    try {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
      File('$home/.unison/propfind_debug.xml').writeAsStringSync(body);
    } catch (_) {}

    if (response.statusCode != 207) {
      throw WebDavException(
        'PROPFIND failed: ${response.statusCode}',
        response.statusCode,
      );
    }

    final entries = _parsePropfindResponse(body, url);
    Trace.debug(TraceCategory.remote, 'PROPFIND $url -> ${entries.length} entries');
    return entries;
  }

  /// List child names of a directory (matching OsFs.childrenOf interface).
  Future<List<Name>> childrenOf(SyncPath path) async {
    final entries = await listDirectory(path.toString());
    return entries
        .where((e) => e.name.isNotEmpty)
        .map((e) => Name(e.name))
        .toList()
      ..sort();
  }

  /// Get info about a single path.
  Future<WebDavEntry?> stat(String path) async {
    try {
      final url = _url(path);
      final response = await _http.send(http.Request('PROPFIND', Uri.parse(url))
        ..headers.addAll({
          ..._headers,
          'Depth': '0',
          'Content-Type': 'application/xml',
        })
        ..body = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype/>
    <d:getcontentlength/>
    <d:getlastmodified/>
    <d:getetag/>
  </d:prop>
</d:propfind>''');

      final body = await response.stream.bytesToString();
      if (response.statusCode != 207) return null;

      final entries = _parsePropfindResponse(body, _url(''));
      // Depth 0 returns the item itself
      return entries.isNotEmpty ? entries.first : null;
    } catch (_) {
      return null;
    }
  }

  /// Check if a path exists.
  Future<bool> exists(String path) async {
    final url = _url(path);
    Trace.debug(TraceCategory.remote, 'HEAD $url');
    try {
      // Use streamed send so we can drop the body without blocking
      final req = http.Request('HEAD', Uri.parse(url))
        ..headers.addAll(_headers);
      final response = await _http.send(req)
          .timeout(const Duration(seconds: 10));
      // Drain in background
      Future.microtask(() async {
        try {
          await response.stream.drain<void>().timeout(const Duration(seconds: 3));
        } catch (_) {}
      });
      Trace.debug(TraceCategory.remote, 'HEAD $path -> ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 301;
    } catch (e) {
      Trace.debug(TraceCategory.remote, 'HEAD $path failed: $e');
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // File operations
  // -----------------------------------------------------------------------

  /// Download a file.
  Future<Uint8List> readFile(String path) async {
    Trace.debug(TraceCategory.remote, 'GET ${_url(path)}');
    final response = await _http.get(
      Uri.parse(_url(path)),
      headers: _headers,
    ).timeout(const Duration(minutes: 5));
    Trace.debug(TraceCategory.remote,
        'GET $path -> ${response.statusCode} (${response.bodyBytes.length}B)');

    if (response.statusCode != 200) {
      throw WebDavException(
        'GET failed for $path: ${response.statusCode}',
        response.statusCode,
      );
    }

    return response.bodyBytes;
  }

  /// Download a file as a stream (for large files).
  Future<http.StreamedResponse> readFileStream(String path) async {
    final request = http.Request('GET', Uri.parse(_url(path)));
    request.headers.addAll(_headers);
    return _http.send(request);
  }

  /// Upload a file.
  Future<void> writeFile(String path, Uint8List data) async {
    final url = _url(path);
    Trace.debug(TraceCategory.remote, 'PUT $url (${data.length}B)');
    final req = http.Request('PUT', Uri.parse(url))
      ..headers.addAll({
        ..._headers,
        'Content-Type': 'application/octet-stream',
        'Content-Length': '${data.length}',
      })
      ..bodyBytes = data;
    final response = await _http.send(req)
        .timeout(const Duration(minutes: 10));
    // Drain body in background — server may keep stream open
    Future.microtask(() async {
      try {
        await response.stream.drain<void>().timeout(const Duration(seconds: 5));
      } catch (_) {}
    });
    Trace.debug(TraceCategory.remote, 'PUT $path -> ${response.statusCode}');

    if (response.statusCode != 201 &&
        response.statusCode != 204 &&
        response.statusCode != 200) {
      throw WebDavException(
        'PUT failed for $path: ${response.statusCode}',
        response.statusCode,
      );
    }
  }

  /// Create a directory (MKCOL).
  ///
  /// Treats existing directories as success (status 405, 409, 301).
  /// Has a 30s timeout to prevent hangs.
  Future<void> mkdir(String path) async {
    final url = _url(path);
    Trace.debug(TraceCategory.remote, 'MKCOL $url');

    http.StreamedResponse response;
    try {
      response = await _http.send(
        http.Request('MKCOL', Uri.parse(url))
          ..headers.addAll(_headers),
      ).timeout(const Duration(seconds: 15));
    } on Exception catch (e) {
      Trace.warning(TraceCategory.remote, 'MKCOL $path failed: $e');
      throw WebDavException('MKCOL $path: $e', 0);
    }

    final status = response.statusCode;
    Trace.debug(TraceCategory.remote, 'MKCOL $path -> $status');
    // Drain the response body in the background with hard timeout — DON'T await it.
    // Some servers (HiDrive) hold the stream open via keep-alive after MKCOL.
    Future.microtask(() async {
      try {
        await response.stream.drain<void>().timeout(const Duration(seconds: 5));
      } catch (_) {/* ignore */}
    });

    // Accept: 201 created, 200 ok, 204 no content,
    //         405 method not allowed (already exists),
    //         409 conflict (already exists on some servers),
    //         301/302/308 redirect to existing collection
    if (status == 201 || status == 200 || status == 204 ||
        status == 405 || status == 409 ||
        status == 301 || status == 302 || status == 308) {
      return;
    }

    Trace.warning(TraceCategory.remote,
        'MKCOL $path: unexpected status $status');
    throw WebDavException('MKCOL failed for $path: $status', status);
  }

  /// Create directory and all parents.
  /// Skips MKCOL for directories that already exist (saves round-trips).
  Future<void> mkdirRecursive(String path) async {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    var current = '';
    for (final part in parts) {
      current += '$part/';
      // Cheap existence check first
      try {
        if (await exists(current)) {
          Trace.debug(TraceCategory.remote, 'mkdirRecursive: $current exists, skip');
          continue;
        }
      } catch (_) {
        // exists() failed, try MKCOL anyway
      }
      try {
        await mkdir(current);
      } on WebDavException catch (e) {
        // Tolerate "already exists" type errors at intermediate levels
        if (e.statusCode == 405 || e.statusCode == 409) {
          continue;
        }
        rethrow;
      }
    }
  }

  /// Delete a file or directory.
  Future<void> delete(String path) async {
    final url = _url(path);
    Trace.debug(TraceCategory.remote, 'DELETE $url');
    final req = http.Request('DELETE', Uri.parse(url))
      ..headers.addAll(_headers);
    final response = await _http.send(req)
        .timeout(const Duration(seconds: 30));
    Future.microtask(() async {
      try {
        await response.stream.drain<void>().timeout(const Duration(seconds: 5));
      } catch (_) {}
    });
    Trace.debug(TraceCategory.remote, 'DELETE $path -> ${response.statusCode}');

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw WebDavException(
        'DELETE failed for $path: ${response.statusCode}',
        response.statusCode,
      );
    }
  }

  /// Move/rename a file or directory.
  Future<void> move(String fromPath, String toPath) async {
    final response = await _http.send(
      http.Request('MOVE', Uri.parse(_url(fromPath)))
        ..headers.addAll({
          ..._headers,
          'Destination': _url(toPath),
          'Overwrite': 'T',
        }),
    );

    final status = response.statusCode;
    if (status != 201 && status != 204) {
      throw WebDavException('MOVE failed: $status', status);
    }
  }

  /// Copy a file on the server side.
  Future<void> copy(String fromPath, String toPath) async {
    final response = await _http.send(
      http.Request('COPY', Uri.parse(_url(fromPath)))
        ..headers.addAll({
          ..._headers,
          'Destination': _url(toPath),
          'Overwrite': 'T',
        }),
    );

    final status = response.statusCode;
    if (status != 201 && status != 204) {
      throw WebDavException('COPY failed: $status', status);
    }
  }

  // -----------------------------------------------------------------------
  // Higher-level helpers for sync integration
  // -----------------------------------------------------------------------

  /// Get Fileinfo-compatible data for a path.
  Future<Fileinfo> getFileinfo(SyncPath path) async {
    final entry = await stat(path.toString());
    if (entry == null) return Fileinfo.absent;

    return Fileinfo(
      typ: entry.isDirectory ? FileType.directory : FileType.file,
      inode: 0,
      desc: Props(
        permissions: entry.isDirectory ? 0x1FF : 0x1ED,
        modTime: entry.lastModified ?? DateTime.now(),
        length: entry.size,
      ),
      stamp: const NoStamp(),
    );
  }

  /// Upload a file with automatic parent directory creation.
  Future<void> writeFileWithParents(String path, Uint8List data) async {
    // Ensure parent directories exist
    final lastSlash = path.lastIndexOf('/');
    if (lastSlash > 0) {
      await mkdirRecursive(path.substring(0, lastSlash));
    }
    await writeFile(path, data);
  }

  /// Close the client and release resources.
  void close() {
    _http.close();
  }

  // -----------------------------------------------------------------------
  // PROPFIND XML parsing
  // -----------------------------------------------------------------------

  List<WebDavEntry> _parsePropfindResponse(String xml, String requestUrl) {
    final doc = XmlDocument.parse(xml);
    final entries = <WebDavEntry>[];

    // Namespace-agnostic: find all 'response' elements regardless of prefix
    final responses = doc.rootElement.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName == 'response');

    for (final resp in responses) {
      final href = _getText(resp, 'href') ?? '';

      // Skip the directory itself (depth=1 includes parent)
      if (_isParentEntry(href, requestUrl)) continue;

      final name = Uri.decodeFull(href.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '');
      if (name.isEmpty) continue;

      final isDir = _hasResourceType(resp, 'collection');
      final size = int.tryParse(
        _getPropText(resp, 'getcontentlength') ?? '0',
      ) ?? 0;

      DateTime? modified;
      final modStr = _getPropText(resp, 'getlastmodified');
      if (modStr != null) {
        modified = _parseHttpDate(modStr);
      }

      final etag = _getPropText(resp, 'getetag');
      final contentType = _getPropText(resp, 'getcontenttype');

      entries.add(WebDavEntry(
        href: href,
        name: name,
        isDirectory: isDir,
        size: size,
        lastModified: modified,
        etag: etag,
        contentType: contentType,
      ));
    }

    return entries;
  }

  bool _isParentEntry(String href, String requestUrl) {
    final normHref = href.endsWith('/') ? href : '$href/';
    final normReq = requestUrl.endsWith('/') ? requestUrl : '$requestUrl/';
    final hrefUri = Uri.tryParse(normHref);
    final reqUri = Uri.tryParse(normReq);
    if (hrefUri != null && reqUri != null) {
      return hrefUri.path == reqUri.path;
    }
    return normHref == normReq;
  }

  /// Find element by local name, ignoring namespace prefix.
  /// Works with d:href, D:href, lp1:href, href etc.
  Iterable<XmlElement> _findByLocal(XmlElement elem, String localName) {
    return elem.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName == localName);
  }

  String? _getText(XmlElement elem, String localName) {
    final found = _findByLocal(elem, localName);
    return found.isNotEmpty ? found.first.innerText : null;
  }

  String? _getPropText(XmlElement response, String propName) {
    for (final prop in _findByLocal(response, 'prop')) {
      final found = _findByLocal(prop, propName);
      if (found.isNotEmpty) {
        final text = found.first.innerText.trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  bool _hasResourceType(XmlElement response, String type) {
    for (final rt in _findByLocal(response, 'resourcetype')) {
      if (_findByLocal(rt, type).isNotEmpty) return true;
    }
    return false;
  }

  /// Parse HTTP date format (RFC 2616).
  DateTime? _parseHttpDate(String s) {
    try {
      return DateTime.parse(s);
    } catch (_) {
      try {
        // Try HTTP date format: "Sun, 06 Nov 1994 08:49:37 GMT"
        return HttpDate.parse(s);
      } catch (_) {
        return null;
      }
    }
  }
}

/// WebDAV-specific exception.
class WebDavException implements Exception {
  final String message;
  final int statusCode;

  const WebDavException(this.message, this.statusCode);

  @override
  String toString() => 'WebDavException($statusCode): $message';
}
