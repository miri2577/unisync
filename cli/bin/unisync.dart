/// UniSync CLI — command-line interface for file synchronization.
///
/// Usage:
///   unisync <profile>              Sync using a profile
///   unisync <root1> <root2>        Sync two directories directly
///   unisync -batch <profile>       Sync without asking (non-conflicting only)
///   unisync -server <root>         Run as remote server
///   unisync -list                  List available profiles
import 'dart:io';

import 'package:args/args.dart';
import 'package:unisync_cli/cli_sync.dart';
import 'package:unisync_cli/cli_ui.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help')
    ..addFlag('version', negatable: false, help: 'Show version')
    ..addFlag('batch', abbr: 'b', negatable: false,
        help: 'Batch mode: sync non-conflicting changes without asking')
    ..addFlag('auto', abbr: 'a', negatable: false,
        help: 'Auto mode: accept all default actions')
    ..addFlag('list', abbr: 'l', negatable: false,
        help: 'List available profiles')
    ..addFlag('server', negatable: false,
        help: 'Run as remote sync server')
    ..addFlag('watch', abbr: 'w', negatable: false,
        help: 'Watch mode: continuous sync on file changes')
    ..addOption('repeat', abbr: 'r',
        help: 'Repeat sync every N seconds')
    ..addOption('profile-dir',
        help: 'Profile directory (default: ~/.unison)')
    ..addOption('force',
        help: 'Force direction: newer, older, replica1, replica2')
    ..addOption('prefer',
        help: 'Prefer side for conflicts: newer, older, replica1, replica2')
    ..addMultiOption('ignore', abbr: 'i',
        help: 'Add ignore pattern (can repeat)')
    ..addOption('maxerrors',
        help: 'Max errors before abort (-1=never)', defaultsTo: '-1')
    ..addOption('maxthreads',
        help: 'Max concurrent transfers', defaultsTo: '20');

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('Use --help for usage information.');
    exit(1);
  }

  if (args['help'] as bool) {
    _printUsage(parser);
    exit(0);
  }

  if (args['version'] as bool) {
    print('UniSync 0.1.0');
    print('Dart/Flutter bidirectional file synchronizer');
    exit(0);
  }

  if (args['list'] as bool) {
    listProfiles(args['profile-dir'] as String?);
    exit(0);
  }

  if (args['server'] as bool) {
    if (args.rest.isEmpty) {
      stderr.writeln('Error: server mode requires a root directory.');
      exit(1);
    }
    runServerMode(args.rest[0]);
    exit(0);
  }

  // Sync mode
  if (args.rest.isEmpty) {
    stderr.writeln('Error: specify a profile name or two root directories.');
    stderr.writeln('Use --help for usage information.');
    exit(1);
  }

  runSync(args);
}

void _printUsage(ArgParser parser) {
  print('''
UniSync — Bidirectional File Synchronizer

Usage:
  unisync <profile>              Sync using a saved profile
  unisync <root1> <root2>        Sync two directories directly
  unisync --list                 List available profiles
  unisync --server <root>        Run as remote sync server

Examples:
  unisync my-documents           Load profile "my-documents.prf" and sync
  unisync C:\\Docs D:\\Backup      Sync two local directories
  unisync --batch my-docs        Sync without asking (skip conflicts)
  unisync --watch my-docs        Continuous sync on file changes

Options:
${parser.usage}

Interactive commands during sync:
  >  or  →     Set direction: replica 1 to replica 2
  <  or  ←     Set direction: replica 2 to replica 1
  /            Skip this item
  m            Mark for merge
  d            Show details
  A            Accept all defaults
  1            Set all to replica 1 → 2
  2            Set all to replica 2 → 1
  C            Skip all conflicts
  g            Go — execute propagation
  q            Quit without syncing
  ?            Show this help
''');
}
