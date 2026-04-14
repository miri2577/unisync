/// Core sync engine for Unison file synchronizer.
///
/// Pure Dart implementation — no Flutter dependency.
library;

// Models
export 'src/model/archive.dart';
export 'src/model/common.dart';
export 'src/model/fileinfo.dart';
export 'src/model/fingerprint.dart';
export 'src/model/fspath.dart';
export 'src/model/name.dart';
export 'src/model/props.dart';
export 'src/model/recon_item.dart';
export 'src/model/sync_path.dart';
export 'src/model/tree.dart';
export 'src/model/update_item.dart';

// Filesystem
export 'src/fs/case.dart';
export 'src/fs/fileinfo_service.dart';
export 'src/fs/os.dart';
export 'src/fs/platform_ext.dart';
export 'src/fs/watcher.dart';

// Fingerprinting
export 'src/fingerprint/fingerprint_service.dart';
export 'src/fingerprint/fpcache.dart';

// Archive
export 'src/archive/archive_serial.dart';
export 'src/archive/archive_store.dart';

// Backup
export 'src/backup/stasher.dart';

// Engine
export 'src/engine/batch_ops.dart';
export 'src/engine/files.dart';
export 'src/engine/merge.dart';
export 'src/engine/recon.dart';
export 'src/engine/sync_engine.dart';
export 'src/engine/transport.dart';
export 'src/engine/update.dart';

// Remote
export 'src/remote/connection.dart';
export 'src/remote/protocol.dart';
export 'src/remote/remote_sync.dart';

// Filter
export 'src/filter/glob.dart';
export 'src/filter/ignore.dart';
export 'src/filter/pred.dart';

// Profile
export 'src/profile/globals.dart';
export 'src/profile/prefs.dart';
export 'src/profile/profile_parser.dart';

// Transfer
export 'src/transfer/checksum.dart';
export 'src/transfer/rsync.dart';

// Utilities
export 'src/util/marshal.dart';
export 'src/util/stats.dart';
export 'src/util/trace.dart';
