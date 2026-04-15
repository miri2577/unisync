import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unison_core/unison_core.dart';

import '../state/sync_state.dart';
import '../widgets/recon_item_tile.dart';

// Batch operations from unison_core
import 'package:unison_core/src/engine/batch_ops.dart' as batch;

class SyncScreen extends ConsumerStatefulWidget {
  final String profileName;

  const SyncScreen({super.key, required this.profileName});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncOperationProvider.notifier).scan(widget.profileName);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(syncOperationProvider);
    final theme = FluentTheme.of(context);

    return ScaffoldPage(
      header: PageHeader(
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: () {
            ref.read(syncOperationProvider.notifier).reset();
            Navigator.of(context).pop();
          },
        ),
        title: Row(
          children: [
            const Icon(FluentIcons.sync),
            const SizedBox(width: 8),
            Text(widget.profileName),
          ],
        ),
      ),
      content: _buildBody(context, state, theme),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SyncOperationState state,
    FluentThemeData theme,
  ) {
    return Column(
      children: [
        // Status bar
        _buildStatusBar(context, state, theme),
        // Content
        Expanded(child: _buildContent(state, theme)),
      ],
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    SyncOperationState state,
    FluentThemeData theme,
  ) {
    return Container(
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
              ref.read(syncOperationProvider.notifier).reset();
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: 12),
          if (state.phase == AppSyncPhase.scanning ||
              state.phase == AppSyncPhase.reconciling ||
              state.phase == AppSyncPhase.propagating)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: ProgressRing(strokeWidth: 2),
              ),
            ),
          Expanded(
            child: Text(
              state.message.isNotEmpty ? state.message : _phaseLabel(state.phase),
              style: theme.typography.body,
            ),
          ),
          if (state.result != null) ...[
            _buildBadge('OK', state.result!.propagated, Colors.green),
            const SizedBox(width: 6),
            _buildBadge('Skip', state.result!.skipped, Colors.orange),
            const SizedBox(width: 6),
            _buildBadge('Fail', state.result!.failed, Colors.red),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }

  Widget _buildContent(SyncOperationState state, FluentThemeData theme) {
    if (state.phase == AppSyncPhase.error) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.error_badge, size: 32, color: Colors.red),
                const SizedBox(height: 8),
                Text('Error', style: theme.typography.subtitle),
                const SizedBox(height: 8),
                SelectableText(
                  state.error ?? 'Unknown error',
                  style: theme.typography.body,
                ),
              ],
            ),
          ),
          Expanded(child: _buildLogPanel(state, theme)),
        ],
      );
    }

    if (state.phase == AppSyncPhase.idle ||
        state.phase == AppSyncPhase.scanning ||
        state.phase == AppSyncPhase.reconciling ||
        state.phase == AppSyncPhase.propagating) {
      return Column(
        children: [
          const SizedBox(height: 16),
          const Center(child: ProgressRing()),
          const SizedBox(height: 8),
          Center(
            child: Text(state.message, style: theme.typography.body),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildLogPanel(state, theme)),
        ],
      );
    }

    if (state.reconItems.isEmpty && state.phase == AppSyncPhase.done) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.completed, size: 32, color: Colors.green),
                const SizedBox(height: 8),
                Text('Everything is in sync', style: theme.typography.subtitle),
              ],
            ),
          ),
          Expanded(child: _buildLogPanel(state, theme)),
        ],
      );
    }

    // ReconItem list with batch action bar
    return Column(
      children: [
        _buildBatchBar(state),
        Expanded(
          flex: 2,
          child: _buildReconList(state),
        ),
        Expanded(child: _buildLogPanel(state, theme)),
      ],
    );
  }

  Widget _buildLogPanel(SyncOperationState state, FluentThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(FluentIcons.diagnostic_data_bar_tooltip, size: 12),
                const SizedBox(width: 6),
                Text('Log (${state.log.length})',
                    style: theme.typography.caption),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.black.withValues(alpha: 0.04),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListView.builder(
                reverse: true,
                itemCount: state.log.length,
                itemBuilder: (_, i) {
                  final line = state.log[state.log.length - 1 - i];
                  return SelectableText(
                    line,
                    style: const TextStyle(
                      fontFamily: 'Consolas', fontSize: 11.5,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchBar(SyncOperationState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: CommandBar(
        primaryItems: [
          CommandBarButton(
            icon: const Icon(FluentIcons.accept, size: 14),
            label: const Text('Accept All'),
            onPressed: () => setState(() {
              batch.batchAcceptDefaults(state.reconItems);
            }),
          ),
          CommandBarButton(
            icon: const Icon(FluentIcons.forward, size: 14),
            label: const Text('All →'),
            onPressed: () => setState(() {
              batch.batchForceRight(state.reconItems);
            }),
          ),
          CommandBarButton(
            icon: const Icon(FluentIcons.back, size: 14),
            label: const Text('All ←'),
            onPressed: () => setState(() {
              batch.batchForceLeft(state.reconItems);
            }),
          ),
          CommandBarButton(
            icon: const Icon(FluentIcons.warning, size: 14),
            label: const Text('Skip Conflicts'),
            onPressed: () => setState(() {
              batch.batchSkipConflicts(state.reconItems);
            }),
          ),
          CommandBarButton(
            icon: const Icon(FluentIcons.undo, size: 14),
            label: const Text('Reset'),
            onPressed: () => setState(() {
              batch.batchRevertAll(state.reconItems);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildReconList(SyncOperationState state) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: state.reconItems.length,
      itemBuilder: (context, index) {
        final item = state.reconItems[index];
        return ReconItemTile(
          item: item,
          onToggleDirection: () => _toggleDirection(item),
        );
      },
    );
  }

  void _toggleDirection(ReconItem item) {
    if (item.replicas case Different(diff: var diff)) {
      setState(() {
        diff.direction = switch (diff.direction) {
          Replica1ToReplica2() => const Replica2ToReplica1(),
          Replica2ToReplica1() => Conflict('skipped by user'),
          Conflict() => diff.defaultDirection,
          Merge() => diff.defaultDirection,
        };
      });
    }
  }

  String _phaseLabel(AppSyncPhase phase) {
    return switch (phase) {
      AppSyncPhase.idle => 'Ready',
      AppSyncPhase.scanning => 'Scanning...',
      AppSyncPhase.reconciling => 'Reconciling...',
      AppSyncPhase.propagating => 'Propagating...',
      AppSyncPhase.done => 'Done',
      AppSyncPhase.error => 'Error',
    };
  }
}
