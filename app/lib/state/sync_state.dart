import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unison_core/unison_core.dart';

import 'credentials.dart';
import 'settings_state.dart';

/// Current sync operation phase.
enum AppSyncPhase { idle, scanning, reconciling, propagating, done, error }

/// State for profile list.
class ProfileListState {
  final List<ProfileInfo> profiles;
  final bool isLoading;

  const ProfileListState({this.profiles = const [], this.isLoading = false});

  ProfileListState copyWith({List<ProfileInfo>? profiles, bool? isLoading}) {
    return ProfileListState(
      profiles: profiles ?? this.profiles,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Provider for profile directory path.
final profileDirProvider = Provider<String>((ref) {
  return ProfileParser.defaultProfileDir();
});

/// Provider for the profile list.
final profileListProvider =
    StateNotifierProvider<ProfileListNotifier, ProfileListState>((ref) {
  return ProfileListNotifier(ref.watch(profileDirProvider));
});

class ProfileListNotifier extends StateNotifier<ProfileListState> {
  final String _profileDir;

  ProfileListNotifier(this._profileDir)
      : super(const ProfileListState()) {
    refresh();
  }

  void refresh() {
    state = state.copyWith(isLoading: true);
    final parser = ProfileParser(_profileDir);
    final names = parser.listProfiles();
    final profiles = <ProfileInfo>[];
    for (final name in names) {
      final info = scanProfile(_profileDir, name);
      if (info != null) profiles.add(info);
    }
    state = ProfileListState(profiles: profiles);
  }

  void createProfile(String name, String root1, String root2) {
    Directory(_profileDir).createSync(recursive: true);
    final content = 'root = $root1\nroot = $root2\n';
    File('$_profileDir/$name.prf').writeAsStringSync(content);
    refresh();
  }

  void deleteProfile(String name) {
    final file = File('$_profileDir/$name.prf');
    if (file.existsSync()) file.deleteSync();
    refresh();
  }
}

/// State for an active sync operation.
class SyncOperationState {
  final AppSyncPhase phase;
  final String message;
  final List<ReconItem> reconItems;
  final SyncResult? result;
  final String? error;
  final List<String> log;

  const SyncOperationState({
    this.phase = AppSyncPhase.idle,
    this.message = '',
    this.reconItems = const [],
    this.result,
    this.error,
    this.log = const [],
  });

  SyncOperationState copyWith({
    AppSyncPhase? phase,
    String? message,
    List<ReconItem>? reconItems,
    SyncResult? result,
    String? error,
    List<String>? log,
  }) {
    return SyncOperationState(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      reconItems: reconItems ?? this.reconItems,
      result: result ?? this.result,
      error: error ?? this.error,
      log: log ?? this.log,
    );
  }
}

/// Provider for the active sync operation.
final syncOperationProvider =
    StateNotifierProvider<SyncOperationNotifier, SyncOperationState>((ref) {
  return SyncOperationNotifier(
    ref.watch(profileDirProvider),
    ref.watch(appSettingsProvider),
  );
});

class SyncOperationNotifier extends StateNotifier<SyncOperationState> {
  final String _profileDir;
  final AppSettings _appSettings;

  SyncOperationNotifier(this._profileDir, this._appSettings)
      : super(const SyncOperationState()) {
    // Pipe core Trace output into the UI log.
    Trace.handler = (cat, level, msg) {
      _log('[${cat.name}] $msg');
    };
  }

  void _log(String line) {
    if (!mounted) return;
    final ts = DateTime.now().toString().substring(11, 19);
    state = state.copyWith(log: [...state.log, '$ts  $line']);
  }

  /// Start a sync for a profile.
  void scan(String profileName) {
    _scanAsync(profileName).catchError((e) {
      if (mounted) {
        state = state.copyWith(
          phase: AppSyncPhase.error,
          error: 'Unhandled: $e\n${e is Error ? e.stackTrace : ""}',
        );
      }
    });
  }

  Future<void> _scanAsync(String profileName) async {
    state = SyncOperationState(
      phase: AppSyncPhase.scanning,
      message: 'Loading profile...',
      log: ['${DateTime.now().toString().substring(11, 19)}  Starting sync for "$profileName"'],
    );

    try {
      // Load profile
      final prefs = UnisonPrefs();
      final parser = ProfileParser(_profileDir);
      final errors = parser.loadProfile(profileName, prefs.registry);
      if (errors.isNotEmpty) {
        state = state.copyWith(
          phase: AppSyncPhase.error,
          error: errors.map((e) => e.toString()).join('\n'),
        );
        return;
      }

      if (prefs.root.value.length < 2) {
        state = state.copyWith(
          phase: AppSyncPhase.error,
          error: 'Profile must have exactly 2 roots',
        );
        return;
      }

      final root1Str = prefs.root.value[0];
      final root2Str = prefs.root.value[1];

      // Check if root2 is WebDAV
      final isWebDav = root2Str.startsWith('webdav://');

      _log('Root 1: $root1Str');
      _log('Root 2: $root2Str');
      _log('Mode: ${isWebDav ? "WebDAV" : "Local"}');

      if (isWebDav) {
        await _syncWebDav(profileName, root1Str, prefs);
      } else {
        _syncLocal(root1Str, root2Str, prefs);
      }
    } catch (e) {
      state = state.copyWith(
        phase: AppSyncPhase.error,
        error: '$e',
      );
    }
  }

  /// Sync with a WebDAV remote.
  Future<void> _syncWebDav(String profileName, String root1Str, UnisonPrefs prefs) async {
    final root1 = Fspath.fromLocal(root1Str);

    // Read WebDAV URL/username from profile, password from secure storage
    final webdavUrl = (prefs.registry.get('webdavurl') as Pref<String>?)?.value ?? '';
    final webdavUser = (prefs.registry.get('webdavuser') as Pref<String>?)?.value ?? '';
    var webdavPass = await Credentials.getPassword(profileName) ?? '';

    // Backward compat: legacy profiles may still have webdavpass in .prf
    if (webdavPass.isEmpty) {
      final legacyPass = (prefs.registry.get('webdavpass') as Pref<String>?)?.value ?? '';
      if (legacyPass.isNotEmpty) {
        // Migrate to secure storage and remove from profile on next save
        webdavPass = legacyPass;
        await Credentials.setPassword(profileName, legacyPass);
      }
    }

    if (webdavUrl.isEmpty || webdavUser.isEmpty) {
      state = state.copyWith(
        phase: AppSyncPhase.error,
        error: 'WebDAV URL and username are required',
      );
      return;
    }

    if (webdavPass.isEmpty) {
      state = state.copyWith(
        phase: AppSyncPhase.error,
        error: 'No password stored for profile "$profileName".\n'
            'Edit the profile to enter your WebDAV password.',
      );
      return;
    }

    _log('WebDAV URL: $webdavUrl');
    _log('WebDAV user: $webdavUser');

    final webdav = WebDavClient(WebDavConfig(
      baseUrl: webdavUrl,
      username: webdavUser,
      password: webdavPass,
    ));

    state = state.copyWith(message: 'Connecting to WebDAV...');
    _log('Testing WebDAV connection (PROPFIND)...');

    final connected = await webdav.testConnection();
    if (!connected) {
      _log('Connection FAILED');
      state = state.copyWith(
        phase: AppSyncPhase.error,
        error: 'Could not connect to WebDAV server: $webdavUrl',
      );
      webdav.close();
      return;
    }
    _log('Connected OK');

    final store = ArchiveStore(_profileDir);
    store.recoverAll();

    final engine = WebDavSyncEngine(
      localRoot: root1,
      webdav: webdav,
      profileName: profileName,
      archiveStore: store,
    );

    final result = await engine.sync(
      onProgress: (phase, msg) {
        final appPhase = switch (phase) {
          SyncPhase.scanning => AppSyncPhase.scanning,
          SyncPhase.reconciling => AppSyncPhase.reconciling,
          SyncPhase.propagating => AppSyncPhase.propagating,
          SyncPhase.updatingArchive => AppSyncPhase.propagating,
          SyncPhase.done => AppSyncPhase.done,
        };
        state = state.copyWith(phase: appPhase, message: msg);
      },
    );

    webdav.close();

    state = state.copyWith(
      phase: AppSyncPhase.done,
      message: 'Sync complete: ${result.propagated} propagated, '
          '${result.skipped} skipped, ${result.failed} failed',
      reconItems: result.reconItems,
      result: result,
    );
  }

  /// Sync two local directories.
  void _syncLocal(String root1Str, String root2Str, UnisonPrefs prefs) {
    final root1 = Fspath.fromLocal(root1Str);
    final root2 = Fspath.fromLocal(root2Str);
    final store = ArchiveStore(_profileDir);
    store.recoverAll();

    final transport = TransportOrchestrator(
      maxThreads: _appSettings.maxThreads,
      maxErrors: _appSettings.maxErrors,
    );
    final engine = SyncEngine(archiveStore: store, transport: transport);

    state = state.copyWith(message: 'Scanning...');

    final allIgnore = [..._appSettings.ignorePatterns, ...prefs.ignore.value];
    final ignoreFilter = allIgnore.isNotEmpty
        ? IgnoreFilter(ignorePatterns: allIgnore)
        : null;

    final updateConfig = UpdateConfig(
      useFastCheck: _appSettings.fastCheck,
      fatTolerance: _appSettings.fatFilesystem,
      shouldIgnore: ignoreFilter != null
          ? (p) => ignoreFilter.shouldIgnore(p)
          : null,
    );

    final reconConfig = ReconConfig(
      preferNewer: _appSettings.preferNewer,
      noDeletion: _appSettings.noDeletion,
      noUpdate: _appSettings.noUpdate,
      noCreation: _appSettings.noCreation,
    );

    final result = engine.sync(
      root1,
      root2,
      updateConfig: updateConfig,
      reconConfig: reconConfig,
      onProgress: (phase, msg) {
        final appPhase = switch (phase) {
          SyncPhase.scanning => AppSyncPhase.scanning,
          SyncPhase.reconciling => AppSyncPhase.reconciling,
          SyncPhase.propagating => AppSyncPhase.propagating,
          SyncPhase.updatingArchive => AppSyncPhase.propagating,
          SyncPhase.done => AppSyncPhase.done,
        };
        state = state.copyWith(phase: appPhase, message: msg);
      },
    );

    state = state.copyWith(
      phase: AppSyncPhase.done,
      message: 'Sync complete: ${result.propagated} propagated, '
          '${result.skipped} skipped, ${result.failed} failed',
      reconItems: result.reconItems,
      result: result,
    );
  }

  void reset() {
    state = const SyncOperationState();
  }
}
