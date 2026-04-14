/// Remote-capable sync operations.
///
/// Wraps the local sync engine operations as RPC commands that can be
/// invoked over a remote connection. Provides both client-side proxy
/// calls and server-side command registration.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../archive/archive_serial.dart';
import '../engine/update.dart';
import '../fingerprint/fingerprint_service.dart';
import '../fs/fileinfo_service.dart';
import '../fs/os.dart';
import '../model/archive.dart';
import '../model/fileinfo.dart';
import '../model/fingerprint.dart';
import '../model/fspath.dart';
import '../model/name.dart';
import '../model/props.dart';
import '../model/sync_path.dart';
import '../model/update_item.dart';
import '../util/marshal.dart';
import '../util/trace.dart';
import 'protocol.dart';

/// Chunk size for streaming file transfers (64KB).
const _streamChunkSize = 65536;

// ---------------------------------------------------------------------------
// Server-side: register all sync RPC commands
// ---------------------------------------------------------------------------

/// Register all sync-related RPC commands on a server.
void registerSyncCommands(CommandRegistry registry, Fspath root) {
  final detector = UpdateDetector();
  final fpService = const FingerprintService();
  final os = const OsFs();
  final fileinfoService = const FileinfoService();

  // --- Basic commands ---

  registry.register('ping', (payload) async {
    return Uint8List.fromList(utf8.encode('pong'));
  });

  registry.register('version', (payload) async {
    final enc = MarshalEncoder();
    enc.writeInt(protocolVersion);
    enc.writeString('unison-dart 0.1.0');
    return enc.toBytes();
  });

  // --- Filesystem queries ---

  registry.register('stat', (payload) async {
    final path = SyncPath.fromString(MarshalDecoder(payload).readString());
    final info = fileinfoService.get(root, path);
    final enc = MarshalEncoder();
    enc.writeInt(info.typ.index);
    enc.writeInt(info.inode);
    enc.writeInt(info.desc.permissions);
    enc.writeInt64(info.desc.modTime.millisecondsSinceEpoch);
    enc.writeInt64(info.desc.length);
    return enc.toBytes();
  });

  registry.register('children', (payload) async {
    final path = SyncPath.fromString(MarshalDecoder(payload).readString());
    final names = os.childrenOf(root, path);
    final enc = MarshalEncoder();
    enc.writeInt(names.length);
    for (final name in names) {
      enc.writeString(name.raw);
    }
    return enc.toBytes();
  });

  registry.register('exists', (payload) async {
    final path = SyncPath.fromString(MarshalDecoder(payload).readString());
    final enc = MarshalEncoder();
    enc.writeBool(os.exists(root, path));
    return enc.toBytes();
  });

  registry.register('readLink', (payload) async {
    final path = SyncPath.fromString(MarshalDecoder(payload).readString());
    final target = os.readLink(root, path);
    return Uint8List.fromList(utf8.encode(target));
  });

  // --- Fingerprinting ---

  registry.register('fingerprint', (payload) async {
    final path = SyncPath.fromString(MarshalDecoder(payload).readString());
    final fp = fpService.file(root, path);
    return fp.bytes;
  });

  // --- File read (small files, single response) ---

  registry.register('readFile', (payload) async {
    final path = SyncPath.fromString(MarshalDecoder(payload).readString());
    final fullPath = root.concat(path).toLocal();
    return File(fullPath).readAsBytesSync();
  });

  // --- File read (large files, streaming) ---

  registry.registerStream('readFileStream', (payload, sendChunk) async {
    final path = SyncPath.fromString(MarshalDecoder(payload).readString());
    final fullPath = root.concat(path).toLocal();
    final file = File(fullPath);
    final raf = file.openSync(mode: FileMode.read);
    try {
      final buffer = Uint8List(_streamChunkSize);
      while (true) {
        final n = raf.readIntoSync(buffer);
        if (n <= 0) break;
        sendChunk(n == buffer.length ? buffer : Uint8List.sublistView(buffer, 0, n));
      }
    } finally {
      raf.closeSync();
    }
  });

  // --- File write (small files) ---

  registry.register('writeFile', (payload) async {
    final dec = MarshalDecoder(payload);
    final path = SyncPath.fromString(dec.readString());
    final data = dec.readByteArray();
    final fullPath = root.concat(path).toLocal();
    final parent = File(fullPath).parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);
    File(fullPath).writeAsBytesSync(data);
    return Uint8List(0);
  });

  // --- Directory operations ---

  registry.register('mkdir', (payload) async {
    final path = SyncPath.fromString(MarshalDecoder(payload).readString());
    os.createDir(root, path);
    return Uint8List(0);
  });

  registry.register('delete', (payload) async {
    final path = SyncPath.fromString(MarshalDecoder(payload).readString());
    os.delete(root, path);
    return Uint8List(0);
  });

  registry.register('rename', (payload) async {
    final dec = MarshalDecoder(payload);
    final from = SyncPath.fromString(dec.readString());
    final to = SyncPath.fromString(dec.readString());
    os.rename(root, from, to);
    return Uint8List(0);
  });

  registry.register('symlink', (payload) async {
    final dec = MarshalDecoder(payload);
    final path = SyncPath.fromString(dec.readString());
    final target = dec.readString();
    os.symlink(root, path, target);
    return Uint8List(0);
  });

  // --- Properties ---

  registry.register('setProps', (payload) async {
    final dec = MarshalDecoder(payload);
    final path = SyncPath.fromString(dec.readString());
    final permissions = dec.readInt();
    final modTimeMs = dec.readInt64();
    final fullPath = root.concat(path).toLocal();
    os.setModTime(fullPath, DateTime.fromMillisecondsSinceEpoch(modTimeMs));
    if (!Platform.isWindows) {
      os.setPermissions(fullPath, permissions);
    }
    return Uint8List(0);
  });

  // --- Update detection ---

  registry.register('findUpdates', (payload) async {
    final dec = MarshalDecoder(payload);
    final pathStr = dec.readString();
    final archiveData = dec.readByteArray();
    final useFastCheck = dec.readBool();

    final path = SyncPath.fromString(pathStr);
    final archive = archiveData.isEmpty
        ? const NoArchive()
        : decodeArchive(archiveData);
    final config = UpdateConfig(useFastCheck: useFastCheck);

    final (updateItem, newArchive) =
        detector.findUpdates(root, path, archive, config);

    final enc = MarshalEncoder();
    _encodeUpdateItem(enc, updateItem);
    enc.writeByteArray(encodeArchive(newArchive));
    return enc.toBytes();
  });

  registry.register('buildArchive', (payload) async {
    final dec = MarshalDecoder(payload);
    final pathStr = dec.readString();
    final useFastCheck = dec.readBool();
    final path = SyncPath.fromString(pathStr);
    final config = UpdateConfig(useFastCheck: useFastCheck);
    final archive = detector.buildArchiveFromFs(root, path, config);
    return encodeArchive(archive);
  });

  // --- Copy file with atomic write (temp + rename) ---

  registry.register('copyFileAtomic', (payload) async {
    final dec = MarshalDecoder(payload);
    final dstPathStr = dec.readString();
    final data = dec.readByteArray();
    final permissions = dec.readInt();
    final modTimeMs = dec.readInt64();

    final dstPath = SyncPath.fromString(dstPathStr);
    final fullPath = root.concat(dstPath).toLocal();

    // Ensure parent
    final parent = File(fullPath).parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);

    // Write to temp, then rename
    final tempPath = os.tempPath(root, dstPath);
    File(tempPath).writeAsBytesSync(data);

    // Set props on temp
    os.setModTime(tempPath, DateTime.fromMillisecondsSinceEpoch(modTimeMs));
    if (!Platform.isWindows) {
      os.setPermissions(tempPath, permissions);
    }

    // Atomic rename
    if (File(fullPath).existsSync()) File(fullPath).deleteSync();
    File(tempPath).renameSync(fullPath);

    return Uint8List(0);
  });

  Trace.info(
    TraceCategory.remote,
    'Registered ${registry.names.length} sync commands for $root',
  );
}

// ---------------------------------------------------------------------------
// Client-side: proxy calls to remote
// ---------------------------------------------------------------------------

/// Client proxy for remote sync operations.
class RemoteSyncClient {
  final RpcClient _rpc;

  RemoteSyncClient(this._rpc);

  Future<bool> ping() async {
    try {
      final result = await _rpc.call('ping', Uint8List(0));
      return utf8.decode(result) == 'pong';
    } catch (_) {
      return false;
    }
  }

  Future<(int, String)> version() async {
    final result = await _rpc.call('version', Uint8List(0));
    final dec = MarshalDecoder(result);
    return (dec.readInt(), dec.readString());
  }

  Future<Fileinfo> stat(SyncPath path) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    final result = await _rpc.call('stat', enc.toBytes());
    final dec = MarshalDecoder(result);
    return Fileinfo(
      typ: FileType.values[dec.readInt()],
      inode: dec.readInt(),
      desc: Props(
        permissions: dec.readInt(),
        modTime: DateTime.fromMillisecondsSinceEpoch(dec.readInt64()),
        length: dec.readInt64(),
      ),
      stamp: const NoStamp(),
    );
  }

  Future<List<Name>> children(SyncPath path) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    final result = await _rpc.call('children', enc.toBytes());
    final dec = MarshalDecoder(result);
    final count = dec.readInt();
    return List.generate(count, (_) => Name(dec.readString()));
  }

  Future<bool> exists(SyncPath path) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    final result = await _rpc.call('exists', enc.toBytes());
    return MarshalDecoder(result).readBool();
  }

  Future<Uint8List> readFile(SyncPath path) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    return _rpc.call('readFile', enc.toBytes());
  }

  /// Read a large file via streaming.
  Future<Stream<Uint8List>> readFileStream(SyncPath path) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    return _rpc.callStream('readFileStream', enc.toBytes());
  }

  Future<void> writeFile(SyncPath path, Uint8List data) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    enc.writeByteArray(data);
    await _rpc.call('writeFile', enc.toBytes());
  }

  Future<void> copyFileAtomic(
      SyncPath path, Uint8List data, Props props) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    enc.writeByteArray(data);
    enc.writeInt(props.permissions);
    enc.writeInt64(props.modTime.millisecondsSinceEpoch);
    await _rpc.call('copyFileAtomic', enc.toBytes());
  }

  Future<void> mkdir(SyncPath path) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    await _rpc.call('mkdir', enc.toBytes());
  }

  Future<void> delete(SyncPath path) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    await _rpc.call('delete', enc.toBytes());
  }

  Future<void> rename(SyncPath from, SyncPath to) async {
    final enc = MarshalEncoder();
    enc.writeString(from.toString());
    enc.writeString(to.toString());
    await _rpc.call('rename', enc.toBytes());
  }

  Future<void> symlink(SyncPath path, String target) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    enc.writeString(target);
    await _rpc.call('symlink', enc.toBytes());
  }

  Future<void> setProps(SyncPath path, Props props) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    enc.writeInt(props.permissions);
    enc.writeInt64(props.modTime.millisecondsSinceEpoch);
    await _rpc.call('setProps', enc.toBytes());
  }

  Future<(UpdateItem, Archive)> findUpdates(
    SyncPath path,
    Archive archive,
    bool useFastCheck,
  ) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    enc.writeByteArray(encodeArchive(archive));
    enc.writeBool(useFastCheck);
    final result = await _rpc.call('findUpdates', enc.toBytes());
    final dec = MarshalDecoder(result);
    final updateItem = _decodeUpdateItem(dec);
    final archiveData = dec.readByteArray();
    return (updateItem, decodeArchive(archiveData));
  }

  Future<Archive> buildArchive(SyncPath path, bool useFastCheck) async {
    final enc = MarshalEncoder();
    enc.writeString(path.toString());
    enc.writeBool(useFastCheck);
    final result = await _rpc.call('buildArchive', enc.toBytes());
    return decodeArchive(result);
  }
}

// ---------------------------------------------------------------------------
// Server mode
// ---------------------------------------------------------------------------

/// Start server mode: read commands from stdin, send responses to stdout.
Future<void> runServer(Fspath root) async {
  Trace.info(TraceCategory.remote, 'Starting server mode for $root');

  final registry = CommandRegistry();
  registerSyncCommands(registry, root);

  final server = RpcServer(
    stdin.cast<List<int>>(),
    stdout,
    registry,
  );

  server.start();
  await stdin.drain();
  await server.stop();
}

// ---------------------------------------------------------------------------
// UpdateItem serialization (simplified)
// ---------------------------------------------------------------------------

// UpdateItem tag constants
const _tagNoUpdates = 0;
const _tagUpdates = 1;
const _tagUpdateError = 2;
// UpdateContent tag constants
const _tagAbsent = 0;
const _tagFileContent = 1;
const _tagDirContent = 2;
const _tagSymlinkContent = 3;
// ContentsChange tag constants
const _tagContentsSame = 0;
const _tagContentsUpdated = 1;
// PrevState tag constants
const _tagPrevDir = 0;
const _tagPrevFile = 1;
const _tagPrevSymlink = 2;
const _tagNewEntry = 3;

void _encodeUpdateItem(MarshalEncoder enc, UpdateItem item) {
  switch (item) {
    case NoUpdates():
      enc.writeTag(_tagNoUpdates);
    case Updates(content: var content, prevState: var prev):
      enc.writeTag(_tagUpdates);
      _encodeUpdateContent(enc, content);
      _encodePrevState(enc, prev);
    case UpdateError(message: var msg):
      enc.writeTag(_tagUpdateError);
      enc.writeString(msg);
  }
}

void _encodeUpdateContent(MarshalEncoder enc, UpdateContent content) {
  switch (content) {
    case Absent():
      enc.writeTag(_tagAbsent);
    case FileContent(desc: var desc, contentsChange: var cc):
      enc.writeTag(_tagFileContent);
      _encodeProps(enc, desc);
      _encodeContentsChange(enc, cc);
    case DirContent(desc: var desc, children: var ch, permChange: var pc, isEmpty: var empty):
      enc.writeTag(_tagDirContent);
      _encodeProps(enc, desc);
      enc.writeInt(pc == PermChange.propsUpdated ? 1 : 0);
      enc.writeBool(empty);
      enc.writeInt(ch.length);
      for (final (name, child) in ch) {
        enc.writeString(name.raw);
        _encodeUpdateItem(enc, child);
      }
    case SymlinkContent(target: var target):
      enc.writeTag(_tagSymlinkContent);
      enc.writeString(target);
  }
}

void _encodeContentsChange(MarshalEncoder enc, ContentsChange cc) {
  switch (cc) {
    case ContentsSame():
      enc.writeTag(_tagContentsSame);
    case ContentsUpdated(fingerprint: var fp, stamp: var stamp, ressStamp: var ress):
      enc.writeTag(_tagContentsUpdated);
      enc.writeByteArray(fp.dataFork.bytes);
      enc.writeBool(fp.resourceFork != null);
      if (fp.resourceFork != null) enc.writeByteArray(fp.resourceFork!.bytes);
      enc.writeInt(ress.value);
  }
}

void _encodePrevState(MarshalEncoder enc, PrevState prev) {
  switch (prev) {
    case PrevDir(desc: var d):
      enc.writeTag(_tagPrevDir);
      _encodeProps(enc, d);
    case PrevFile(desc: var d, fingerprint: var fp, stamp: _, ressStamp: var r):
      enc.writeTag(_tagPrevFile);
      _encodeProps(enc, d);
      enc.writeByteArray(fp.dataFork.bytes);
      enc.writeInt(r.value);
    case PrevSymlink():
      enc.writeTag(_tagPrevSymlink);
    case NewEntry():
      enc.writeTag(_tagNewEntry);
  }
}

void _encodeProps(MarshalEncoder enc, Props props) {
  enc.writeInt(props.permissions);
  enc.writeInt64(props.modTime.millisecondsSinceEpoch);
  enc.writeInt64(props.length);
  enc.writeSignedInt(props.ownerId);
  enc.writeSignedInt(props.groupId);
}

UpdateItem _decodeUpdateItem(MarshalDecoder dec) {
  final tag = dec.readTag();
  return switch (tag) {
    _tagNoUpdates => const NoUpdates(),
    _tagUpdates => _decodeUpdatesImpl(dec),
    _tagUpdateError => UpdateError(dec.readString()),
    _ => throw FormatException('Unknown UpdateItem tag: $tag'),
  };
}

UpdateItem _decodeUpdatesImpl(MarshalDecoder dec) {
  final content = _decodeUpdateContent(dec);
  final prev = _decodePrevState(dec);
  return Updates(content, prev);
}

UpdateContent _decodeUpdateContent(MarshalDecoder dec) {
  final tag = dec.readTag();
  return switch (tag) {
    _tagAbsent => const Absent(),
    _tagFileContent => _decodeFileContent(dec),
    _tagDirContent => _decodeDirContent(dec),
    _tagSymlinkContent => SymlinkContent(dec.readString()),
    _ => throw FormatException('Unknown UpdateContent tag: $tag'),
  };
}

FileContent _decodeFileContent(MarshalDecoder dec) {
  final desc = _decodeProps(dec);
  final cc = _decodeContentsChange(dec);
  return FileContent(desc, cc);
}

DirContent _decodeDirContent(MarshalDecoder dec) {
  final desc = _decodeProps(dec);
  final pc = dec.readInt() == 1 ? PermChange.propsUpdated : PermChange.propsSame;
  final empty = dec.readBool();
  final count = dec.readInt();
  final children = <(Name, UpdateItem)>[];
  for (var i = 0; i < count; i++) {
    final name = Name(dec.readString());
    final child = _decodeUpdateItem(dec);
    children.add((name, child));
  }
  return DirContent(desc, children, pc, empty);
}

ContentsChange _decodeContentsChange(MarshalDecoder dec) {
  final tag = dec.readTag();
  if (tag == _tagContentsSame) return const ContentsSame();
  final dataFp = Fingerprint(dec.readByteArray());
  final hasRess = dec.readBool();
  final ressFp = hasRess ? Fingerprint(dec.readByteArray()) : null;
  final ressValue = dec.readInt();
  return ContentsUpdated(
    FullFingerprint(dataFp, ressFp),
    const NoStamp(),
    RessStamp(ressValue),
  );
}

PrevState _decodePrevState(MarshalDecoder dec) {
  final tag = dec.readTag();
  return switch (tag) {
    _tagPrevDir => PrevDir(_decodeProps(dec)),
    _tagPrevFile => _decodePrevFile(dec),
    _tagPrevSymlink => const PrevSymlink(),
    _tagNewEntry => const NewEntry(),
    _ => throw FormatException('Unknown PrevState tag: $tag'),
  };
}

PrevFile _decodePrevFile(MarshalDecoder dec) {
  final desc = _decodeProps(dec);
  final fp = Fingerprint(dec.readByteArray());
  final ress = dec.readInt();
  return PrevFile(desc, FullFingerprint(fp), const NoStamp(), RessStamp(ress));
}

Props _decodeProps(MarshalDecoder dec) {
  return Props(
    permissions: dec.readInt(),
    modTime: DateTime.fromMillisecondsSinceEpoch(dec.readInt64()),
    length: dec.readInt64(),
    ownerId: dec.readSignedInt(),
    groupId: dec.readSignedInt(),
  );
}
