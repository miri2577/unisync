/// CLI sync execution — ties together profile loading, sync engine, and TUI.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:unison_core/unison_core.dart';

import 'cli_ui.dart';

/// Run sync from CLI arguments.
void runSync(ArgResults args) {
  final profileDir = (args['profile-dir'] as String?) ??
      ProfileParser.defaultProfileDir();
  final batchMode = args['batch'] as bool;
  final autoMode = args['auto'] as bool;
  final watchMode = args['watch'] as bool;
  final repeatSec = args['repeat'] as String?;
  final maxErrors = int.tryParse(args['maxerrors'] as String) ?? -1;
  final maxThreads = int.tryParse(args['maxthreads'] as String) ?? 20;
  final ignorePatterns = (args['ignore'] as List<String>?) ?? [];

  // Determine roots
  Fspath root1;
  Fspath root2;
  UnisonPrefs? prefs;

  if (args.rest.length == 1) {
    // Profile mode
    final profileName = args.rest[0];
    prefs = UnisonPrefs();
    final parser = ProfileParser(profileDir);
    final errors = parser.loadProfile(profileName, prefs.registry);

    if (errors.isNotEmpty) {
      for (final e in errors) {
        stderr.writeln('Profile error: $e');
      }
      // Continue if there are roots despite errors
    }

    if (prefs.root.value.length < 2) {
      stderr.writeln('Error: profile "$profileName" must have exactly 2 roots.');
      exit(1);
    }

    root1 = Fspath.fromLocal(prefs.root.value[0]);
    root2 = Fspath.fromLocal(prefs.root.value[1]);
    print('Profile: $profileName');
  } else if (args.rest.length >= 2) {
    // Direct root mode
    root1 = Fspath.fromLocal(args.rest[0]);
    root2 = Fspath.fromLocal(args.rest[1]);
  } else {
    stderr.writeln('Error: specify a profile or two root directories.');
    exit(1);
  }

  print('Root 1: $root1');
  print('Root 2: $root2');

  // Verify roots exist
  if (!Directory(root1.toLocal()).existsSync()) {
    stderr.writeln('Error: root 1 does not exist: ${root1.toLocal()}');
    exit(1);
  }
  if (!Directory(root2.toLocal()).existsSync()) {
    stderr.writeln('Error: root 2 does not exist: ${root2.toLocal()}');
    exit(1);
  }

  // Build configs
  final updateConfig = UpdateConfig(
    useFastCheck: prefs?.fastCheck.value ?? true,
    fatTolerance: prefs?.fatFilesystem.value ?? false,
    shouldIgnore: ignorePatterns.isNotEmpty
        ? (path) {
            final filter = IgnoreFilter(ignorePatterns: ignorePatterns);
            return filter.shouldIgnore(path);
          }
        : null,
  );

  final forceDir = args['force'] as String?;
  final preferDir = args['prefer'] as String?;

  final reconConfig = ReconConfig(
    force: forceDir == 'replica1'
        ? true
        : forceDir == 'replica2'
            ? false
            : null,
    prefer: preferDir == 'replica1'
        ? true
        : preferDir == 'replica2'
            ? false
            : null,
    preferNewer: forceDir == 'newer' || preferDir == 'newer',
    noDeletion: prefs?.noDeletion.value ?? false,
    noUpdate: prefs?.noUpdate.value ?? false,
    noCreation: prefs?.noCreation.value ?? false,
  );

  // Create engine
  final store = ArchiveStore(profileDir);
  store.recoverAll();

  final transport = TransportOrchestrator(
    maxThreads: maxThreads,
    maxErrors: maxErrors,
  );
  final engine = SyncEngine(
    archiveStore: store,
    transport: transport,
  );

  // Watch mode
  if (watchMode) {
    _runWatchMode(engine, root1, root2, updateConfig, reconConfig, batchMode);
    return;
  }

  // Repeat mode
  if (repeatSec != null) {
    final interval = int.tryParse(repeatSec);
    if (interval == null || interval <= 0) {
      stderr.writeln('Error: --repeat must be a positive integer (seconds).');
      exit(1);
    }
    _runRepeatMode(engine, root1, root2, updateConfig, reconConfig,
        batchMode, Duration(seconds: interval));
    return;
  }

  // Single sync
  _runOnce(engine, root1, root2, updateConfig, reconConfig, batchMode, autoMode);
}

/// Run a single sync cycle.
void _runOnce(
  SyncEngine engine,
  Fspath root1,
  Fspath root2,
  UpdateConfig updateConfig,
  ReconConfig reconConfig,
  bool batchMode,
  bool autoMode,
) {
  if (batchMode || autoMode) {
    // Non-interactive: full sync in one call
    print('\nSyncing...');
    final result = engine.sync(
      root1, root2,
      updateConfig: updateConfig,
      reconConfig: reconConfig,
      onProgress: (phase, msg) => stdout.write('\r$msg${" " * 30}'),
    );
    stdout.write('\r${" " * 60}\r');
    printResult(result);
  } else {
    // Interactive: scan+reconcile first, let user review, then propagate
    print('\nScanning...');
    final result = engine.sync(
      root1, root2,
      updateConfig: updateConfig,
      reconConfig: reconConfig,
      onProgress: (phase, msg) => stdout.write('\r$msg${" " * 30}'),
    );
    stdout.write('\r${" " * 60}\r');

    // engine.sync already propagated — show results
    // (In future: split scan/recon/propagate for true interactive mode)
    printResult(result);
  }
}

/// Run in watch mode — sync on filesystem changes.
void _runWatchMode(
  SyncEngine engine,
  Fspath root1,
  Fspath root2,
  UpdateConfig updateConfig,
  ReconConfig reconConfig,
  bool batchMode,
) {
  print('\nWatch mode: monitoring for changes (Ctrl+C to stop)...');

  final controller = engine.syncWatch(
    root1,
    root2,
    updateConfig: updateConfig,
    reconConfig: reconConfig,
    onProgress: (phase, msg) {
      stdout.write('\r[$phase] $msg${" " * 20}');
    },
    onSyncComplete: (result) {
      stdout.write('\r${" " * 60}\r');
      if (result.propagated > 0 || result.failed > 0) {
        printResult(result);
      }
      print('Watching...');
    },
  );

  // Block until Ctrl+C
  ProcessSignal.sigint.watch().listen((_) {
    print('\nStopping watch...');
    controller.stop();
    exit(0);
  });

  // Keep alive
  while (controller.isRunning) {
    sleep(const Duration(seconds: 1));
  }
}

/// Run in repeat mode — sync every N seconds.
void _runRepeatMode(
  SyncEngine engine,
  Fspath root1,
  Fspath root2,
  UpdateConfig updateConfig,
  ReconConfig reconConfig,
  bool batchMode,
  Duration interval,
) {
  print('\nRepeat mode: syncing every ${interval.inSeconds}s (Ctrl+C to stop)...');

  var running = true;
  ProcessSignal.sigint.watch().listen((_) {
    print('\nStopping...');
    running = false;
    exit(0);
  });

  while (running) {
    final result = engine.sync(
      root1,
      root2,
      updateConfig: updateConfig,
      reconConfig: reconConfig,
    );

    if (result.propagated > 0 || result.failed > 0) {
      printResult(result);
    } else {
      stdout.write('\r[${DateTime.now().toString().substring(11, 19)}] '
          'In sync${" " * 30}');
    }

    sleep(interval);
  }
}

/// Run as remote sync server.
void runServerMode(String rootPath) {
  print('Starting server mode for: $rootPath');
  final root = Fspath.fromLocal(rootPath);

  if (!Directory(rootPath).existsSync()) {
    stderr.writeln('Error: root directory does not exist: $rootPath');
    exit(1);
  }

  // runServer is async, block with a simple loop
  runServer(root);
}
