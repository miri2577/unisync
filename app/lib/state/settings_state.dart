import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unison_core/unison_core.dart';

/// Persisted app settings backed by a UnisonPrefs instance.
class AppSettings {
  final int maxThreads;
  final int maxErrors;
  final bool fastCheck;
  final bool times;
  final bool links;
  final bool fatFilesystem;
  final bool confirmBigDeletes;
  final bool preferNewer;
  final bool noDeletion;
  final bool noCreation;
  final bool noUpdate;
  final bool syncXattrs;
  final String sshCmd;
  final String sshArgs;
  final List<String> ignorePatterns;

  const AppSettings({
    this.maxThreads = 20,
    this.maxErrors = -1,
    this.fastCheck = true,
    this.times = true,
    this.links = true,
    this.fatFilesystem = false,
    this.confirmBigDeletes = true,
    this.preferNewer = false,
    this.noDeletion = false,
    this.noCreation = false,
    this.noUpdate = false,
    this.syncXattrs = false,
    this.sshCmd = 'ssh',
    this.sshArgs = '',
    this.ignorePatterns = const [],
  });

  AppSettings copyWith({
    int? maxThreads,
    int? maxErrors,
    bool? fastCheck,
    bool? times,
    bool? links,
    bool? fatFilesystem,
    bool? confirmBigDeletes,
    bool? preferNewer,
    bool? noDeletion,
    bool? noCreation,
    bool? noUpdate,
    bool? syncXattrs,
    String? sshCmd,
    String? sshArgs,
    List<String>? ignorePatterns,
  }) {
    return AppSettings(
      maxThreads: maxThreads ?? this.maxThreads,
      maxErrors: maxErrors ?? this.maxErrors,
      fastCheck: fastCheck ?? this.fastCheck,
      times: times ?? this.times,
      links: links ?? this.links,
      fatFilesystem: fatFilesystem ?? this.fatFilesystem,
      confirmBigDeletes: confirmBigDeletes ?? this.confirmBigDeletes,
      preferNewer: preferNewer ?? this.preferNewer,
      noDeletion: noDeletion ?? this.noDeletion,
      noCreation: noCreation ?? this.noCreation,
      noUpdate: noUpdate ?? this.noUpdate,
      syncXattrs: syncXattrs ?? this.syncXattrs,
      sshCmd: sshCmd ?? this.sshCmd,
      sshArgs: sshArgs ?? this.sshArgs,
      ignorePatterns: ignorePatterns ?? this.ignorePatterns,
    );
  }

  /// Convert to UpdateConfig for the sync engine.
  UpdateConfig toUpdateConfig() {
    final filter = ignorePatterns.isNotEmpty
        ? IgnoreFilter(ignorePatterns: ignorePatterns)
        : null;
    return UpdateConfig(
      useFastCheck: fastCheck,
      fatTolerance: fatFilesystem,
      shouldIgnore: filter != null ? (p) => filter.shouldIgnore(p) : null,
    );
  }

  /// Convert to ReconConfig for the sync engine.
  ReconConfig toReconConfig() {
    return ReconConfig(
      preferNewer: preferNewer,
      noDeletion: noDeletion,
      noCreation: noCreation,
      noUpdate: noUpdate,
    );
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  return AppSettingsNotifier();
});

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  void update(AppSettings Function(AppSettings) fn) {
    state = fn(state);
    _save();
  }

  void addIgnorePattern(String pattern) {
    state = state.copyWith(
      ignorePatterns: [...state.ignorePatterns, pattern],
    );
    _save();
  }

  void removeIgnorePattern(int index) {
    final list = List.of(state.ignorePatterns);
    list.removeAt(index);
    state = state.copyWith(ignorePatterns: list);
    _save();
  }

  /// Save settings to a simple config file.
  void _save() {
    try {
      final dir = ProfileParser.defaultProfileDir();
      Directory(dir).createSync(recursive: true);
      final file = File('$dir/unisync_settings.prf');
      final buf = StringBuffer();
      buf.writeln('maxthreads = ${state.maxThreads}');
      buf.writeln('maxerrors = ${state.maxErrors}');
      buf.writeln('fastcheck = ${state.fastCheck}');
      buf.writeln('times = ${state.times}');
      buf.writeln('links = ${state.links}');
      buf.writeln('fat = ${state.fatFilesystem}');
      buf.writeln('confirmbigdeletes = ${state.confirmBigDeletes}');
      buf.writeln('prefernewer = ${state.preferNewer}');
      buf.writeln('nodeletion = ${state.noDeletion}');
      buf.writeln('nocreation = ${state.noCreation}');
      buf.writeln('noupdate = ${state.noUpdate}');
      buf.writeln('xattrs = ${state.syncXattrs}');
      buf.writeln('sshcmd = ${state.sshCmd}');
      buf.writeln('sshargs = ${state.sshArgs}');
      for (final p in state.ignorePatterns) {
        buf.writeln('ignore = $p');
      }
      file.writeAsStringSync(buf.toString());
    } catch (_) {}
  }

  /// Load settings from config file.
  void _load() {
    try {
      final dir = ProfileParser.defaultProfileDir();
      final file = File('$dir/unisync_settings.prf');
      if (!file.existsSync()) return;

      final prefs = UnisonPrefs();
      final parser = ProfileParser(dir);
      parser.loadProfile('unisync_settings', prefs.registry);

      state = AppSettings(
        maxThreads: prefs.registry.get('maxthreads') is Pref<int>
            ? (prefs.registry.get('maxthreads') as Pref<int>).value
            : 20,
        fastCheck: prefs.fastCheck.value,
        times: prefs.times.value,
        links: prefs.links.value,
        fatFilesystem: prefs.fatFilesystem.value,
        confirmBigDeletes: prefs.confirmBigDeletes.value,
        preferNewer: prefs.preferNewer.value,
        noDeletion: prefs.noDeletion.value,
        noCreation: prefs.noCreation.value,
        noUpdate: prefs.noUpdate.value,
        syncXattrs: prefs.xattrs.value,
        sshCmd: prefs.sshCmd.value,
        sshArgs: prefs.sshArgs.value,
        ignorePatterns: prefs.ignore.value,
      );
    } catch (_) {}
  }
}
