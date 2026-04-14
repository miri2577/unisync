# UniSync

**Bidirectional file synchronizer** — a pure Dart/Flutter reimplementation inspired by [Unison](https://github.com/bcpierce00/unison).

UniSync keeps two directories (local or remote) in sync by detecting changes on both sides, resolving conflicts, and propagating updates bidirectionally. Unlike simple backup tools, it handles modifications on *both* replicas intelligently.

## Features

- **Bidirectional sync** — changes on either side are detected and propagated
- **Conflict detection** — files modified on both sides are flagged for resolution
- **Smart change detection** — MD5 fingerprinting with fast-check optimization (mtime + size)
- **Rsync delta transfer** — only changed blocks are transferred for large files
- **Profile system** — `.prf` configuration files with 45+ preferences
- **Ignore patterns** — glob, path, and regex-based filtering (`Name *.tmp`, `Path .git`)
- **Crash-safe archives** — two-phase commit with automatic recovery
- **Concurrent transfers** — configurable parallel file operations (default: 20 threads)
- **Filesystem watching** — automatic re-sync on file changes (`repeat = watch`)
- **Batch operations** — bulk direction changes (all right, skip conflicts, etc.)
- **Remote sync** — SSH-based RPC protocol with streaming file transfer
- **Backup system** — automatic backups before overwrite with versioning
- **External merge** — integration with 3-way merge tools
- **Desktop UI** — native Windows look via Fluent UI, with profile management and sync visualization

## Screenshots

*Coming soon*

## Architecture

```
packages/
  unison_core/       # Pure Dart sync engine (no Flutter dependency)
    lib/src/
      model/         # Data types: Archive, Props, Fingerprint, Path, etc.
      engine/        # Update detection, reconciliation, transport, sync
      transfer/      # Rsync delta algorithm
      archive/       # Persistent archive storage with crash recovery
      filter/        # Ignore patterns (glob/path/regex)
      profile/       # Preferences and .prf file parser
      remote/        # SSH connection, RPC protocol, streaming
      backup/        # File backup and versioning
      fs/            # OS abstraction, filesystem watching
      util/          # Logging, binary serialization, transfer stats
app/                 # Flutter desktop application
  lib/
    screens/         # Profile list, sync view, settings
    widgets/         # Recon item tiles, direction indicators
    state/           # Riverpod state management
```

## Building

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.11+)
- Desktop development tools (Visual Studio for Windows, Xcode for macOS)

### Build

```bash
# Get dependencies
cd packages/unison_core && dart pub get
cd ../../app && flutter pub get

# Run tests (326 tests)
cd ../packages/unison_core && dart test

# Build desktop app
cd ../../app
flutter build windows    # Windows
flutter build macos      # macOS
flutter build linux      # Linux
```

### Run

```bash
cd app && flutter run -d windows
```

## Usage

1. Launch UniSync
2. Click **"New Profile"** to create a sync profile
3. Enter a name and two directory paths (roots)
4. Click **"Sync"** to start synchronization
5. Review changes — click direction arrows to override
6. Use batch buttons (All →, Skip Conflicts, etc.) for bulk operations

### Profile files

Profiles are stored as `.prf` files in `~/.unison/` (or `%USERPROFILE%\.unison\` on Windows):

```ini
# my-sync.prf
root = C:\Users\me\Documents
root = D:\Backup\Documents
ignore = Name {*.tmp,*.bak,.DS_Store}
ignore = Path node_modules
fastcheck = true
times = true
```

## Sync Algorithm

UniSync follows a 3-phase synchronization model:

1. **Update Detection** — scans both replicas against a stored archive of the last synchronized state
2. **Reconciliation** — compares changes from both sides, detects conflicts, computes sync directions
3. **Propagation** — executes file operations (copy, delete, set properties) with atomic writes

## Credits

This project is a clean-room reimplementation inspired by:

- **[Unison File Synchronizer](https://github.com/bcpierce00/unison)** by Benjamin C. Pierce et al.
- The rsync algorithm by Andrew Tridgell

UniSync does not share any source code with the original OCaml Unison implementation. The sync algorithms were reimplemented from published documentation and specifications.

## License

GPLv3 — see [LICENSE](LICENSE)

## Stats

| Metric | Value |
|--------|-------|
| Source files | 50 |
| Test files | 31 |
| Tests | 326 |
| Lines of code | ~10,000 |
| Language | Dart / Flutter |
| Platforms | Windows, macOS, Linux |
