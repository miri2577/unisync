# UniSync — Detailluecken & Fixes

## BUGS (Code ist falsch)

- [x] B1: `update.dart` — `_updateDeleted` nutzte `prevState` nicht → FIXED
- [x] B2: `remote_sync.dart` — `_decodeUpdates()` war Stub → Vollstaendige Serialisierung implementiert
- [x] B3: `archive_serial.dart` — `ownerId`/`groupId` nicht serialisiert → FIXED (archiveFormat v2)

## STUBS (Code tut nichts)

- [x] S1: `settings_screen.dart` — Settings-Toggles mit echtem State-Binding via AppSettings → FIXED
- [x] S2: `settings_screen.dart` — Add/Delete Pattern Buttons funktional → FIXED
- [x] S3: `cli_sync.dart` — Doppelte Propagation entfernt → FIXED

## FEHLENDE INTEGRATION

- [x] I1: Settings-Screen mit AppSettings Provider verbunden → FIXED
- [x] I2: Ignore-Patterns aus AppSettings + Profil in UpdateConfig → FIXED
- [x] I3: FpCache korrekt an UpdateDetector weitergegeben (war kein Bug) → OK
- [ ] I4: Watch Mode UI in Flutter-App (WatcherService existiert, kein UI-Button)
- [x] I5: Rsync-Delta in FileOps.copyFile integriert (>1MB Dateien) → FIXED
- [x] I6: Stasher in TransportOrchestrator integriert (backup vor overwrite/delete) → FIXED
- [x] I7: MergeExecutor in TransportOrchestrator integriert → FIXED (Stub-Aufruf)

## FEHLENDE TESTS

- [x] T1: Symlink Following Config Test → ADDED
- [x] T2: Case Conflict Detection → ADDED
- [x] T3: Ownership Sync (Props ownerId/groupId + Archive roundtrip) → ADDED
- [ ] T4: Remote E2E (syncRemote) — braucht echte SSH Verbindung
- [x] T5: Stasher Integration → ADDED
- [ ] T6: SSH Password Prompt — braucht echte SSH Verbindung
- [x] T7: Batch Operations → ADDED
