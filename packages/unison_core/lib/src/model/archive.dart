/// Archive — persistent record of the last synchronized state.
///
/// Mirrors OCaml Unison's archive type from `update.ml`.
/// Stored on disk per profile, loaded at sync start, updated after propagation.
library;

import 'dart:collection';

import 'fileinfo.dart';
import 'fingerprint.dart';
import 'name.dart';
import 'props.dart';

/// The archive format version. Increment when the serialization format changes.
const archiveFormat = 1;

/// Sorted map of child names to archives.
///
/// Uses [Name.compareTo] which respects the current [CaseMode].
typedef NameMap = SplayTreeMap<Name, Archive>;

/// Create an empty [NameMap].
NameMap emptyNameMap() => SplayTreeMap<Name, Archive>();

/// Snapshot of a filesystem tree as of the last sync.
///
/// Each node records the properties and content identity (fingerprint)
/// that both replicas agreed upon after the last successful sync.
sealed class Archive {
  const Archive();
}

/// A directory in the archive.
class ArchiveDir extends Archive {
  final Props desc;
  final NameMap children;

  ArchiveDir(this.desc, this.children);

  /// Empty directory archive.
  factory ArchiveDir.empty(Props desc) => ArchiveDir(desc, emptyNameMap());
}

/// A file in the archive.
class ArchiveFile extends Archive {
  final Props desc;
  final FullFingerprint fingerprint;
  final Stamp stamp;
  final RessStamp ressStamp;

  const ArchiveFile(this.desc, this.fingerprint, this.stamp, this.ressStamp);
}

/// A symbolic link in the archive.
class ArchiveSymlink extends Archive {
  final String target;

  const ArchiveSymlink(this.target);
}

/// No archive entry — path was never synced or was deleted.
class NoArchive extends Archive {
  const NoArchive();
}
