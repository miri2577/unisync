/// Archive binary serialization.
///
/// Encodes/decodes [Archive] trees to/from binary format for disk persistence.
library;

import 'dart:typed_data';

import '../model/archive.dart';
import '../model/fileinfo.dart';
import '../model/fingerprint.dart';
import '../model/name.dart';
import '../model/props.dart';
import '../util/marshal.dart';

// Tag constants for archive node types.
const _tagDir = 0;
const _tagFile = 1;
const _tagSymlink = 2;
const _tagNoArchive = 3;

// Tag constants for stamps.
const _tagInodeStamp = 0;
const _tagNoStamp = 1;
const _tagRescanStamp = 2;

/// Encode an [Archive] tree to binary.
Uint8List encodeArchive(Archive archive) {
  final enc = MarshalEncoder();
  enc.writeInt(archiveFormat); // version header
  _writeArchive(enc, archive);
  return enc.toBytes();
}

/// Decode an [Archive] tree from binary.
///
/// Throws [ArchiveVersionError] if the format version doesn't match.
Archive decodeArchive(Uint8List data) {
  final dec = MarshalDecoder(data);
  final version = dec.readInt();
  if (version != archiveFormat) {
    throw ArchiveVersionError(version, archiveFormat);
  }
  return _readArchive(dec);
}

void _writeArchive(MarshalEncoder enc, Archive archive) {
  switch (archive) {
    case ArchiveDir(desc: var desc, children: var children):
      enc.writeTag(_tagDir);
      _writeProps(enc, desc);
      enc.writeInt(children.length);
      for (final MapEntry(key: name, value: child) in children.entries) {
        enc.writeString(name.raw);
        _writeArchive(enc, child);
      }
    case ArchiveFile(
        desc: var desc,
        fingerprint: var fp,
        stamp: var stamp,
        ressStamp: var ress,
      ):
      enc.writeTag(_tagFile);
      _writeProps(enc, desc);
      _writeFullFingerprint(enc, fp);
      _writeStamp(enc, stamp);
      enc.writeInt(ress.value);
    case ArchiveSymlink(target: var target):
      enc.writeTag(_tagSymlink);
      enc.writeString(target);
    case NoArchive():
      enc.writeTag(_tagNoArchive);
  }
}

Archive _readArchive(MarshalDecoder dec) {
  final tag = dec.readTag();
  return switch (tag) {
    _tagDir => _readArchiveDir(dec),
    _tagFile => _readArchiveFile(dec),
    _tagSymlink => ArchiveSymlink(dec.readString()),
    _tagNoArchive => const NoArchive(),
    _ => throw FormatException('Unknown archive tag: $tag'),
  };
}

ArchiveDir _readArchiveDir(MarshalDecoder dec) {
  final desc = _readProps(dec);
  final count = dec.readInt();
  final children = emptyNameMap();
  for (var i = 0; i < count; i++) {
    final name = Name(dec.readString());
    final child = _readArchive(dec);
    children[name] = child;
  }
  return ArchiveDir(desc, children);
}

ArchiveFile _readArchiveFile(MarshalDecoder dec) {
  final desc = _readProps(dec);
  final fp = _readFullFingerprint(dec);
  final stamp = _readStamp(dec);
  final ressValue = dec.readInt();
  return ArchiveFile(desc, fp, stamp, RessStamp(ressValue));
}

void _writeProps(MarshalEncoder enc, Props props) {
  enc.writeInt(props.permissions);
  enc.writeInt64(props.modTime.millisecondsSinceEpoch);
  enc.writeInt64(props.length);
  enc.writeSignedInt(props.ownerId);
  enc.writeSignedInt(props.groupId);
}

Props _readProps(MarshalDecoder dec) {
  final permissions = dec.readInt();
  final modTimeMs = dec.readInt64();
  final length = dec.readInt64();
  final ownerId = dec.readSignedInt();
  final groupId = dec.readSignedInt();
  return Props(
    permissions: permissions,
    modTime: DateTime.fromMillisecondsSinceEpoch(modTimeMs),
    length: length,
    ownerId: ownerId,
    groupId: groupId,
  );
}

void _writeFullFingerprint(MarshalEncoder enc, FullFingerprint fp) {
  enc.writeByteArray(fp.dataFork.bytes);
  enc.writeBool(fp.resourceFork != null);
  if (fp.resourceFork != null) {
    enc.writeByteArray(fp.resourceFork!.bytes);
  }
}

FullFingerprint _readFullFingerprint(MarshalDecoder dec) {
  final data = Fingerprint(dec.readByteArray());
  final hasRess = dec.readBool();
  final ress = hasRess ? Fingerprint(dec.readByteArray()) : null;
  return FullFingerprint(data, ress);
}

void _writeStamp(MarshalEncoder enc, Stamp stamp) {
  switch (stamp) {
    case InodeStamp(inode: var inode):
      enc.writeTag(_tagInodeStamp);
      enc.writeInt64(inode);
    case NoStamp():
      enc.writeTag(_tagNoStamp);
    case RescanStamp():
      enc.writeTag(_tagRescanStamp);
  }
}

Stamp _readStamp(MarshalDecoder dec) {
  final tag = dec.readTag();
  return switch (tag) {
    _tagInodeStamp => InodeStamp(dec.readInt64()),
    _tagNoStamp => const NoStamp(),
    _tagRescanStamp => const RescanStamp(),
    _ => throw FormatException('Unknown stamp tag: $tag'),
  };
}

/// Thrown when archive format version doesn't match.
class ArchiveVersionError extends Error {
  final int found;
  final int expected;
  ArchiveVersionError(this.found, this.expected);

  @override
  String toString() =>
      'Archive version mismatch: found $found, expected $expected';
}
