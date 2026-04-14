/// Global state and standard preferences.
///
/// Mirrors OCaml Unison's `globals.ml`. Registers all standard preferences
/// and provides access to global sync configuration.
library;

import 'prefs.dart';

/// All standard Unison preferences, registered in a [PrefsRegistry].
class UnisonPrefs {
  final PrefsRegistry registry;

  // -- Root & path --
  late final ListPref root;
  late final ListPref path;

  // -- Sync behavior --
  late final Pref<bool> batch;
  late final Pref<bool> auto_;
  late final Pref<bool> confirmBigDeletes;
  late final Pref<bool> fastCheck;
  late final Pref<String> repeat;
  late final Pref<int> retry;

  // -- Direction --
  late final Pref<String> force;
  late final Pref<String> prefer;
  late final Pref<bool> preferNewer;

  // -- Restrictions --
  late final Pref<bool> noDeletion;
  late final Pref<bool> noUpdate;
  late final Pref<bool> noCreation;
  late final Pref<int> maxSizeThreshold;

  // -- File handling --
  late final Pref<bool> times;
  late final Pref<int> perms;
  late final Pref<bool> dontChmod;
  late final Pref<bool> links;
  late final Pref<bool> xattrs;
  late final Pref<bool> acl;

  // -- Filter --
  late final ListPref ignore;
  late final ListPref ignoreNot;
  late final ListPref follow;
  late final ListPref atomic;

  // -- Backup --
  late final ListPref backup;
  late final ListPref backupNot;
  late final Pref<String> backupLocation;
  late final Pref<String> backupDir;
  late final Pref<String> backupPrefix;
  late final Pref<String> backupSuffix;
  late final Pref<int> maxBackups;
  late final Pref<bool> backupCurrent;

  // -- Merge --
  late final ListPref merge;
  late final Pref<bool> mergeBatch;
  late final Pref<bool> confirmMerge;

  // -- Remote --
  late final Pref<String> serverCmd;
  late final Pref<String> sshCmd;

  // -- WebDAV --
  late final Pref<String> webdavUrl;
  late final Pref<String> webdavUser;
  late final Pref<String> webdavPass;
  late final Pref<String> sshArgs;
  late final Pref<bool> addVersionNo;

  // -- UI --
  late final Pref<String> ui;
  late final Pref<int> height;
  late final Pref<String> label;
  late final Pref<String> key;
  late final Pref<bool> contactQuietly;
  late final Pref<bool> dumbTty;

  // -- FAT --
  late final Pref<bool> fatFilesystem;

  // -- Case --
  late final Pref<String> ignoreCase;

  UnisonPrefs() : registry = PrefsRegistry() {
    _registerAll();
  }

  void _registerAll() {
    // Root & path
    root = registry.createStringList(
      name: 'root',
      doc: 'Replica root directories (exactly 2 required)',
      category: PrefCategory.basic,
    );
    path = registry.createStringList(
      name: 'path',
      doc: 'Paths to synchronize (relative to roots)',
      category: PrefCategory.basic,
    );

    // Sync behavior
    batch = registry.createBool(
      name: 'batch',
      doc: 'Batch mode: do not ask for confirmation on non-conflicting changes',
      category: PrefCategory.basic,
    );
    auto_ = registry.createBool(
      name: 'auto',
      doc: 'Automatically accept default actions',
      category: PrefCategory.basic,
    );
    confirmBigDeletes = registry.createBool(
      name: 'confirmbigdeletes',
      doc: 'Request confirmation for whole-replica deletes',
      defaultValue: true,
      category: PrefCategory.sync,
    );
    fastCheck = registry.createBool(
      name: 'fastcheck',
      doc: 'Use file modification times for quick change detection',
      defaultValue: true,
      category: PrefCategory.sync,
    );
    repeat = registry.createString(
      name: 'repeat',
      doc: 'Continuous sync mode: watch, <seconds>, or empty',
      category: PrefCategory.sync,
    );
    retry = registry.createInt(
      name: 'retry',
      doc: 'Number of times to retry failed syncs',
      category: PrefCategory.sync,
    );

    // Direction
    force = registry.createString(
      name: 'force',
      doc: 'Force changes in one direction (path or replica root)',
      category: PrefCategory.sync,
    );
    prefer = registry.createString(
      name: 'prefer',
      doc: 'Prefer one side for conflict resolution',
      category: PrefCategory.sync,
    );
    preferNewer = registry.createBool(
      name: 'prefernewer',
      doc: 'Resolve conflicts by preferring the newer file',
      category: PrefCategory.sync,
    );

    // Restrictions
    noDeletion = registry.createBool(
      name: 'nodeletion',
      doc: 'Prevent deletions from being propagated',
      category: PrefCategory.sync,
    );
    noUpdate = registry.createBool(
      name: 'noupdate',
      doc: 'Prevent updates from being propagated',
      category: PrefCategory.sync,
    );
    noCreation = registry.createBool(
      name: 'nocreation',
      doc: 'Prevent new files from being propagated',
      category: PrefCategory.sync,
    );
    maxSizeThreshold = registry.createInt(
      name: 'maxsizethreshold',
      doc: 'Maximum file size (KB) to transfer',
      category: PrefCategory.sync,
    );

    // File handling
    times = registry.createBool(
      name: 'times',
      doc: 'Preserve modification times',
      defaultValue: true,
      category: PrefCategory.sync,
    );
    perms = registry.createInt(
      name: 'perms',
      doc: 'Permission synchronization level (-1=default)',
      defaultValue: -1,
      category: PrefCategory.sync,
    );
    dontChmod = registry.createBool(
      name: 'dontchmod',
      doc: 'Do not set permissions on target',
      category: PrefCategory.sync,
    );
    links = registry.createBool(
      name: 'links',
      doc: 'Enable symbolic link support',
      defaultValue: true,
      category: PrefCategory.sync,
    );
    xattrs = registry.createBool(
      name: 'xattrs',
      doc: 'Sync extended attributes',
      category: PrefCategory.advanced,
    );
    acl = registry.createBool(
      name: 'acl',
      doc: 'Sync access control lists',
      category: PrefCategory.advanced,
    );

    // Filter
    ignore = registry.createStringList(
      name: 'ignore',
      doc: 'Patterns for paths to ignore',
      category: PrefCategory.filter,
    );
    ignoreNot = registry.createStringList(
      name: 'ignorenot',
      doc: 'Exception patterns (override ignore)',
      category: PrefCategory.filter,
    );
    follow = registry.createStringList(
      name: 'follow',
      doc: 'Symlinks to follow transparently',
      category: PrefCategory.filter,
    );
    atomic = registry.createStringList(
      name: 'atomic',
      doc: 'Directories to treat as atomic units',
      category: PrefCategory.filter,
    );

    // Backup
    backup = registry.createStringList(
      name: 'backup',
      doc: 'Patterns for paths to backup',
      category: PrefCategory.backup,
    );
    backupNot = registry.createStringList(
      name: 'backupnot',
      doc: 'Patterns excluded from backup',
      category: PrefCategory.backup,
    );
    backupLocation = registry.createString(
      name: 'backuplocation',
      doc: 'Backup storage: central or local',
      defaultValue: 'central',
      category: PrefCategory.backup,
    );
    backupDir = registry.createString(
      name: 'backupdir',
      doc: 'Directory for central backups',
      category: PrefCategory.backup,
    );
    backupPrefix = registry.createString(
      name: 'backupprefix',
      doc: 'Backup filename prefix',
      defaultValue: '.bak.',
      category: PrefCategory.backup,
    );
    backupSuffix = registry.createString(
      name: 'backupsuffix',
      doc: 'Backup filename suffix',
      category: PrefCategory.backup,
    );
    maxBackups = registry.createInt(
      name: 'maxbackups',
      doc: 'Maximum backup versions to keep',
      defaultValue: 2,
      category: PrefCategory.backup,
    );
    backupCurrent = registry.createBool(
      name: 'backupcurrent',
      doc: 'Backup the current version for merge support',
      category: PrefCategory.backup,
    );

    // Merge
    merge = registry.createStringList(
      name: 'merge',
      doc: 'External merge program (pathspec -> command)',
      category: PrefCategory.sync,
    );
    mergeBatch = registry.createBool(
      name: 'mergebatch',
      doc: 'Skip confirmation for merge results',
      category: PrefCategory.sync,
    );
    confirmMerge = registry.createBool(
      name: 'confirmmerge',
      doc: 'Confirm before committing merges',
      category: PrefCategory.sync,
    );

    // Remote
    serverCmd = registry.createString(
      name: 'servercmd',
      doc: 'Path to remote unison executable',
      category: PrefCategory.remote,
    );
    sshCmd = registry.createString(
      name: 'sshcmd',
      doc: 'SSH command',
      defaultValue: 'ssh',
      category: PrefCategory.remote,
    );
    sshArgs = registry.createString(
      name: 'sshargs',
      doc: 'Additional SSH arguments',
      category: PrefCategory.remote,
    );
    addVersionNo = registry.createBool(
      name: 'addversionno',
      doc: 'Append version number to remote command',
      category: PrefCategory.remote,
    );

    // WebDAV
    webdavUrl = registry.createString(
      name: 'webdavurl',
      doc: 'WebDAV server URL',
      category: PrefCategory.remote,
    );
    webdavUser = registry.createString(
      name: 'webdavuser',
      doc: 'WebDAV username',
      category: PrefCategory.remote,
    );
    webdavPass = registry.createString(
      name: 'webdavpass',
      doc: 'WebDAV password',
      category: PrefCategory.remote,
    );

    // UI
    ui = registry.createString(
      name: 'ui',
      doc: 'User interface: text or graphic',
      category: PrefCategory.ui,
    );
    height = registry.createInt(
      name: 'height',
      doc: 'Window height in lines',
      defaultValue: 15,
      category: PrefCategory.ui,
    );
    label = registry.createString(
      name: 'label',
      doc: 'Profile display name',
      category: PrefCategory.ui,
    );
    key = registry.createString(
      name: 'key',
      doc: 'Profile keyboard shortcut (0-9)',
      category: PrefCategory.ui,
    );
    contactQuietly = registry.createBool(
      name: 'contactquietly',
      doc: 'Suppress server contact message',
      category: PrefCategory.ui,
    );
    dumbTty = registry.createBool(
      name: 'dumbtty',
      doc: 'Dumb terminal mode (line-buffered)',
      category: PrefCategory.ui,
    );

    // FAT
    fatFilesystem = registry.createBool(
      name: 'fat',
      doc: 'FAT filesystem mode (no permissions, case-insensitive)',
      category: PrefCategory.advanced,
    );

    // Case
    ignoreCase = registry.createString(
      name: 'ignorecase',
      doc: 'Case handling: true, false, or default (auto-detect)',
      defaultValue: 'default',
      category: PrefCategory.advanced,
    );
  }

  /// Build a [ReconConfig] from the current preferences.
  /// (Imported type would create circular dep, so returns a map instead.)
  Map<String, dynamic> toReconConfigMap() {
    return {
      'force': force.isSet ? force.value : null,
      'prefer': prefer.isSet ? prefer.value : null,
      'preferNewer': preferNewer.value,
      'noDeletion': noDeletion.value,
      'noUpdate': noUpdate.value,
      'noCreation': noCreation.value,
    };
  }
}
