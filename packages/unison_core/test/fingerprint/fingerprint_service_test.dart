import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;
  late Fspath root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unison_fp_test_');
    root = Fspath.fromLocal(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('FingerprintService', () {
    const svc = FingerprintService();

    test('computes correct MD5 for known content', () {
      // MD5 of "Hello World!" = ed076287532e86365e841e92bfc50d8c
      File('${tempDir.path}/hello.txt').writeAsStringSync('Hello World!');
      final fp = svc.file(root, SyncPath.fromString('hello.txt'));
      expect(fp.toHex(), 'ed076287532e86365e841e92bfc50d8c');
    });

    test('computes correct MD5 for empty file', () {
      // MD5 of "" = d41d8cd98f00b204e9800998ecf8427e
      File('${tempDir.path}/empty.txt').writeAsStringSync('');
      final fp = svc.file(root, SyncPath.fromString('empty.txt'));
      expect(fp.toHex(), 'd41d8cd98f00b204e9800998ecf8427e');
    });

    test('different content produces different fingerprint', () {
      File('${tempDir.path}/a.txt').writeAsStringSync('AAA');
      File('${tempDir.path}/b.txt').writeAsStringSync('BBB');
      final fpA = svc.file(root, SyncPath.fromString('a.txt'));
      final fpB = svc.file(root, SyncPath.fromString('b.txt'));
      expect(fpA, isNot(equals(fpB)));
    });

    test('same content produces same fingerprint', () {
      File('${tempDir.path}/a.txt').writeAsStringSync('same');
      File('${tempDir.path}/b.txt').writeAsStringSync('same');
      final fpA = svc.file(root, SyncPath.fromString('a.txt'));
      final fpB = svc.file(root, SyncPath.fromString('b.txt'));
      expect(fpA, equals(fpB));
    });

    test('handles large file (1MB)', () {
      final data = Uint8List(1024 * 1024); // 1MB of zeros
      File('${tempDir.path}/large.bin').writeAsBytesSync(data);
      final fp = svc.file(root, SyncPath.fromString('large.bin'));
      // Verify against reference MD5
      final expected = md5.convert(data);
      expect(fp.bytes, Uint8List.fromList(expected.bytes));
    });

    test('subfile computes hash of range', () {
      File('${tempDir.path}/range.txt').writeAsStringSync('ABCDEFGHIJ');
      // MD5 of "CDEF" (offset 2, length 4)
      final expected = md5.convert('CDEF'.codeUnits);
      final fp = svc.subfile('${tempDir.path}/range.txt', 2, 4);
      expect(fp.bytes, Uint8List.fromList(expected.bytes));
    });

    test('fileAbsoluteAsync produces same result as sync', () async {
      File('${tempDir.path}/async.txt').writeAsStringSync('async test');
      final syncFp = svc.fileAbsolute('${tempDir.path}/async.txt');
      final asyncFp = await svc.fileAbsoluteAsync('${tempDir.path}/async.txt');
      expect(asyncFp, equals(syncFp));
    });

    test('fullFile wraps in FullFingerprint', () {
      File('${tempDir.path}/full.txt').writeAsStringSync('full');
      final full = svc.fullFile(root, SyncPath.fromString('full.txt'));
      expect(full.resourceFork, isNull);
      expect(full.dataFork.isPseudo, isFalse);
    });

    test('throws for missing file', () {
      expect(
        () => svc.file(root, SyncPath.fromString('missing.txt')),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
