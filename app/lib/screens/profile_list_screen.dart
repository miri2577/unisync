import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unison_core/unison_core.dart';

import '../state/settings_state.dart';
import '../state/sync_state.dart';
import 'sync_screen.dart';

class ProfileListScreen extends ConsumerWidget {
  const ProfileListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileListProvider);

    return ScaffoldPage.scrollable(
      header: PageHeader(
        title: const Text('Profiles'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('New Profile'),
              onPressed: () => _showCreateDialog(context, ref),
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('Refresh'),
              onPressed: () =>
                  ref.read(profileListProvider.notifier).refresh(),
            ),
          ],
        ),
      ),
      children: [
        if (state.isLoading)
          const Center(child: ProgressRing())
        else if (state.profiles.isEmpty)
          _buildEmptyState(context, ref)
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: state.profiles
                .map((p) => _ProfileCard(profile: p))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.sync, size: 64),
          const SizedBox(height: 16),
          Text(
            'No sync profiles found',
            style: FluentTheme.of(context).typography.subtitle,
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new profile to get started.',
            style: FluentTheme.of(context).typography.body,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => _showCreateDialog(context, ref),
            child: const Text('Create Profile'),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _CreateProfileDialog(ref: ref),
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  final ProfileInfo profile;

  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    final displayName = profile.label ?? profile.name;
    final rootsText = profile.roots.length >= 2
        ? '${profile.roots[0]}\n${profile.roots[1]}'
        : profile.roots.join('\n');

    return SizedBox(
      width: 320,
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(FluentIcons.sync, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayName,
                    style: theme.typography.bodyStrong,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (profile.key != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      profile.key!,
                      style: theme.typography.caption,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              rootsText,
              style: theme.typography.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Button(
                  onPressed: () => _deleteProfile(context, ref),
                  child: const Text('Delete'),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: () => _startWatch(context, ref),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.red_eye, size: 12),
                      SizedBox(width: 4),
                      Text('Watch'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _startSync(context, ref),
                  child: const Text('Sync'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _startSync(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      FluentPageRoute(
        builder: (_) => SyncScreen(profileName: profile.name),
      ),
    );
  }

  void _startWatch(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      FluentPageRoute(
        builder: (_) => _WatchScreen(profileName: profile.name),
      ),
    );
  }

  void _deleteProfile(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('Delete Profile'),
        content: Text('Delete profile "${profile.name}"?'),
        actions: [
          Button(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(profileListProvider.notifier).deleteProfile(profile.name);
    }
  }
}

class _CreateProfileDialog extends StatefulWidget {
  final WidgetRef ref;

  const _CreateProfileDialog({required this.ref});

  @override
  State<_CreateProfileDialog> createState() => _CreateProfileDialogState();
}

/// Known WebDAV providers with URL templates.
const _webdavProviders = <(String, String, String)>[
  ('Nextcloud', 'https://YOUR-SERVER/remote.php/dav/files/USERNAME/', 'Replace YOUR-SERVER and USERNAME'),
  ('HiDrive (Strato)', 'https://webdav.hidrive.strato.com/users/USERNAME/', 'Replace USERNAME with your HiDrive username'),
  ('pCloud', 'https://webdav.pcloud.com/', 'Uses your pCloud login'),
  ('Box', 'https://dav.box.com/dav/', 'Uses your Box login'),
  ('4shared', 'https://webdav.4shared.com/', 'Uses your 4shared login'),
  ('Yandex Disk', 'https://webdav.yandex.com/', 'Uses your Yandex login'),
  ('Synology NAS', 'https://YOUR-NAS:5006/', 'Replace YOUR-NAS with IP/hostname'),
  ('QNAP NAS', 'https://YOUR-NAS:8080/', 'Replace YOUR-NAS with IP/hostname'),
  ('ownCloud', 'https://YOUR-SERVER/remote.php/dav/files/USERNAME/', 'Replace YOUR-SERVER and USERNAME'),
  ('Custom', '', 'Enter your own WebDAV URL'),
];

class _CreateProfileDialogState extends State<_CreateProfileDialog> {
  final _nameController = TextEditingController();
  final _root1Controller = TextEditingController();
  final _root2Controller = TextEditingController();
  String _root2Type = 'local';
  String _webdavProvider = 'Custom';
  final _webdavUrlController = TextEditingController();
  final _webdavUserController = TextEditingController();
  final _webdavPassController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _root1Controller.dispose();
    _root2Controller.dispose();
    _webdavUrlController.dispose();
    _webdavUserController.dispose();
    _webdavPassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('Create New Profile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoLabel(
            label: 'Profile Name',
            child: TextBox(
              controller: _nameController,
              placeholder: 'my-sync',
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Root 1 (Local Path)',
            child: Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: _root1Controller,
                    placeholder: 'C:\\Users\\you\\Documents',
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: () => _pickFolder(_root1Controller),
                  child: const Icon(FluentIcons.folder_open, size: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Root 2 Type',
            child: ComboBox<String>(
              value: _root2Type,
              items: const [
                ComboBoxItem(value: 'local', child: Text('Local Path')),
                ComboBoxItem(value: 'ssh', child: Text('SSH Remote')),
                ComboBoxItem(value: 'webdav', child: Text('WebDAV (Nextcloud, HiDrive, ...)')),
              ],
              onChanged: (v) => setState(() => _root2Type = v ?? 'local'),
            ),
          ),
          const SizedBox(height: 16),
          if (_root2Type == 'local')
            InfoLabel(
              label: 'Root 2 (Local Path)',
              child: Row(
                children: [
                  Expanded(
                    child: TextBox(
                      controller: _root2Controller,
                      placeholder: 'D:\\Backup\\Documents',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: () => _pickFolder(_root2Controller),
                    child: const Icon(FluentIcons.folder_open, size: 14),
                  ),
                ],
              ),
            ),
          if (_root2Type == 'ssh')
            InfoLabel(
              label: 'Root 2 (SSH)',
              child: TextBox(
                controller: _root2Controller,
                placeholder: 'ssh://user@host/path',
              ),
            ),
          if (_root2Type == 'webdav') ...[
            InfoLabel(
              label: 'Provider',
              child: ComboBox<String>(
                value: _webdavProvider,
                isExpanded: true,
                items: [
                  for (final (name, _, hint) in _webdavProviders)
                    ComboBoxItem(
                      value: name,
                      child: Text(name),
                    ),
                ],
                onChanged: (v) {
                  setState(() {
                    _webdavProvider = v ?? 'Custom';
                    final entry = _webdavProviders.firstWhere(
                      (e) => e.$1 == _webdavProvider,
                      orElse: () => ('Custom', '', ''),
                    );
                    if (entry.$2.isNotEmpty) {
                      _webdavUrlController.text = entry.$2;
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 4),
            // Show hint for selected provider
            Builder(builder: (_) {
              final entry = _webdavProviders.firstWhere(
                (e) => e.$1 == _webdavProvider,
                orElse: () => ('', '', ''),
              );
              if (entry.$3.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(entry.$3,
                    style: FluentTheme.of(context).typography.caption),
                );
              }
              return const SizedBox();
            }),
            const SizedBox(height: 8),
            InfoLabel(
              label: 'WebDAV URL',
              child: TextBox(
                controller: _webdavUrlController,
                placeholder: 'https://cloud.example.com/remote.php/dav/files/user/',
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Username',
              child: TextBox(
                controller: _webdavUserController,
                placeholder: 'username',
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: 'Password',
              child: PasswordBox(
                controller: _webdavPassController,
                placeholder: 'password',
              ),
            ),
          ],
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _create,
          child: const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _pickFolder(TextEditingController controller) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Folder',
    );
    if (result != null) {
      controller.text = result;
    }
  }

  void _create() {
    final name = _nameController.text.trim();
    final root1 = _root1Controller.text.trim();

    if (name.isEmpty || root1.isEmpty) return;

    String root2;
    String extraConfig = '';

    if (_root2Type == 'webdav') {
      final url = _webdavUrlController.text.trim();
      final user = _webdavUserController.text.trim();
      final pass = _webdavPassController.text.trim();
      if (url.isEmpty || user.isEmpty) return;
      root2 = 'webdav://$url';
      extraConfig = 'webdavurl = $url\n'
          'webdavuser = $user\n'
          'webdavpass = $pass\n';
    } else {
      root2 = _root2Controller.text.trim();
      if (root2.isEmpty) return;
    }

    // Create profile with optional WebDAV config
    final profileDir = widget.ref.read(profileDirProvider);
    Directory(profileDir).createSync(recursive: true);
    final content = 'root = $root1\nroot = $root2\n$extraConfig';
    File('$profileDir/$name.prf').writeAsStringSync(content);
    widget.ref.read(profileListProvider.notifier).refresh();
    Navigator.pop(context);
  }
}

/// Watch mode screen — continuous sync with live status.
class _WatchScreen extends ConsumerStatefulWidget {
  final String profileName;
  const _WatchScreen({required this.profileName});

  @override
  ConsumerState<_WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<_WatchScreen> {
  WatchSyncController? _controller;
  final _log = <String>[];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startWatch());
  }

  @override
  void dispose() {
    _controller?.stop();
    super.dispose();
  }

  void _startWatch() {
    final profileDir = ref.read(profileDirProvider);
    final settings = ref.read(appSettingsProvider);
    final prefs = UnisonPrefs();
    final parser = ProfileParser(profileDir);
    parser.loadProfile(widget.profileName, prefs.registry);

    if (prefs.root.value.length < 2) {
      setState(() => _log.add('Error: profile needs 2 roots'));
      return;
    }

    final root1 = Fspath.fromLocal(prefs.root.value[0]);
    final root2 = Fspath.fromLocal(prefs.root.value[1]);
    final store = ArchiveStore(profileDir);
    store.recoverAll();

    final engine = SyncEngine(
      archiveStore: store,
      transport: TransportOrchestrator(
        maxThreads: settings.maxThreads,
        maxErrors: settings.maxErrors,
      ),
    );

    setState(() {
      _running = true;
      _log.add('[${_time()}] Watch mode started');
      _log.add('Root 1: $root1');
      _log.add('Root 2: $root2');
    });

    _controller = engine.syncWatch(
      root1,
      root2,
      updateConfig: settings.toUpdateConfig(),
      reconConfig: settings.toReconConfig(),
      onProgress: (phase, msg) {
        setState(() => _log.add('[${_time()}] $msg'));
      },
      onSyncComplete: (result) {
        setState(() {
          if (result.propagated > 0 || result.failed > 0) {
            _log.add('[${_time()}] Sync: ${result.propagated} OK, '
                '${result.skipped} skipped, ${result.failed} failed');
          } else {
            _log.add('[${_time()}] In sync');
          }
        });
      },
    );
  }

  String _time() => DateTime.now().toString().substring(11, 19);

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return NavigationView(
      pane: NavigationPane(
        displayMode: PaneDisplayMode.top,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.red_eye),
            title: Text('Watch: ${widget.profileName}'),
            body: Column(
              children: [
                // Status bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: theme.resources.dividerStrokeColorDefault,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(FluentIcons.back),
                        onPressed: () {
                          _controller?.stop();
                          Navigator.of(context).pop();
                        },
                      ),
                      const SizedBox(width: 12),
                      if (_running)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 16, height: 16,
                            child: ProgressRing(strokeWidth: 2),
                          ),
                        ),
                      Text(
                        _running ? 'Watching for changes...' : 'Stopped',
                        style: theme.typography.body,
                      ),
                      const Spacer(),
                      Button(
                        onPressed: () {
                          _controller?.stop();
                          setState(() {
                            _running = false;
                            _log.add('[${_time()}] Stopped');
                          });
                        },
                        child: const Text('Stop'),
                      ),
                    ],
                  ),
                ),
                // Log
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _log.length,
                    itemBuilder: (_, i) => Text(
                      _log[i],
                      style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
