# UniSync

**Bidirectional File Synchronizer | Bidirektionaler Datei-Synchronisierer**

A pure Dart/Flutter desktop application for keeping two directories perfectly in sync — inspired by [Unison](https://github.com/bcpierce00/unison).

Eine reine Dart/Flutter Desktop-Anwendung, die zwei Verzeichnisse perfekt synchron hält — inspiriert von [Unison](https://github.com/bcpierce00/unison).

---

## English

### What is UniSync?

UniSync is a **bidirectional file synchronizer** for Windows, macOS, and Linux. Unlike simple backup or mirroring tools that only copy in one direction, UniSync intelligently detects and propagates changes on **both sides**. If you edit a file on your laptop and a different file on your desktop, UniSync will transfer both changes so both machines end up identical.

### Why UniSync?

| Problem | UniSync Solution |
|---------|-----------------|
| You edit files on multiple machines | Bidirectional sync keeps all copies up-to-date |
| Cloud sync corrupts or conflicts silently | Explicit conflict detection — you decide what happens |
| Large files waste bandwidth on every sync | Rsync delta algorithm transfers only changed blocks |
| Sync tools don't tell you what changed | Visual UI shows every change with color-coded direction arrows |
| One crash and your sync state is lost | Two-phase commit archives with automatic crash recovery |

### How Does It Work?

UniSync uses a **3-phase synchronization algorithm**:

**Phase 1 — Update Detection**
Both directories are scanned and compared against an archive (a snapshot of the last synchronized state). UniSync identifies exactly what changed: new files, modified content, deleted files, permission changes, and more. A fast-check optimization using file modification times and sizes avoids reading unchanged files entirely.

**Phase 2 — Reconciliation**
Changes from both sides are compared. If only one side changed a file, the change is propagated automatically. If both sides changed the same file differently, it's flagged as a **conflict** for the user to resolve. If both sides made the same change, it's silently marked as equal.

**Phase 3 — Propagation**
The computed actions are executed: files are copied, deleted, or have their properties updated. All writes use atomic temp-file-and-rename to prevent corruption. Up to 20 file transfers run in parallel for maximum speed.

### Features

- **Bidirectional sync** — changes on either side are detected and propagated
- **Conflict detection & resolution** — files modified on both sides are flagged; resolve per-file or in batch
- **Smart change detection** — MD5 content fingerprinting with fast-check optimization (mtime + file size)
- **Rsync delta transfer** — for large files, only changed blocks are transferred using a rolling checksum algorithm
- **Profile system** — save sync configurations as `.prf` files with 45+ preferences
- **Ignore patterns** — flexible filtering with glob (`Name *.tmp`), path (`Path .git`), and regex patterns
- **Crash-safe archives** — two-phase commit protocol with automatic recovery after power loss or crashes
- **Concurrent transfers** — configurable parallel file operations (default: 20 simultaneous transfers)
- **Filesystem watching** — automatic re-sync when files change (`repeat = watch` mode)
- **Batch operations** — bulk direction changes: "all right", "skip conflicts", "revert all", etc.
- **Remote sync** — SSH-based RPC protocol with streaming file transfer and zlib compression
- **Backup system** — automatic versioned backups before overwriting files
- **External merge** — integration with 3-way merge tools for conflict resolution
- **Desktop UI** — native Windows look (Fluent UI), macOS, and Linux support
- **Error recovery** — configurable error tolerance; sync continues past individual file failures
- **Path-specific rules** — different sync strategies for different subdirectories

### Usage — Desktop App (GUI)

1. Launch UniSync
2. Click **"New Profile"** to create a sync configuration
3. Enter a name and two directory paths (your two replicas)
4. Click **"Sync"** to start synchronization
5. Review the change list — each item shows what changed and in which direction
6. Click direction arrows to override individual items, or use batch buttons for bulk operations
7. Changes are propagated and the archive is updated for next time

### Usage — Command Line (CLI)

UniSync also includes a standalone CLI for headless/server environments:

```bash
# Sync two directories directly
unisync C:\Docs D:\Backup

# Sync using a saved profile
unisync my-documents

# Batch mode — no prompts, skip conflicts
unisync --batch my-documents

# Watch mode — continuous sync on file changes
unisync --watch my-documents

# Repeat mode — sync every 60 seconds
unisync --repeat 60 my-documents

# List available profiles
unisync --list

# Run as remote server
unisync --server /data/sync

# With options
unisync --maxthreads 50 --ignore "Name *.tmp" --prefer newer C:\A D:\B
```

**Interactive commands** during sync review:

| Key | Action |
|-----|--------|
| `>` `.` | Set direction: replica 1 to 2 |
| `<` `,` | Set direction: replica 2 to 1 |
| `/` | Skip this item |
| `m` | Mark for merge |
| `d` | Show item details |
| `A` | Accept all defaults |
| `1` | Set all to replica 1 → 2 |
| `2` | Set all to replica 2 → 1 |
| `C` | Skip all conflicts |
| `R` | Revert all to defaults |
| `g` | Go — execute propagation |
| `q` | Quit without syncing |

**Build the CLI binary:**

```bash
cd cli
dart compile exe bin/unisync.dart -o unisync.exe
```

### Profile Configuration

Profiles are stored as `.prf` files in `~/.unison/` (or `%USERPROFILE%\.unison\` on Windows):

```ini
# work-sync.prf
root = C:\Users\me\Documents\Work
root = D:\Backup\Work

# Ignore temporary and build files
ignore = Name {*.tmp,*.bak,*.log}
ignore = Name .DS_Store
ignore = Path {node_modules,.git,build}

# Sync settings
fastcheck = true       # Use file timestamps for quick change detection
times = true           # Preserve modification times
batch = false          # Ask before syncing (set true for unattended)
confirmbigdeletes = true

# Conflict handling
prefernewer = false    # Don't auto-resolve; let me decide
```

### Architecture

UniSync is split into two packages:

```
packages/unison_core/    Pure Dart library — the complete sync engine
                         No Flutter dependency, can be used standalone
  model/                 Core data types (Archive, Props, Fingerprint, Path...)
  engine/                Sync phases (Update, Reconciliation, Transport)
  transfer/              Rsync delta algorithm (rolling checksum + block matching)
  archive/               Persistent storage with crash-safe two-phase commit
  filter/                Ignore patterns (glob, path, regex)
  profile/               Preference system and .prf file parser
  remote/                SSH connection, RPC protocol, streaming transfers
  backup/                Versioned file backups
  fs/                    OS abstraction, filesystem watching
  util/                  Logging, binary serialization, transfer statistics

app/                     Flutter desktop application
  screens/               Profile list, sync view, settings
  widgets/               Recon item tiles, direction indicators
  state/                 Riverpod state management
cli/                     Command-line interface (standalone native binary)
  bin/unisync.dart         Entry point with argument parsing
  lib/cli_sync.dart        Sync orchestration (batch, watch, repeat, server)
  lib/cli_ui.dart          Interactive TUI with ANSI colors
```

### Building from Source

**Prerequisites:**
- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.11 or later
- Desktop development tools (Visual Studio for Windows, Xcode for macOS, standard build tools for Linux)

```bash
# Clone
git clone https://github.com/miri2577/unisync.git
cd unisync

# Install dependencies
cd packages/unison_core && dart pub get
cd ../../app && flutter pub get

# Run tests (326 tests)
cd ../packages/unison_core && dart test

# Build
cd ../../app
flutter build windows    # Windows (.exe)
flutter build macos      # macOS (.app)
flutter build linux      # Linux
```

### Technical Details

| Component | Implementation |
|-----------|---------------|
| Change detection | MD5 fingerprinting + mtime/size fast-check + inode stamps |
| Delta transfer | Rsync algorithm: rolling checksum (base 16381) + MD5 strong hash |
| Archive format | Custom binary serialization with LEB128 integer encoding |
| Crash safety | 3-phase commit protocol (write temp → backup old → atomic rename) |
| Concurrency | Dart isolate pool with configurable parallelism (1-100 threads) |
| Remote protocol | 5-byte framed messages with checksum, zlib compression, streaming |
| Pattern matching | Glob-to-regex compilation supporting `*`, `?`, `[a-z]`, `{a,b,c}` |
| UI framework | Fluent UI (Windows native) with Riverpod state management |

---

## Deutsch

### Was ist UniSync?

UniSync ist ein **bidirektionaler Datei-Synchronisierer** fuer Windows, macOS und Linux. Im Gegensatz zu einfachen Backup- oder Spiegelungs-Tools, die nur in eine Richtung kopieren, erkennt und uebertraegt UniSync Aenderungen auf **beiden Seiten** intelligent. Wenn du eine Datei auf deinem Laptop und eine andere auf deinem Desktop bearbeitest, uebertraegt UniSync beide Aenderungen, sodass beide Rechner am Ende identisch sind.

### Warum UniSync?

| Problem | UniSync-Loesung |
|---------|-----------------|
| Du bearbeitest Dateien auf mehreren Rechnern | Bidirektionaler Sync haelt alle Kopien aktuell |
| Cloud-Sync beschaedigt Dateien oder verschluckt Konflikte | Explizite Konflikterkennung — du entscheidest |
| Grosse Dateien verschwenden Bandbreite bei jedem Sync | Rsync-Delta-Algorithmus uebertraegt nur geaenderte Bloecke |
| Sync-Tools zeigen nicht, was sich geaendert hat | Visuelle UI zeigt jede Aenderung mit farbigen Richtungspfeilen |
| Ein Absturz und der Sync-Zustand ist weg | Zwei-Phasen-Commit-Archive mit automatischer Crash-Recovery |

### Wie funktioniert es?

UniSync verwendet einen **3-Phasen-Synchronisations-Algorithmus**:

**Phase 1 — Aenderungserkennung (Update Detection)**
Beide Verzeichnisse werden gescannt und mit einem Archiv verglichen (einem Snapshot des letzten synchronisierten Zustands). UniSync identifiziert genau, was sich geaendert hat: neue Dateien, geaenderte Inhalte, geloeschte Dateien, Berechtigungsaenderungen und mehr. Eine Fast-Check-Optimierung anhand von Dateiaenderungszeiten und -groessen vermeidet das Lesen unveraenderter Dateien komplett.

**Phase 2 — Abgleich (Reconciliation)**
Aenderungen beider Seiten werden verglichen. Wenn nur eine Seite eine Datei geaendert hat, wird die Aenderung automatisch uebertragen. Wenn beide Seiten dieselbe Datei unterschiedlich geaendert haben, wird sie als **Konflikt** markiert, den der Benutzer loesen muss. Wenn beide Seiten die gleiche Aenderung vorgenommen haben, wird sie stillschweigend als identisch markiert.

**Phase 3 — Ausfuehrung (Propagation)**
Die berechneten Aktionen werden ausgefuehrt: Dateien werden kopiert, geloescht oder ihre Eigenschaften aktualisiert. Alle Schreibvorgaenge verwenden atomares Temp-Datei-und-Umbenennen, um Korruption zu verhindern. Bis zu 20 Dateitransfers laufen parallel fuer maximale Geschwindigkeit.

### Funktionen

- **Bidirektionaler Sync** — Aenderungen auf beiden Seiten werden erkannt und uebertragen
- **Konflikterkennung & -loesung** — unterschiedlich geaenderte Dateien werden markiert; Loesung pro Datei oder im Batch
- **Intelligente Aenderungserkennung** — MD5-Fingerprinting mit Fast-Check-Optimierung (mtime + Dateigroesse)
- **Rsync-Delta-Transfer** — bei grossen Dateien werden nur geaenderte Bloecke uebertragen
- **Profil-System** — Sync-Konfigurationen als `.prf`-Dateien mit 45+ Einstellungen
- **Ignore-Patterns** — flexibles Filtern mit Glob (`Name *.tmp`), Pfad (`Path .git`) und Regex
- **Crash-sichere Archive** — Zwei-Phasen-Commit mit automatischer Wiederherstellung nach Absturz
- **Parallele Transfers** — konfigurierbare gleichzeitige Dateioperationen (Standard: 20)
- **Dateisystem-Ueberwachung** — automatischer Re-Sync bei Dateiänderungen (`repeat = watch`)
- **Batch-Operationen** — Massen-Richtungsaenderungen: "Alle rechts", "Konflikte ueberspringen", etc.
- **Remote-Sync** — SSH-basiertes RPC-Protokoll mit Streaming und zlib-Kompression
- **Backup-System** — automatische versionierte Sicherungen vor dem Ueberschreiben
- **Externer Merge** — Integration mit 3-Wege-Merge-Tools zur Konfliktloesung
- **Desktop-UI** — natives Windows-Aussehen (Fluent UI), macOS- und Linux-Unterstuetzung
- **Fehlertoleranz** — konfigurierbare Fehlergrenze; Sync laeuft bei einzelnen Dateifehlern weiter
- **Pfad-spezifische Regeln** — verschiedene Sync-Strategien fuer verschiedene Unterverzeichnisse

### Benutzung — Desktop App (GUI)

1. UniSync starten
2. **"New Profile"** klicken, um ein Sync-Profil zu erstellen
3. Name und zwei Verzeichnispfade eingeben (die beiden Replicas)
4. **"Sync"** klicken, um die Synchronisation zu starten
5. Aenderungsliste pruefen — jedes Element zeigt, was sich geaendert hat und in welche Richtung
6. Richtungspfeile klicken fuer einzelne Aenderungen, oder Batch-Buttons fuer Massenoperationen
7. Aenderungen werden ausgefuehrt und das Archiv fuer den naechsten Sync aktualisiert

### Benutzung — Kommandozeile (CLI)

UniSync bietet auch ein eigenstaendiges CLI fuer Server/Headless-Umgebungen:

```bash
# Zwei Verzeichnisse direkt synchronisieren
unisync C:\Docs D:\Backup

# Mit gespeichertem Profil synchronisieren
unisync mein-profil

# Batch-Modus — keine Rueckfragen, Konflikte ueberspringen
unisync --batch mein-profil

# Watch-Modus — automatischer Sync bei Dateiänderungen
unisync --watch mein-profil

# Repeat-Modus — alle 60 Sekunden synchronisieren
unisync --repeat 60 mein-profil

# Profile auflisten
unisync --list

# Als Remote-Server starten
unisync --server /data/sync
```

**Interaktive Befehle** waehrend der Sync-Pruefung:

| Taste | Aktion |
|-------|--------|
| `>` `.` | Richtung: Replica 1 nach 2 |
| `<` `,` | Richtung: Replica 2 nach 1 |
| `/` | Element ueberspringen |
| `m` | Zum Merge markieren |
| `d` | Details anzeigen |
| `A` | Alle Standardaktionen akzeptieren |
| `1` | Alle nach Replica 2 |
| `2` | Alle nach Replica 1 |
| `C` | Alle Konflikte ueberspringen |
| `R` | Alle zuruecksetzen |
| `g` | Ausfuehren — Sync starten |
| `q` | Beenden ohne Sync |

**CLI-Binary kompilieren:**

```bash
cd cli
dart compile exe bin/unisync.dart -o unisync.exe
```

### Profil-Konfiguration

Profile werden als `.prf`-Dateien in `~/.unison/` (oder `%USERPROFILE%\.unison\` unter Windows) gespeichert:

```ini
# arbeit-sync.prf
root = C:\Users\ich\Dokumente\Arbeit
root = D:\Backup\Arbeit

# Temporaere und Build-Dateien ignorieren
ignore = Name {*.tmp,*.bak,*.log}
ignore = Name .DS_Store
ignore = Path {node_modules,.git,build}

# Sync-Einstellungen
fastcheck = true       # Dateizeitstempel fuer schnelle Erkennung nutzen
times = true           # Aenderungszeiten beibehalten
batch = false          # Vor dem Sync fragen (true fuer unbeaufsichtigt)
confirmbigdeletes = true

# Konfliktbehandlung
prefernewer = false    # Nicht automatisch loesen; mich entscheiden lassen
```

### Technische Details

| Komponente | Implementierung |
|------------|----------------|
| Aenderungserkennung | MD5-Fingerprinting + mtime/size Fast-Check + Inode-Stamps |
| Delta-Transfer | Rsync-Algorithmus: Rolling Checksum (Basis 16381) + MD5 Strong Hash |
| Archiv-Format | Eigene binaere Serialisierung mit LEB128-Integer-Kodierung |
| Crash-Sicherheit | 3-Phasen-Commit (Temp schreiben → Altes sichern → Atomares Umbenennen) |
| Parallelitaet | Dart-Isolate-Pool mit konfigurierbarer Parallelitaet (1-100 Threads) |
| Remote-Protokoll | 5-Byte-gerahmte Nachrichten mit Pruefsumme, zlib-Kompression, Streaming |
| Pattern-Matching | Glob-zu-Regex-Kompilierung mit `*`, `?`, `[a-z]`, `{a,b,c}` |
| UI-Framework | Fluent UI (Windows-nativ) mit Riverpod State Management |

---

## Credits

This project is a **clean-room reimplementation** inspired by:

- **[Unison File Synchronizer](https://github.com/bcpierce00/unison)** by Benjamin C. Pierce et al.
- The rsync algorithm by Andrew Tridgell

UniSync does not share any source code with the original OCaml Unison implementation. The synchronization algorithms were reimplemented from published documentation and academic specifications.

Dieses Projekt ist eine **Clean-Room-Neuimplementierung**, inspiriert von:

- **[Unison File Synchronizer](https://github.com/bcpierce00/unison)** von Benjamin C. Pierce et al.
- Dem Rsync-Algorithmus von Andrew Tridgell

UniSync teilt keinen Quellcode mit der originalen OCaml-Unison-Implementierung. Die Synchronisations-Algorithmen wurden anhand veroeffentlichter Dokumentation und akademischer Spezifikationen neu implementiert.

## License / Lizenz

GPLv3 — see / siehe [LICENSE](LICENSE)

## Project Stats

| Metric / Metrik | Value / Wert |
|-----------------|-------------|
| Source files / Quelldateien | 53 |
| Test files / Testdateien | 31 |
| Tests | 326 |
| Lines of code / Codezeilen | ~11,000 |
| Language / Sprache | Dart / Flutter |
| Platforms / Plattformen | Windows, macOS, Linux |
