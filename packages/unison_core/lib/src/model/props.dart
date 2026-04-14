/// File properties (metadata) tracked during synchronization.
///
/// Mirrors OCaml Unison's `props.ml`. Tracks permissions, modification time,
/// file size, and optionally extended attributes/ACLs.
library;

/// File properties for synchronization comparison.
///
/// Immutable value object. [similar] handles platform-specific tolerance
/// (e.g. 2-second FAT granularity for modification times).
class Props {
  /// Unix permission bits, masked by the sync permission mask.
  /// On Windows this is simplified (read-only flag mapped to 0o444 vs 0o666).
  final int permissions;

  /// Last modification time.
  final DateTime modTime;

  /// File size in bytes.
  final int length;

  /// Change time (ctime). Used for fast-check optimization.
  /// Not synced, only used for local change detection.
  final DateTime? ctime;

  const Props({
    required this.permissions,
    required this.modTime,
    required this.length,
    this.ctime,
  });

  /// Dummy props for absent/unknown entries.
  static final absent = Props(
    permissions: 0,
    modTime: DateTime.fromMillisecondsSinceEpoch(0),
    length: 0,
  );

  /// Default directory permissions.
  static final dirDefault = Props(
    permissions: 0x1FF, // 0o777
    modTime: DateTime.fromMillisecondsSinceEpoch(0),
    length: 0,
  );

  /// Whether two property sets are "similar enough" to not require syncing.
  ///
  /// - Permissions: compared after masking (ignores bits outside sync mask)
  /// - Modification time: tolerates up to 2-second difference for FAT
  /// - Length: must be exactly equal
  bool similar(Props other, {bool fatTolerance = false}) {
    if (length != other.length) return false;

    if (!_permissionsSimilar(other)) return false;

    if (!_timeSimilar(modTime, other.modTime, fatTolerance: fatTolerance)) {
      return false;
    }

    return true;
  }

  bool _permissionsSimilar(Props other) {
    // Compare masked permissions (ignore umask differences)
    return (permissions & _permMask) == (other.permissions & _permMask);
  }

  /// Permission mask — by default sync all permission bits.
  /// Can be narrowed via preferences.
  static int _permMask = 0x1FF; // 0o777

  /// Set the global permission mask.
  static set permMask(int mask) => _permMask = mask;

  static bool _timeSimilar(
    DateTime a,
    DateTime b, {
    bool fatTolerance = false,
  }) {
    final diff = a.difference(b).inSeconds.abs();
    if (diff == 0) return true;
    // FAT filesystems have 2-second granularity
    if (fatTolerance && diff <= 2) return true;
    return false;
  }

  /// Create new props by overriding specific fields from [source],
  /// keeping platform-appropriate values from [this] where [source]
  /// doesn't apply.
  Props override_({
    int? permissions,
    DateTime? modTime,
    int? length,
  }) {
    return Props(
      permissions: permissions ?? this.permissions,
      modTime: modTime ?? this.modTime,
      length: length ?? this.length,
      ctime: ctime,
    );
  }

  /// Create a copy with specific fields changed.
  Props copyWith({
    int? permissions,
    DateTime? modTime,
    int? length,
    DateTime? ctime,
  }) {
    return Props(
      permissions: permissions ?? this.permissions,
      modTime: modTime ?? this.modTime,
      length: length ?? this.length,
      ctime: ctime ?? this.ctime,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Props &&
      permissions == other.permissions &&
      modTime == other.modTime &&
      length == other.length;

  @override
  int get hashCode => Object.hash(permissions, modTime, length);

  @override
  String toString() =>
      'Props(perm=${permissions.toRadixString(8)}, '
      'mod=$modTime, len=$length)';
}
