import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings_state.dart';
import '../state/sync_state.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedSection = 0;
  final _patternController = TextEditingController();

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final settings = ref.watch(appSettingsProvider);
    final profileDir = ref.watch(profileDirProvider);

    return ScaffoldPage(
      header: const PageHeader(title: Text('Settings')),
      content: Row(
        children: [
          SizedBox(
            width: 200,
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                _sectionTile(0, FluentIcons.folder, 'General'),
                _sectionTile(1, FluentIcons.sync, 'Sync'),
                _sectionTile(2, FluentIcons.filter, 'Filters'),
                _sectionTile(3, FluentIcons.cloud, 'Remote'),
                _sectionTile(4, FluentIcons.info, 'About'),
              ],
            ),
          ),
          Container(width: 1, color: theme.resources.dividerStrokeColorDefault),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: switch (_selectedSection) {
                0 => _buildGeneral(settings, profileDir, theme),
                1 => _buildSync(settings, theme),
                2 => _buildFilters(settings, theme),
                3 => _buildRemote(settings, theme),
                4 => _buildAbout(theme),
                _ => const SizedBox(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTile(int index, IconData icon, String label) {
    return ListTile.selectable(
      leading: Icon(icon, size: 16),
      title: Text(label),
      selected: _selectedSection == index,
      onPressed: () => setState(() => _selectedSection = index),
    );
  }

  void _update(AppSettings Function(AppSettings) fn) {
    ref.read(appSettingsProvider.notifier).update(fn);
  }

  Widget _buildGeneral(AppSettings s, String profileDir, FluentThemeData theme) {
    return ListView(
      children: [
        Text('General', style: theme.typography.subtitle),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Profile Directory',
          child: TextBox(readOnly: true, controller: TextEditingController(text: profileDir)),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Max Concurrent Transfers',
          child: NumberBox<int>(
            value: s.maxThreads,
            min: 1,
            max: 100,
            onChanged: (v) => _update((s) => s.copyWith(maxThreads: v ?? 20)),
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Max Errors Before Abort (-1 = never)',
          child: NumberBox<int>(
            value: s.maxErrors,
            min: -1,
            max: 1000,
            onChanged: (v) => _update((s) => s.copyWith(maxErrors: v ?? -1)),
          ),
        ),
      ],
    );
  }

  Widget _buildSync(AppSettings s, FluentThemeData theme) {
    return ListView(
      children: [
        Text('Sync Behavior', style: theme.typography.subtitle),
        const SizedBox(height: 16),
        _toggle('Fast Check (skip fingerprint if mtime+size unchanged)', s.fastCheck,
            (v) => _update((s) => s.copyWith(fastCheck: v))),
        _toggle('Preserve Modification Times', s.times,
            (v) => _update((s) => s.copyWith(times: v))),
        _toggle('Sync Symbolic Links', s.links,
            (v) => _update((s) => s.copyWith(links: v))),
        _toggle('FAT Filesystem Tolerance', s.fatFilesystem,
            (v) => _update((s) => s.copyWith(fatFilesystem: v))),
        _toggle('Confirm Large Deletions', s.confirmBigDeletes,
            (v) => _update((s) => s.copyWith(confirmBigDeletes: v))),
        _toggle('Sync Extended Attributes', s.syncXattrs,
            (v) => _update((s) => s.copyWith(syncXattrs: v))),
        const SizedBox(height: 24),
        Text('Conflict Resolution', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        _toggle('Prefer Newer File', s.preferNewer,
            (v) => _update((s) => s.copyWith(preferNewer: v))),
        _toggle('Prevent Deletions', s.noDeletion,
            (v) => _update((s) => s.copyWith(noDeletion: v))),
        _toggle('Prevent New File Creation', s.noCreation,
            (v) => _update((s) => s.copyWith(noCreation: v))),
        _toggle('Prevent Content Updates', s.noUpdate,
            (v) => _update((s) => s.copyWith(noUpdate: v))),
      ],
    );
  }

  Widget _buildFilters(AppSettings s, FluentThemeData theme) {
    return ListView(
      children: [
        Text('Ignore Patterns', style: theme.typography.subtitle),
        const SizedBox(height: 8),
        Text('Files matching these patterns are excluded from sync.',
            style: theme.typography.body),
        const SizedBox(height: 12),
        for (var i = 0; i < s.ignorePatterns.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const Icon(FluentIcons.filter, size: 12),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(s.ignorePatterns[i],
                      style: const TextStyle(fontFamily: 'Consolas')),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.delete, size: 12),
                  onPressed: () =>
                      ref.read(appSettingsProvider.notifier).removeIgnorePattern(i),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextBox(
                controller: _patternController,
                placeholder: 'Name *.tmp',
              ),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: () {
                final p = _patternController.text.trim();
                if (p.isNotEmpty) {
                  ref.read(appSettingsProvider.notifier).addIgnorePattern(p);
                  _patternController.clear();
                }
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.add, size: 12),
                  SizedBox(width: 4),
                  Text('Add'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRemote(AppSettings s, FluentThemeData theme) {
    return ListView(
      children: [
        Text('Remote Connection', style: theme.typography.subtitle),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'SSH Command',
          child: TextBox(
            controller: TextEditingController(text: s.sshCmd),
            onChanged: (v) => _update((s) => s.copyWith(sshCmd: v)),
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Additional SSH Arguments',
          child: TextBox(
            controller: TextEditingController(text: s.sshArgs),
            placeholder: '-o StrictHostKeyChecking=no',
            onChanged: (v) => _update((s) => s.copyWith(sshArgs: v)),
          ),
        ),
      ],
    );
  }

  Widget _buildAbout(FluentThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('UniSync', style: theme.typography.subtitle),
        const SizedBox(height: 8),
        Text('Bidirectional File Synchronizer', style: theme.typography.body),
        const SizedBox(height: 24),
        _info('Version', '0.1.0'),
        _info('Engine', 'unison_core (Dart)'),
        _info('Protocol', 'v1'),
        _info('Tests', '326 passing'),
        const SizedBox(height: 24),
        Text(
          'Inspired by Unison by Benjamin C. Pierce et al.\n'
          'github.com/bcpierce00/unison\n\n'
          'UniSync is a clean-room reimplementation in Dart/Flutter.',
          style: theme.typography.caption,
        ),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          ToggleSwitch(checked: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
