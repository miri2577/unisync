/// External merge tool integration.
///
/// Mirrors OCaml Unison's merge system. Spawns an external merge program
/// with temp copies of both versions and an optional archive (base) version,
/// then checks the result.
library;

import 'dart:io';

import '../model/fspath.dart';
import '../model/sync_path.dart';
import '../util/trace.dart';

/// Result of a merge operation.
sealed class MergeResult {
  const MergeResult();
}

/// Merge succeeded — the output file contains the merged content.
class MergeSuccess extends MergeResult {
  final String outputPath;
  const MergeSuccess(this.outputPath);
}

/// Merge failed — the tool exited with an error or the user aborted.
class MergeFailure extends MergeResult {
  final String reason;
  final int? exitCode;
  const MergeFailure(this.reason, [this.exitCode]);
}

/// Configuration for the merge command.
///
/// The command string supports these variables:
/// - `CURRENT1` — path to replica 1's version
/// - `CURRENT2` — path to replica 2's version
/// - `CURRENTARCH` — path to the archive (base) version (if available)
/// - `CURRENTARCHOPT` — same as CURRENTARCH but empty string if unavailable
/// - `NEW` — path where the merged result should be written
/// - `PATH` — the relative sync path
/// - `BATCHMODE` — "batch" if in batch mode, empty otherwise
class MergeConfig {
  /// The merge command template with variable placeholders.
  final String command;

  /// Whether to run in batch mode (no UI prompts from merge tool).
  final bool batchMode;

  const MergeConfig({required this.command, this.batchMode = false});
}

/// Executes external merge operations.
class MergeExecutor {
  const MergeExecutor();

  /// Run an external merge for a conflicting file.
  ///
  /// Creates temp copies of both versions, runs the merge command,
  /// and returns the result.
  Future<MergeResult> merge({
    required Fspath root1,
    required Fspath root2,
    required SyncPath path,
    required MergeConfig config,
    String? archivePath,
  }) async {
    final file1 = root1.concat(path).toLocal();
    final file2 = root2.concat(path).toLocal();

    // Create temp directory for merge work
    final tempDir = Directory.systemTemp.createTempSync('unison_merge_');
    try {
      final tempFile1 = '${tempDir.path}/current1';
      final tempFile2 = '${tempDir.path}/current2';
      final tempOutput = '${tempDir.path}/new';
      final tempArchive = '${tempDir.path}/currentarch';

      // Copy current versions to temp
      File(file1).copySync(tempFile1);
      File(file2).copySync(tempFile2);

      // Copy archive version if available
      String archiveArg = '';
      String archiveOptArg = '';
      if (archivePath != null && File(archivePath).existsSync()) {
        File(archivePath).copySync(tempArchive);
        archiveArg = tempArchive;
        archiveOptArg = tempArchive;
      }

      // Build command with variable substitution
      final cmd = config.command
          .replaceAll('CURRENT1', tempFile1)
          .replaceAll('CURRENT2', tempFile2)
          .replaceAll('CURRENTARCHOPT', archiveOptArg)
          .replaceAll('CURRENTARCH', archiveArg)
          .replaceAll('NEW', tempOutput)
          .replaceAll('PATH', path.toString())
          .replaceAll('BATCHMODE', config.batchMode ? 'batch' : '');

      Trace.info(TraceCategory.general, 'Running merge: $cmd');

      // Execute merge command
      final result = await Process.run(
        _shellExecutable(),
        _shellArgs(cmd),
        runInShell: false,
      );

      if (result.exitCode != 0) {
        Trace.warning(
          TraceCategory.general,
          'Merge exited with code ${result.exitCode}: ${result.stderr}',
        );
        return MergeFailure(
          'Merge tool exited with code ${result.exitCode}',
          result.exitCode,
        );
      }

      // Check if output was created
      if (!File(tempOutput).existsSync()) {
        return const MergeFailure('Merge tool did not produce output file');
      }

      // Copy result back — caller is responsible for choosing which replica
      return MergeSuccess(tempOutput);
    } catch (e) {
      return MergeFailure('Merge error: $e');
    } finally {
      // Don't clean up temp dir yet — caller needs the output file
      // Caller should clean up after copying the result
    }
  }

  /// Apply a successful merge result to both replicas.
  void applyMergeResult(
    MergeSuccess result,
    Fspath root1,
    Fspath root2,
    SyncPath path,
  ) {
    final dst1 = root1.concat(path).toLocal();
    final dst2 = root2.concat(path).toLocal();

    File(result.outputPath).copySync(dst1);
    File(result.outputPath).copySync(dst2);

    // Clean up temp directory
    final tempDir = File(result.outputPath).parent;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}

    Trace.info(
      TraceCategory.general,
      'Applied merge result to both replicas: $path',
    );
  }

  /// Parse a merge command pattern from preferences.
  ///
  /// Format: `<pathspec> -> <command>`
  /// Example: `Name *.txt -> diff3 -m CURRENT1 CURRENTARCH CURRENT2 > NEW`
  static (String pattern, String command)? parseMergeSpec(String spec) {
    final arrowIdx = spec.indexOf('->');
    if (arrowIdx == -1) return null;

    final pattern = spec.substring(0, arrowIdx).trim();
    final command = spec.substring(arrowIdx + 2).trim();

    if (pattern.isEmpty || command.isEmpty) return null;
    return (pattern, command);
  }

  String _shellExecutable() {
    if (Platform.isWindows) return 'cmd';
    return '/bin/sh';
  }

  List<String> _shellArgs(String command) {
    if (Platform.isWindows) return ['/c', command];
    return ['-c', command];
  }
}
