/// Update detection output types.
///
/// Mirrors OCaml Unison's `common.ml` updateItem/updateContent types.
/// Produced by the update detection phase (comparing filesystem vs archive).
library;

import 'fileinfo.dart';
import 'fingerprint.dart';
import 'name.dart';
import 'props.dart';

// ---------------------------------------------------------------------------
// Content change tracking
// ---------------------------------------------------------------------------

/// Whether file contents changed since last sync.
sealed class ContentsChange {
  const ContentsChange();
}

/// Content is identical to the archive.
class ContentsSame extends ContentsChange {
  const ContentsSame();
}

/// Content differs from the archive.
class ContentsUpdated extends ContentsChange {
  final FullFingerprint fingerprint;
  final Stamp stamp;
  final RessStamp ressStamp;

  const ContentsUpdated(this.fingerprint, this.stamp, this.ressStamp);
}

/// Whether directory/file properties changed.
enum PermChange { propsSame, propsUpdated }

// ---------------------------------------------------------------------------
// Previous state (what was in the archive before this scan)
// ---------------------------------------------------------------------------

/// What existed in the archive at this path before the update scan.
sealed class PrevState {
  const PrevState();
}

/// Previously a directory.
class PrevDir extends PrevState {
  final Props desc;
  const PrevDir(this.desc);
}

/// Previously a file.
class PrevFile extends PrevState {
  final Props desc;
  final FullFingerprint fingerprint;
  final Stamp stamp;
  final RessStamp ressStamp;

  const PrevFile(this.desc, this.fingerprint, this.stamp, this.ressStamp);
}

/// Previously a symbolic link.
class PrevSymlink extends PrevState {
  const PrevSymlink();
}

/// Newly appeared (not in archive).
class NewEntry extends PrevState {
  const NewEntry();
}

// ---------------------------------------------------------------------------
// Update content — what currently exists on a replica
// ---------------------------------------------------------------------------

/// Description of what currently exists at a path on one replica.
sealed class UpdateContent {
  const UpdateContent();
}

/// The path no longer exists (was deleted).
class Absent extends UpdateContent {
  const Absent();
}

/// A regular file.
class FileContent extends UpdateContent {
  final Props desc;
  final ContentsChange contentsChange;

  const FileContent(this.desc, this.contentsChange);
}

/// A directory with its children's update items.
class DirContent extends UpdateContent {
  final Props desc;

  /// Children sorted by [Name], only including those with actual updates
  /// (non-trivial entries).
  final List<(Name, UpdateItem)> children;

  final PermChange permChange;

  /// Whether the directory was emptied (all children deleted).
  final bool isEmpty;

  const DirContent(this.desc, this.children, this.permChange, this.isEmpty);
}

/// A symbolic link.
class SymlinkContent extends UpdateContent {
  final String target;

  const SymlinkContent(this.target);
}

// ---------------------------------------------------------------------------
// Update item — the result of scanning one path on one replica
// ---------------------------------------------------------------------------

/// Result of comparing one path's current state against the archive.
sealed class UpdateItem {
  const UpdateItem();
}

/// No changes detected at this path.
class NoUpdates extends UpdateItem {
  const NoUpdates();
}

/// Changes detected — [content] is the current state, [prevState] is
/// what was in the archive.
class Updates extends UpdateItem {
  final UpdateContent content;
  final PrevState prevState;

  const Updates(this.content, this.prevState);
}

/// Error scanning this path (e.g. permission denied).
class UpdateError extends UpdateItem {
  final String message;

  const UpdateError(this.message);
}
