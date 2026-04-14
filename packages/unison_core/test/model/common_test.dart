import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('parseRoot', () {
    test('local path', () {
      final root = parseRoot('/home/user/docs');
      expect(root, isA<ConnectLocal>());
      expect((root as ConnectLocal).path, '/home/user/docs');
    });

    test('Windows local path', () {
      final root = parseRoot('C:\\Users\\test');
      expect(root, isA<ConnectLocal>());
    });

    test('SSH URI with user and port', () {
      final root = parseRoot('ssh://alice@myserver:2222/home/alice');
      expect(root, isA<ConnectByShell>());
      final ssh = root as ConnectByShell;
      expect(ssh.user, 'alice');
      expect(ssh.host, 'myserver');
      expect(ssh.port, 2222);
      expect(ssh.path, '/home/alice');
    });

    test('SSH URI without user and port', () {
      final root = parseRoot('ssh://myserver/data');
      final ssh = root as ConnectByShell;
      expect(ssh.user, isNull);
      expect(ssh.host, 'myserver');
      expect(ssh.port, isNull);
      expect(ssh.path, '/data');
    });

    test('legacy SSH syntax user@host:path', () {
      final root = parseRoot('bob@server:/home/bob');
      final ssh = root as ConnectByShell;
      expect(ssh.user, 'bob');
      expect(ssh.host, 'server');
      expect(ssh.path, '/home/bob');
    });

    test('legacy SSH syntax host:path', () {
      final root = parseRoot('server:/data');
      final ssh = root as ConnectByShell;
      expect(ssh.user, isNull);
      expect(ssh.host, 'server');
      expect(ssh.path, '/data');
    });

    test('socket URI', () {
      final root = parseRoot('socket://myhost:5000/sync');
      expect(root, isA<ConnectBySocket>());
      final sock = root as ConnectBySocket;
      expect(sock.host, 'myhost');
      expect(sock.port, 5000);
      expect(sock.path, '/sync');
    });

    test('socket URI without port throws', () {
      expect(() => parseRoot('socket://myhost/sync'), throwsArgumentError);
    });
  });
}
