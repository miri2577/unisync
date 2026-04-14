import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unison_core/unison_core.dart';

import '../state/sync_state.dart';

/// Time Machine — browse sync history and restore file versions.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<SyncRecord> _records = [];
  SyncRecord? _selectedRecord;
  String? _selectedFile;
  List<(SyncRecord, HistoryEntry)>? _fileVersions;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    final dir = ref.read(profileDirProvider);
    final history = SyncHistory(dir);
    setState(() {
      _records = history.loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      header: PageHeader(
        title: const Row(
          children: [
            Icon(FluentIcons.history, size: 24),
            SizedBox(width: 8),
            Text('Time Machine'),
          ],
        ),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('Refresh'),
              onPressed: _loadHistory,
            ),
          ],
        ),
      ),
      content: _records.isEmpty
          ? _buildEmpty(theme)
          : Row(
              children: [
                // Timeline (left)
                SizedBox(
                  width: 350,
                  child: _buildTimeline(theme),
                ),
                Container(
                    width: 1,
                    color: theme.resources.dividerStrokeColorDefault),
                // Detail (right)
                Expanded(
                  child: _selectedRecord != null
                      ? _fileVersions != null
                          ? _buildFileVersions(theme)
                          : _buildRecordDetail(theme)
                      : Center(
                          child: Text(
                            'Select a sync to view details',
                            style: theme.typography.body,
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(FluentThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.history, size: 64),
          const SizedBox(height: 16),
          Text('No sync history yet', style: theme.typography.subtitle),
          const SizedBox(height: 8),
          Text(
            'Sync history will appear here after your first sync.',
            style: theme.typography.body,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(FluentThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _records.length,
      itemBuilder: (_, i) {
        final r = _records[i];
        final isSelected = _selectedRecord?.id == r.id;
        final date = '${r.timestamp.day}.${r.timestamp.month}.${r.timestamp.year}';
        final time = r.timestamp.toString().substring(11, 16);

        return ListTile.selectable(
          selected: isSelected,
          onPressed: () => setState(() {
            _selectedRecord = r;
            _fileVersions = null;
            _selectedFile = null;
          }),
          leading: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(time,
                  style: theme.typography.bodyStrong),
              Text(date, style: theme.typography.caption),
            ],
          ),
          title: Text(
            '${r.propagated} synced, ${r.skipped} skipped',
            style: theme.typography.body,
          ),
          subtitle: Text(
            '${r.entries.length} files changed',
            style: theme.typography.caption,
          ),
          trailing: r.failed > 0
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('${r.failed} failed',
                      style: TextStyle(fontSize: 11, color: Colors.red)),
                )
              : null,
        );
      },
    );
  }

  Widget _buildRecordDetail(FluentThemeData theme) {
    final r = _selectedRecord!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Sync #${r.id}',
          style: theme.typography.subtitle,
        ),
        const SizedBox(height: 8),
        Text('${r.timestamp}', style: theme.typography.caption),
        Text('${r.root1}  <->  ${r.root2}',
            style: theme.typography.caption),
        const SizedBox(height: 16),
        Row(
          children: [
            _badge('Propagated', r.propagated, Colors.green),
            const SizedBox(width: 8),
            _badge('Skipped', r.skipped, Colors.orange),
            const SizedBox(width: 8),
            _badge('Failed', r.failed, Colors.red),
          ],
        ),
        const SizedBox(height: 24),
        Text('Changed Files', style: theme.typography.bodyStrong),
        const SizedBox(height: 8),
        for (final entry in r.entries)
          ListTile(
            leading: Icon(_actionIcon(entry.action), size: 16),
            title: Text(entry.path),
            subtitle: Text(
              '${entry.action} | ${entry.direction} | '
              '${_formatSize(entry.size)}',
              style: theme.typography.caption,
            ),
            trailing: Button(
              onPressed: () => _showFileHistory(entry.path),
              child: const Text('History'),
            ),
          ),
      ],
    );
  }

  Widget _buildFileVersions(FluentThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(FluentIcons.back, size: 14),
              onPressed: () => setState(() {
                _fileVersions = null;
                _selectedFile = null;
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'File History: $_selectedFile',
                style: theme.typography.subtitle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final (record, entry) in _fileVersions!)
          ListTile(
            leading: Icon(_actionIcon(entry.action), size: 16),
            title: Text(record.timestamp.toString().substring(0, 19)),
            subtitle: Text(
              '${entry.action} | ${entry.direction} | '
              '${_formatSize(entry.size)}',
              style: theme.typography.caption,
            ),
          ),
        if (_fileVersions!.isEmpty)
          Text('No history for this file',
              style: theme.typography.body),
      ],
    );
  }

  void _showFileHistory(String path) {
    final dir = ref.read(profileDirProvider);
    final history = SyncHistory(dir);
    setState(() {
      _selectedFile = path;
      _fileVersions = history.fileHistory(path);
    });
  }

  Widget _badge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label: $count',
          style: TextStyle(fontSize: 12, color: color)),
    );
  }

  IconData _actionIcon(String action) {
    return switch (action) {
      'created' => FluentIcons.add,
      'modified' => FluentIcons.edit,
      'deleted' => FluentIcons.delete,
      'propsChanged' => FluentIcons.permissions,
      _ => FluentIcons.page,
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
