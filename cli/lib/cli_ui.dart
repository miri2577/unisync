/// Terminal UI for interactive sync review.
///
/// Displays reconciliation items and handles keyboard input for
/// direction changes, batch operations, and navigation.
library;

import 'dart:io';

import 'package:unison_core/unison_core.dart';

/// ANSI color codes.
const _reset = '\x1b[0m';
const _bold = '\x1b[1m';
const _red = '\x1b[31m';
const _green = '\x1b[32m';
const _yellow = '\x1b[33m';
const _blue = '\x1b[34m';
const _cyan = '\x1b[36m';
const _gray = '\x1b[90m';

/// Display the reconciliation items and let the user interact.
///
/// Returns `true` if the user wants to proceed with propagation.
bool reviewReconItems(List<ReconItem> items) {
  if (items.isEmpty) {
    print('\n${_green}Nothing to do — everything is in sync.$_reset\n');
    return false;
  }

  var currentIndex = 0;

  _printSummary(items);
  _printItems(items, currentIndex);

  while (true) {
    stdout.write('\n${_bold}Command (?=help): $_reset');
    final input = stdin.readLineSync()?.trim() ?? '';

    if (input.isEmpty) continue;

    switch (input) {
      // Navigation
      case 'n' || 'j':
        if (currentIndex < items.length - 1) currentIndex++;
        _printItems(items, currentIndex);
      case 'p' || 'k':
        if (currentIndex > 0) currentIndex--;
        _printItems(items, currentIndex);
      case '0':
        currentIndex = 0;
        _printItems(items, currentIndex);
      case '9':
        currentIndex = items.length - 1;
        _printItems(items, currentIndex);

      // Direction for current item
      case '>' || '.' || 'f':
        _setDirection(items, currentIndex, const Replica1ToReplica2());
        _printItems(items, currentIndex);
      case '<' || ',':
        _setDirection(items, currentIndex, const Replica2ToReplica1());
        _printItems(items, currentIndex);
      case '/':
        _setDirection(items, currentIndex, Conflict('skipped by user'));
        _printItems(items, currentIndex);
      case 'm':
        _setDirection(items, currentIndex, const Merge());
        _printItems(items, currentIndex);
      case 'r':
        if (items[currentIndex].replicas case Different(diff: var d)) {
          d.revertToDefault();
        }
        _printItems(items, currentIndex);

      // Batch operations
      case 'A':
        batchAcceptDefaults(items);
        print('${_green}Accepted all defaults.$_reset');
        _printItems(items, currentIndex);
      case '1':
        batchForceRight(items);
        print('${_green}All set to replica 1 → 2.$_reset');
        _printItems(items, currentIndex);
      case '2':
        batchForceLeft(items);
        print('${_green}All set to replica 2 → 1.$_reset');
        _printItems(items, currentIndex);
      case 'C':
        batchSkipConflicts(items);
        print('${_yellow}Skipped all conflicts.$_reset');
        _printItems(items, currentIndex);
      case 'R':
        batchRevertAll(items);
        print('${_blue}Reverted all to defaults.$_reset');
        _printItems(items, currentIndex);

      // Details
      case 'd' || 'x':
        _printDetail(items[currentIndex]);

      // List
      case 'l':
        _printItems(items, currentIndex);
      case 'L':
        _printItemsTerse(items);

      // Execute
      case 'g' || 'y':
        final actionCount = items.where((i) =>
            i.direction is Replica1ToReplica2 ||
            i.direction is Replica2ToReplica1 ||
            i.direction is Merge).length;
        final skipCount = items.where((i) => i.direction is Conflict).length;
        print('\n${_bold}Proceed with $actionCount actions '
            '($skipCount skipped)?$_reset [y/n] ');
        final confirm = stdin.readLineSync()?.trim() ?? '';
        if (confirm == 'y' || confirm == 'Y' || confirm == 'g') {
          return true;
        }
        print('Cancelled.');

      // Quit
      case 'q':
        print('Quit without syncing.');
        return false;

      // Help
      case '?':
        _printHelp();

      default:
        print('${_gray}Unknown command: "$input". Type ? for help.$_reset');
    }
  }
}

void _setDirection(List<ReconItem> items, int index, Direction dir) {
  if (items[index].replicas case Different(diff: var d)) {
    d.direction = dir;
  }
}

void _printSummary(List<ReconItem> items) {
  final conflicts = items.where((i) => i.direction is Conflict).length;
  final toRight = items.where((i) => i.direction is Replica1ToReplica2).length;
  final toLeft = items.where((i) => i.direction is Replica2ToReplica1).length;
  final merges = items.where((i) => i.direction is Merge).length;

  print('\n$_bold${items.length} changes detected:$_reset');
  if (toRight > 0) print('  ${_green}$toRight$_reset  replica 1 → 2');
  if (toLeft > 0) print('  ${_cyan}$toLeft$_reset  replica 2 → 1');
  if (conflicts > 0) print('  ${_red}$conflicts$_reset  conflicts');
  if (merges > 0) print('  ${_blue}$merges$_reset  merges');
}

void _printItems(List<ReconItem> items, int current) {
  print('');
  // Show a window of items around the current one
  final windowSize = 15;
  final start = (current - windowSize ~/ 2).clamp(0, items.length - 1);
  final end = (start + windowSize).clamp(0, items.length);

  for (var i = start; i < end; i++) {
    final marker = i == current ? '>' : ' ';
    print('$marker ${_formatItem(items[i])}');
  }

  if (items.length > windowSize) {
    print('${_gray}  ... ${items.length} items total '
        '(${current + 1}/${items.length})$_reset');
  }
}

void _printItemsTerse(List<ReconItem> items) {
  print('');
  for (var i = 0; i < items.length; i++) {
    print('  ${_formatItem(items[i])}');
  }
}

String _formatItem(ReconItem item) {
  final arrow = _formatArrow(item);
  final path = item.path1.toString();
  final left = _formatStatus(item, true);
  final right = _formatStatus(item, false);

  return '$left $arrow $right  $path';
}

String _formatArrow(ReconItem item) {
  return switch (item.replicas) {
    Problem() => '${_red} ???? $_reset',
    Different(diff: var d) => switch (d.direction) {
      Replica1ToReplica2() => '$_green----->$_reset',
      Replica2ToReplica1() => '$_cyan<-----$_reset',
      Conflict() => '$_red<-?->$_reset',
      Merge() => '$_blue<-M->$_reset',
    },
  };
}

String _formatStatus(ReconItem item, bool isLeft) {
  if (item.replicas case Different(diff: var d)) {
    final rc = isLeft ? d.rc1 : d.rc2;
    final s = switch (rc.status) {
      ReplicaStatus.created => '${_green}new    $_reset',
      ReplicaStatus.modified => '${_yellow}changed$_reset',
      ReplicaStatus.deleted => '${_red}deleted$_reset',
      ReplicaStatus.propsChanged => '${_blue}props  $_reset',
      ReplicaStatus.unchanged => '       ',
    };
    return s;
  }
  return '       ';
}

void _printDetail(ReconItem item) {
  print('\n${_bold}Details for: ${item.path1}$_reset');

  if (item.replicas case Different(diff: var d)) {
    print('  Direction: ${d.direction}');
    print('  Default:   ${d.defaultDirection}');
    print('  Replica 1: ${d.rc1.status.name}');
    _printProps('    Props 1', d.rc1.desc);
    print('  Replica 2: ${d.rc2.status.name}');
    _printProps('    Props 2', d.rc2.desc);
    if (d.errors1.isNotEmpty) {
      print('  ${_red}Errors (R1): ${d.errors1.join(", ")}$_reset');
    }
    if (d.errors2.isNotEmpty) {
      print('  ${_red}Errors (R2): ${d.errors2.join(", ")}$_reset');
    }
  } else if (item.replicas case Problem(message: var msg)) {
    print('  ${_red}Problem: $msg$_reset');
  }
}

void _printProps(String label, Props props) {
  print('$label: size=${props.length}, '
      'perm=${props.permissions.toRadixString(8)}, '
      'mod=${props.modTime}');
}

void _printHelp() {
  print('''

${_bold}Navigation:$_reset
  n/j     Next item          p/k     Previous item
  0       First item         9       Last item

${_bold}Direction (current item):$_reset
  > . f   Replica 1 → 2      <  ,    Replica 2 → 1
  /       Skip               m       Merge
  r       Revert to default

${_bold}Batch operations:$_reset
  A       Accept all defaults
  1       All → replica 2    2       All → replica 1
  C       Skip all conflicts R       Revert all

${_bold}Info:$_reset
  d x     Show details       l       List all items
  L       List terse

${_bold}Action:$_reset
  g y     Go — propagate     q       Quit without sync
  ?       This help
''');
}

/// Display propagation progress in the terminal.
void printProgress(PropagationProgress progress) {
  final pct = progress.total > 0
      ? (progress.completed * 100 ~/ progress.total)
      : 0;
  final path = progress.currentPath?.toString() ?? '';
  final truncPath = path.length > 50 ? '...${path.substring(path.length - 47)}' : path;
  stdout.write(
    '\r[$pct%] ${progress.completed}/${progress.total} '
    '(${progress.failed} failed) $truncPath'
    '${" " * 20}', // clear trailing chars
  );
}

/// Display final sync result.
void printResult(SyncResult result) {
  print('\n');
  print('$_bold--- Sync complete ---$_reset');
  print('  ${_green}Propagated: ${result.propagated}$_reset');
  if (result.skipped > 0) {
    print('  ${_yellow}Skipped:    ${result.skipped}$_reset');
  }
  if (result.failed > 0) {
    print('  ${_red}Failed:     ${result.failed}$_reset');
  }
  if (result.scanErrors.isNotEmpty) {
    print('  ${_red}Scan errors: ${result.scanErrors.length}$_reset');
    for (final (path, msg) in result.scanErrors) {
      print('    $path: $msg');
    }
  }
}

/// List available profiles.
void listProfiles(String? profileDir) {
  final dir = profileDir ?? ProfileParser.defaultProfileDir();
  final parser = ProfileParser(dir);
  final profiles = parser.listProfiles();

  if (profiles.isEmpty) {
    print('No profiles found in $dir');
    return;
  }

  print('${_bold}Available profiles:$_reset\n');
  for (final name in profiles) {
    final info = scanProfile(dir, name);
    if (info != null) {
      final label = info.label != null ? ' (${info.label})' : '';
      final key = info.key != null ? ' [${info.key}]' : '';
      final roots = info.roots.length >= 2
          ? '${info.roots[0]} <-> ${info.roots[1]}'
          : info.roots.join(', ');
      print('  ${_bold}$name$_reset$label$key');
      print('    $roots');
    } else {
      print('  $name');
    }
  }
}
