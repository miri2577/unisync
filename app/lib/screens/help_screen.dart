import 'package:fluent_ui/fluent_ui.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      header: PageHeader(
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(
          children: [
            Icon(FluentIcons.help),
            SizedBox(width: 8),
            Text('Help'),
          ],
        ),
      ),
      content: Row(
        children: [
          SizedBox(
            width: 240,
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                _navTile(0, FluentIcons.lightbulb, 'Quickstart'),
                _navTile(1, FluentIcons.folder, 'General'),
                _navTile(2, FluentIcons.sync, 'Sync Settings'),
                _navTile(3, FluentIcons.filter, 'Filters'),
                _navTile(4, FluentIcons.cloud, 'Remote (SSH/WebDAV)'),
                _navTile(5, FluentIcons.history, 'Time Machine'),
                _navTile(6, FluentIcons.warning, 'Conflicts'),
                _navTile(7, FluentIcons.permissions, 'Security'),
                _navTile(8, FluentIcons.command_prompt, 'CLI'),
                _navTile(9, FluentIcons.bug, 'Troubleshooting'),
              ],
            ),
          ),
          Container(width: 1, color: theme.resources.dividerStrokeColorDefault),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: switch (_section) {
                0 => _quickstart(theme),
                1 => _general(theme),
                2 => _syncSettings(theme),
                3 => _filters(theme),
                4 => _remote(theme),
                5 => _timeMachine(theme),
                6 => _conflicts(theme),
                7 => _security(theme),
                8 => _cli(theme),
                9 => _troubleshooting(theme),
                _ => const SizedBox(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _navTile(int index, IconData icon, String label) {
    return ListTile.selectable(
      leading: Icon(icon, size: 16),
      title: Text(label),
      selected: _section == index,
      onPressed: () => setState(() => _section = index),
    );
  }

  Widget _h1(FluentThemeData t, String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 12),
          child: Text(text, style: t.typography.titleLarge));

  Widget _h2(FluentThemeData t, String text) =>
      Padding(padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(text, style: t.typography.subtitle));

  Widget _p(FluentThemeData t, String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text(text, style: t.typography.body));

  Widget _kv(FluentThemeData t, String key, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: RichText(text: TextSpan(
      style: t.typography.body,
      children: [
        TextSpan(text: '$key: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        TextSpan(text: value),
      ],
    )),
  );

  // -------- Sections --------

  Widget _quickstart(FluentThemeData t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _h1(t, 'Quickstart'),
      _p(t, 'UniSync keeps two folders in sync — locally on your machine '
            'or with a cloud / NAS via WebDAV.'),
      _h2(t, '1. Create a profile'),
      _p(t, 'Tab "Profiles" → "New Profile". Give it a name, pick the '
            'first folder, then choose the second target type (Local, SSH, WebDAV).'),
      _h2(t, '2. WebDAV: pick a provider'),
      _p(t, 'When choosing WebDAV, select your provider (Nextcloud, HiDrive, '
            'Synology, etc.). The URL template is filled in automatically — '
            'replace any USERNAME placeholder, then enter login + password.'),
      _h2(t, '3. Sync'),
      _p(t, 'Click "Sync" on a profile card. UniSync compares both sides, '
            'detects changes, and propagates them. Conflicts (changes on '
            'both sides) are skipped by default — you decide.'),
      _h2(t, '4. Watch (continuous sync)'),
      _p(t, 'Click "Watch" instead of "Sync" to monitor changes and sync '
            'them automatically as they happen.'),
      _h2(t, 'Where files end up on WebDAV'),
      _p(t, 'On WebDAV servers, files are stored under '
            'UniSync/<your-profile-name>/ — they don\'t pollute your '
            'cloud root.'),
    ],
  );

  Widget _general(FluentThemeData t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _h1(t, 'General Settings'),
      _kv(t, 'Profile Directory',
          'Where .prf profile files are stored. Default: ~/.unison/'),
      _kv(t, 'Max Concurrent Transfers',
          'How many files are uploaded/downloaded in parallel during '
          'propagation. Default: 20. Higher = faster, but uses more memory.'),
      _kv(t, 'Max Errors Before Abort',
          'How many file errors UniSync tolerates before stopping the sync. '
          '-1 = never abort, 0 = abort on first error, N = abort after N '
          'failures. Default: -1 (continue on errors).'),
    ],
  );

  Widget _syncSettings(FluentThemeData t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _h1(t, 'Sync Behavior'),
      _kv(t, 'Fast Check',
          'Skip MD5 fingerprint computation if file size + modification '
          'time are unchanged. Much faster on large unchanged files. '
          'Default: ON.'),
      _kv(t, 'Preserve Modification Times',
          'Copy mtime values along with file content. Default: ON.'),
      _kv(t, 'Sync Symbolic Links',
          'Replicate symlinks as symlinks (instead of dereferencing). '
          'Default: ON.'),
      _kv(t, 'FAT Filesystem Tolerance',
          'Allow 2-second time differences (FAT/exFAT only stores time at '
          '2-second granularity). Turn ON if syncing to USB sticks. '
          'Default: OFF.'),
      _kv(t, 'Confirm Large Deletions',
          'Require explicit confirmation when many files are about to be '
          'deleted. Default: ON.'),
      _kv(t, 'Sync Extended Attributes',
          'Copy file metadata like xattrs, finder tags, etc. Linux/macOS '
          'only. Default: OFF.'),
      _h2(t, 'Conflict Resolution'),
      _kv(t, 'Prefer Newer File',
          'When both sides changed a file, automatically keep the more '
          'recently modified one. Default: OFF (skip conflicts).'),
      _kv(t, 'Prevent Deletions',
          'Never propagate deletes — if a file disappears on one side, '
          'don\'t delete it on the other. Default: OFF.'),
      _kv(t, 'Prevent New File Creation',
          'Never copy files that don\'t already exist on both sides. '
          'Default: OFF.'),
      _kv(t, 'Prevent Content Updates',
          'Never overwrite changed files (only sync new/deleted). '
          'Default: OFF.'),
    ],
  );

  Widget _filters(FluentThemeData t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _h1(t, 'Ignore Filters'),
      _p(t, 'Patterns that exclude files from sync. They apply to both replicas.'),
      _h2(t, 'Pattern Types'),
      _kv(t, 'Name <glob>',
          'Match the FINAL component of a path. Example: "Name *.tmp" '
          'matches every .tmp file at any depth.'),
      _kv(t, 'Path <glob>',
          'Match the FULL relative path. Example: "Path build/output.bin".'),
      _kv(t, 'BelowPath <prefix>',
          'Match a path and everything beneath it. Example: '
          '"BelowPath node_modules" excludes the folder and all children.'),
      _kv(t, 'Regex <regex>',
          'Match by regular expression. Example: "Regex .*\\.bak\$".'),
      _h2(t, 'Glob Syntax'),
      _kv(t, '*', 'any chars except /'),
      _kv(t, '?', 'any single char except /'),
      _kv(t, '[abc]', 'character class'),
      _kv(t, '{a,b,c}', 'alternation: matches a OR b OR c'),
      _kv(t, '\\\\', 'escape: \\\\* matches a literal *'),
      _h2(t, 'Examples'),
      _p(t, 'Name {*.tmp,*.bak,*.log}\n'
            'Name .DS_Store\n'
            'Path .git\n'
            'BelowPath node_modules\n'
            'Regex .*\\.swp\$'),
    ],
  );

  Widget _remote(FluentThemeData t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _h1(t, 'Remote Sync'),
      _h2(t, 'WebDAV (cloud / NAS)'),
      _p(t, 'Works with any WebDAV server. Built-in presets:'),
      _kv(t, 'Nextcloud / ownCloud',
          'https://YOUR-SERVER/remote.php/dav/files/USERNAME/'),
      _kv(t, 'HiDrive (Strato)',
          'https://webdav.hidrive.strato.com/users/USERNAME/'),
      _kv(t, 'pCloud', 'https://webdav.pcloud.com/'),
      _kv(t, 'Box', 'https://dav.box.com/dav/'),
      _kv(t, 'Synology / QNAP NAS', 'https://YOUR-NAS:PORT/'),
      _p(t, 'Files are stored under UniSync/<profile-name>/ on the server. '
            'Passwords are kept in the OS keyring (Windows Credential Manager / '
            'macOS Keychain / libsecret) — NEVER in plain text.'),
      _h2(t, 'SSH'),
      _p(t, 'Format: ssh://user@host:port/path/to/folder. Requires the unisync '
            'binary on the remote machine (run: unisync --server /path).'),
      _h2(t, 'SSH Command + Args'),
      _kv(t, 'SSH Command', 'Override the ssh binary (default: ssh).'),
      _kv(t, 'Additional SSH Arguments',
          'Extra args passed to ssh, e.g. -o StrictHostKeyChecking=no'),
    ],
  );

  Widget _timeMachine(FluentThemeData t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _h1(t, 'Time Machine'),
      _p(t, 'Browse the history of all syncs. Each sync is recorded with '
            'changed paths, action types, and direction.'),
      _h2(t, 'Timeline'),
      _p(t, 'Left panel: list of past syncs (newest first). Click one to see '
            'the changed files.'),
      _h2(t, 'File History'),
      _p(t, 'Right panel: changed files in the selected sync. Click "History" '
            'on a file to see all past versions.'),
      _h2(t, 'Storage'),
      _p(t, 'History is stored as JSON in ~/.unison/history/. Last 100 syncs '
            'are kept (older ones are auto-pruned).'),
    ],
  );

  Widget _conflicts(FluentThemeData t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _h1(t, 'Conflict Resolution'),
      _p(t, 'When both replicas change the same file differently, UniSync '
            'flags it as a conflict and skips it by default.'),
      _h2(t, 'In the Sync Screen'),
      _p(t, 'Direction arrows next to each item:'),
      _kv(t, '----->', 'Replica 1 will overwrite Replica 2'),
      _kv(t, '<-----', 'Replica 2 will overwrite Replica 1'),
      _kv(t, '<-?->', 'Conflict — will be skipped'),
      _kv(t, '<-M->', 'Merge — passed to external merge tool'),
      _h2(t, 'Batch Buttons'),
      _kv(t, 'Accept All', 'Apply default direction to all items'),
      _kv(t, 'All →', 'Force everything Replica 1 → Replica 2'),
      _kv(t, 'All ←', 'Force everything Replica 2 → Replica 1'),
      _kv(t, 'Skip Conflicts', 'Mark all conflicts as skipped'),
      _kv(t, 'Reset', 'Revert all to computed defaults'),
    ],
  );

  Widget _security(FluentThemeData t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _h1(t, 'Security'),
      _h2(t, 'Passwords'),
      _p(t, 'WebDAV / SSH passwords are stored in the OS-native credential '
            'store, not in profile files:'),
      _kv(t, 'Windows', 'Credential Manager (DPAPI-encrypted, per-user)'),
      _kv(t, 'macOS', 'Keychain'),
      _kv(t, 'Linux', 'libsecret (GNOME Keyring / KWallet)'),
      _p(t, 'Passwords cannot be read by other users on the same machine.'),
      _h2(t, 'Set / Edit Passwords'),
      _p(t, 'Click the lock icon on a profile card with WebDAV to set or '
            'change the stored password.'),
      _h2(t, 'Profile Files'),
      _p(t, 'Profile (.prf) files only contain URL + username — never the '
            'password.'),
    ],
  );

  Widget _cli(FluentThemeData t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _h1(t, 'Command Line Interface'),
      _p(t, 'UniSync also includes a standalone CLI binary (unisync.exe) '
            'for headless / server use.'),
      _h2(t, 'Commands'),
      _kv(t, 'unisync <profile>', 'Sync using a saved profile'),
      _kv(t, 'unisync <root1> <root2>', 'Sync two directories'),
      _kv(t, 'unisync --batch <profile>', 'No prompts, skip conflicts'),
      _kv(t, 'unisync --watch <profile>', 'Continuous sync on changes'),
      _kv(t, 'unisync --repeat 60 <profile>', 'Sync every 60 seconds'),
      _kv(t, 'unisync --list', 'List all profiles'),
      _kv(t, 'unisync --server <root>', 'Run as remote sync server'),
      _h2(t, 'Interactive TUI Keys'),
      _p(t, '> .  Replica 1 → 2\n'
            '< ,  Replica 2 → 1\n'
            '/    Skip\n'
            'm    Merge\n'
            'A    Accept all defaults\n'
            '1    All → Replica 2\n'
            '2    All → Replica 1\n'
            'C    Skip all conflicts\n'
            'g    Go (execute)\n'
            'q    Quit'),
    ],
  );

  Widget _troubleshooting(FluentThemeData t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _h1(t, 'Troubleshooting'),
      _h2(t, 'App appears to hang during sync'),
      _p(t, 'Toggle the Log Panel (button in Sync screen) to see the last '
            'request. Most hangs come from:'),
      _kv(t, 'Wrong WebDAV URL',
          'For HiDrive, URL must be webdav.hidrive.strato.com/users/USERNAME/ — '
          'not just the root URL.'),
      _kv(t, 'Wrong Password',
          'Server returns 401. Check via the lock icon on profile card.'),
      _kv(t, 'Network blocked',
          'Firewall blocks HTTPS — try a different network.'),
      _h2(t, 'WebDAV 403 Forbidden'),
      _p(t, 'Your account doesn\'t have write permission at that URL. '
            'Make sure the URL points to a writable directory in your account.'),
      _h2(t, 'WebDAV 404 Not Found'),
      _p(t, 'The path doesn\'t exist. UniSync auto-creates UniSync/<profile>/ '
            'but parent paths must exist.'),
      _h2(t, 'Sync stuck on "Ensuring remote prefix"'),
      _p(t, 'The server isn\'t responding to MKCOL within 30 seconds. '
            'Check Log Panel for the failing URL. Possible causes: server '
            'overload, captive portal, network outage.'),
      _h2(t, 'Logs / Debug Info'),
      _p(t, 'The Sync screen has a built-in Log Panel showing every WebDAV '
            'request. Click "Show Log" to expand it. Logs are not persisted.'),
      _h2(t, 'Reset a profile'),
      _p(t, 'Delete the profile and re-create it. Archive files at '
            '~/.unison/ar* will be regenerated on the next sync.'),
    ],
  );
}
