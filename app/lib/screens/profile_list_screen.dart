import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unison_core/unison_core.dart';

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

class _CreateProfileDialogState extends State<_CreateProfileDialog> {
  final _nameController = TextEditingController();
  final _root1Controller = TextEditingController();
  final _root2Controller = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _root1Controller.dispose();
    _root2Controller.dispose();
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
            child: TextBox(
              controller: _root1Controller,
              placeholder: 'C:\\Users\\you\\Documents',
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Root 2 (Local Path or SSH)',
            child: TextBox(
              controller: _root2Controller,
              placeholder: 'D:\\Backup\\Documents',
            ),
          ),
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

  void _create() {
    final name = _nameController.text.trim();
    final root1 = _root1Controller.text.trim();
    final root2 = _root2Controller.text.trim();

    if (name.isEmpty || root1.isEmpty || root2.isEmpty) return;

    widget.ref
        .read(profileListProvider.notifier)
        .createProfile(name, root1, root2);
    Navigator.pop(context);
  }
}
