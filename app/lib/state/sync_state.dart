import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unison_core/unison_core.dart';

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

  const SyncOperationState({
    this.phase = AppSyncPhase.idle,
    this.message = '',
    this.reconItems = const [],
    this.result,
    this.error,
  });

  SyncOperationState copyWith({
    AppSyncPhase? phase,
    String? message,
    List<ReconItem>? reconItems,
    SyncResult? result,
    String? error,
  }) {
    return SyncOperationState(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      reconItems: reconItems ?? this.reconItems,
      result: result ?? this.result,
      error: error ?? this.error,
    );
  }
}

/// Provider for the active sync operation.
final syncOperationProvider =
    StateNotifierProvider<SyncOperationNotifier, SyncOperationState>((ref) {
  return SyncOperationNotifier(ref.watch(profileDirProvider));
});

class SyncOperationNotifier extends StateNotifier<SyncOperationState> {
  final String _profileDir;

  SyncOperationNotifier(this._profileDir)
      : super(const SyncOperationState());

  /// Start a sync for a profile. Returns the recon items for UI review.
  void scan(String profileName) {
    state = state.copyWith(
      phase: AppSyncPhase.scanning,
      message: 'Loading profile...',
      reconItems: [],
      result: null,
      error: null,
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

      final root1 = Fspath.fromLocal(prefs.root.value[0]);
      final root2 = Fspath.fromLocal(prefs.root.value[1]);
      final store = ArchiveStore(_profileDir);
      final engine = SyncEngine(archiveStore: store);

      state = state.copyWith(message: 'Scanning...');

      final updateConfig = UpdateConfig(
        useFastCheck: prefs.fastCheck.value,
        fatTolerance: prefs.fatFilesystem.value,
      );

      final reconConfig = ReconConfig(
        preferNewer: prefs.preferNewer.value,
        noDeletion: prefs.noDeletion.value,
        noUpdate: prefs.noUpdate.value,
        noCreation: prefs.noCreation.value,
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
    } catch (e) {
      state = state.copyWith(
        phase: AppSyncPhase.error,
        error: '$e',
      );
    }
  }

  void reset() {
    state = const SyncOperationState();
  }
}
