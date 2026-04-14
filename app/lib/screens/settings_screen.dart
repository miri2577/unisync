import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/sync_state.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedSection = 0;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final profileDir = ref.watch(profileDirProvider);

    return ScaffoldPage(
      header: const PageHeader(title: Text('Settings')),
      content: Row(
        children: [
          // Section list
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
          // Divider
          Container(width: 1, color: theme.resources.dividerStrokeColorDefault),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: switch (_selectedSection) {
                0 => _buildGeneral(profileDir, theme),
                1 => _buildSync(theme),
                2 => _buildFilters(theme),
                3 => _buildRemote(theme),
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
    final isSelected = _selectedSection == index;
    return ListTile.selectable(
      leading: Icon(icon, size: 16),
      title: Text(label),
      selected: isSelected,
      onPressed: () => setState(() => _selectedSection = index),
    );
  }

  Widget _buildGeneral(String profileDir, FluentThemeData theme) {
    return ListView(
      children: [
        Text('General', style: theme.typography.subtitle),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Profile Directory',
          child: TextBox(
            readOnly: true,
            controller: TextEditingController(text: profileDir),
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Theme',
          child: ComboBox<String>(
            value: 'System',
            items: const [
              ComboBoxItem(value: 'System', child: Text('System')),
              ComboBoxItem(value: 'Light', child: Text('Light')),
              ComboBoxItem(value: 'Dark', child: Text('Dark')),
            ],
            onChanged: (_) {},
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Max Concurrent Transfers',
          child: NumberBox<int>(
            value: 20,
            min: 1,
            max: 100,
            onChanged: (_) {},
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Max Errors Before Abort (-1 = never)',
          child: NumberBox<int>(
            value: -1,
            min: -1,
            max: 1000,
            onChanged: (_) {},
          ),
        ),
      ],
    );
  }

  Widget _buildSync(FluentThemeData theme) {
    return ListView(
      children: [
        Text('Sync Behavior', style: theme.typography.subtitle),
        const SizedBox(height: 16),
        _toggleRow('Fast Check (skip fingerprint if mtime+size unchanged)', true),
        _toggleRow('Preserve Modification Times', true),
        _toggleRow('Sync Symbolic Links', true),
        _toggleRow('FAT Filesystem Tolerance (2-second granularity)', false),
        _toggleRow('Confirm Large Deletions', true),
        const SizedBox(height: 24),
        Text('Conflict Resolution', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        _toggleRow('Prefer Newer File', false),
        _toggleRow('Prevent Deletions', false),
        _toggleRow('Prevent New File Creation', false),
        _toggleRow('Prevent Content Updates', false),
      ],
    );
  }

  Widget _buildFilters(FluentThemeData theme) {
    return ListView(
      children: [
        Text('Ignore Patterns', style: theme.typography.subtitle),
        const SizedBox(height: 16),
        Text(
          'Files matching these patterns will be excluded from sync.',
          style: theme.typography.body,
        ),
        const SizedBox(height: 12),
        _patternRow('Name *.tmp'),
        _patternRow('Name .DS_Store'),
        _patternRow('Name {.git,.svn}'),
        _patternRow('Path node_modules'),
        const SizedBox(height: 12),
        Button(
          onPressed: () {},
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.add, size: 12),
              SizedBox(width: 6),
              Text('Add Pattern'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRemote(FluentThemeData theme) {
    return ListView(
      children: [
        Text('Remote Connection', style: theme.typography.subtitle),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'SSH Command',
          child: TextBox(
            controller: TextEditingController(text: 'ssh'),
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Additional SSH Arguments',
          child: const TextBox(placeholder: '-o StrictHostKeyChecking=no'),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: 'Remote Unison Command',
          child: const TextBox(placeholder: 'unison'),
        ),
      ],
    );
  }

  Widget _buildAbout(FluentThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Unison File Synchronizer', style: theme.typography.subtitle),
        const SizedBox(height: 8),
        Text('Dart/Flutter Implementation', style: theme.typography.body),
        const SizedBox(height: 24),
        _infoRow('Version', '0.1.0'),
        _infoRow('Engine', 'unison_core'),
        _infoRow('Protocol Version', '1'),
        _infoRow('Tests', '326 passing'),
        _infoRow('Source Files', '49'),
        const SizedBox(height: 24),
        Text(
          'Based on Unison by Benjamin C. Pierce et al.\n'
          'Original: github.com/bcpierce00/unison\n'
          'This implementation: Pure Dart/Flutter rewrite.',
          style: theme.typography.caption,
        ),
      ],
    );
  }

  Widget _toggleRow(String label, bool initialValue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          ToggleSwitch(
            checked: initialValue,
            onChanged: (_) {},
          ),
        ],
      ),
    );
  }

  Widget _patternRow(String pattern) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(FluentIcons.filter, size: 12),
          const SizedBox(width: 8),
          Expanded(
            child: Text(pattern, style: const TextStyle(fontFamily: 'Consolas')),
          ),
          IconButton(
            icon: const Icon(FluentIcons.delete, size: 12),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
