import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('Archive serialization', () {
    test('NoArchive roundtrip', () {
      final data = encodeArchive(const NoArchive());
      final decoded = decodeArchive(data);
      expect(decoded, isA<NoArchive>());
    });

    test('ArchiveSymlink roundtrip', () {
      final archive = ArchiveSymlink('/target/path');
      final data = encodeArchive(archive);
      final decoded = decodeArchive(data);
      expect(decoded, isA<ArchiveSymlink>());
      expect((decoded as ArchiveSymlink).target, '/target/path');
    });

    test('ArchiveFile roundtrip', () {
      final fp = FullFingerprint(
        Fingerprint(Uint8List.fromList(List.generate(16, (i) => i))),
      );
      final archive = ArchiveFile(
        Props(
          permissions: 0x1ED,
          modTime: DateTime(2024, 6, 15, 12, 30),
          length: 9876,
        ),
        fp,
        const NoStamp(),
        RessStamp.zero,
      );
      final data = encodeArchive(archive);
      final decoded = decodeArchive(data) as ArchiveFile;

      expect(decoded.desc.permissions, 0x1ED);
      expect(decoded.desc.length, 9876);
      expect(decoded.fingerprint.dataFork.toHex(), fp.dataFork.toHex());
      expect(decoded.stamp, isA<NoStamp>());
    });

    test('ArchiveFile with InodeStamp roundtrip', () {
      final archive = ArchiveFile(
        Props(permissions: 0, modTime: DateTime(2024), length: 0),
        FullFingerprint(Fingerprint(Uint8List(16))),
        const InodeStamp(123456),
        RessStamp.zero,
      );
      final data = encodeArchive(archive);
      final decoded = decodeArchive(data) as ArchiveFile;
      expect(decoded.stamp, isA<InodeStamp>());
      expect((decoded.stamp as InodeStamp).inode, 123456);
    });

    test('ArchiveFile with resource fork roundtrip', () {
      final fp = FullFingerprint(
        Fingerprint(Uint8List.fromList(List.filled(16, 0xAA))),
        Fingerprint(Uint8List.fromList(List.filled(16, 0xBB))),
      );
      final archive = ArchiveFile(
        Props(permissions: 0, modTime: DateTime(2024), length: 0),
        fp,
        const NoStamp(),
        RessStamp(42),
      );
      final data = encodeArchive(archive);
      final decoded = decodeArchive(data) as ArchiveFile;
      expect(decoded.fingerprint.resourceFork, isNotNull);
      expect(decoded.fingerprint.resourceFork!.toHex(),
          fp.resourceFork!.toHex());
      expect(decoded.ressStamp.value, 42);
    });

    test('ArchiveDir with children roundtrip', () {
      final children = emptyNameMap();
      children[Name('alpha.txt')] = ArchiveFile(
        Props(permissions: 0x1ED, modTime: DateTime(2024, 1, 1), length: 100),
        FullFingerprint(Fingerprint(Uint8List.fromList(List.filled(16, 1)))),
        const NoStamp(),
        RessStamp.zero,
      );
      children[Name('beta')] = ArchiveDir(
        Props(permissions: 0x1FF, modTime: DateTime(2024, 2, 1), length: 0),
        emptyNameMap(),
      );
      children[Name('gamma.lnk')] = ArchiveSymlink('/some/target');

      final archive = ArchiveDir(
        Props(permissions: 0x1FF, modTime: DateTime(2024, 3, 1), length: 0),
        children,
      );

      final data = encodeArchive(archive);
      final decoded = decodeArchive(data) as ArchiveDir;

      expect(decoded.children.length, 3);
      expect(decoded.children[Name('alpha.txt')], isA<ArchiveFile>());
      expect(decoded.children[Name('beta')], isA<ArchiveDir>());
      expect(decoded.children[Name('gamma.lnk')], isA<ArchiveSymlink>());
    });

    test('nested directories roundtrip', () {
      final innerChildren = emptyNameMap();
      innerChildren[Name('deep.txt')] = ArchiveFile(
        Props(permissions: 0x1ED, modTime: DateTime(2024), length: 42),
        FullFingerprint(Fingerprint(Uint8List(16))),
        const NoStamp(),
        RessStamp.zero,
      );

      final outerChildren = emptyNameMap();
      outerChildren[Name('inner')] = ArchiveDir(
        Props(permissions: 0x1FF, modTime: DateTime(2024), length: 0),
        innerChildren,
      );

      final archive = ArchiveDir(
        Props(permissions: 0x1FF, modTime: DateTime(2024), length: 0),
        outerChildren,
      );

      final data = encodeArchive(archive);
      final decoded = decodeArchive(data) as ArchiveDir;
      final inner = decoded.children[Name('inner')] as ArchiveDir;
      expect(inner.children[Name('deep.txt')], isA<ArchiveFile>());
    });

    test('version mismatch throws ArchiveVersionError', () {
      // Manually craft data with wrong version
      final enc = MarshalEncoder();
      enc.writeInt(999);
      enc.writeTag(3); // NoArchive
      expect(
        () => decodeArchive(enc.toBytes()),
        throwsA(isA<ArchiveVersionError>()),
      );
    });
  });
}
