/// Filesystem entry information (stat result).
///
/// Mirrors OCaml Unison's `fileinfo.ml`.
library;

import 'props.dart';

/// Type of a filesystem entry.
enum FileType {
  absent,
  file,
  directory,
  symlink,
}

/// Inode stamp for fast change detection.
///
/// On platforms with reliable inodes (Linux, macOS), [InodeStamp] enables
/// quick detection of file replacement. On Windows, [NoStamp] is used
/// since NTFS file IDs behave differently.
sealed class Stamp {
  const Stamp();
}

/// Inode number from filesystem stat.
class InodeStamp extends Stamp {
  final int inode;
  const InodeStamp(this.inode);

  @override
  bool operator ==(Object other) =>
      other is InodeStamp && inode == other.inode;

  @override
  int get hashCode => inode.hashCode;

  @override
  String toString() => 'Inode($inode)';
}

/// No inode information available (Windows, or disabled by preference).
class NoStamp extends Stamp {
  const NoStamp();

  @override
  bool operator ==(Object other) => other is NoStamp;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'NoStamp';
}

/// File needs to be re-scanned (e.g. after failed transfer).
class RescanStamp extends Stamp {
  const RescanStamp();

  @override
  bool operator ==(Object other) => other is RescanStamp;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'Rescan';
}

/// macOS resource fork stamp.
class RessStamp {
  final int value;
  const RessStamp(this.value);
  static const zero = RessStamp(0);

  @override
  bool operator ==(Object other) =>
      other is RessStamp && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Information about a filesystem entry, as returned by stat.
class Fileinfo {
  final FileType typ;
  final int inode;
  final Props desc;
  final Stamp stamp;

  const Fileinfo({
    required this.typ,
    required this.inode,
    required this.desc,
    required this.stamp,
  });

  /// Info for an absent (non-existent) entry.
  static final absent = Fileinfo(
    typ: FileType.absent,
    inode: 0,
    desc: Props.absent,
    stamp: const NoStamp(),
  );

  /// Check whether a file appears unchanged based on its stamp and props.
  ///
  /// Conservative: returns `true` only when we can be sure nothing changed.
  /// Used by the fast-check optimization to skip fingerprint computation.
  bool unchanged(Fileinfo archived, {bool useFastCheck = true}) {
    if (!useFastCheck) return false;
    if (typ != archived.typ) return false;

    // Stamp comparison
    final stampMatch = switch ((stamp, archived.stamp)) {
      (InodeStamp(inode: var a), InodeStamp(inode: var b)) => a == b,
      (NoStamp(), NoStamp()) => true,
      _ => false,
    };
    if (!stampMatch) return false;

    // Props comparison (mtime + size)
    if (desc.length != archived.desc.length) return false;
    if (desc.modTime != archived.desc.modTime) return false;

    return true;
  }

  @override
  String toString() => 'Fileinfo($typ, $desc)';
}
