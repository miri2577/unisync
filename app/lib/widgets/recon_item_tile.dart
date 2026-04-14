import 'package:fluent_ui/fluent_ui.dart';
import 'package:unison_core/unison_core.dart';

class ReconItemTile extends StatelessWidget {
  final ReconItem item;
  final VoidCallback? onToggleDirection;

  const ReconItemTile({
    super.key,
    required this.item,
    this.onToggleDirection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // Left status
          SizedBox(
            width: 80,
            child: Text(
              _leftStatus(),
              style: theme.typography.caption?.copyWith(
                color: _statusColor(context, _leftReplicaStatus()),
              ),
            ),
          ),
          // Direction arrow
          GestureDetector(
            onTap: onToggleDirection,
            child: Container(
              width: 60,
              alignment: Alignment.center,
              child: Text(
                _directionArrow(),
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _directionColor(context),
                ),
              ),
            ),
          ),
          // Right status
          SizedBox(
            width: 80,
            child: Text(
              _rightStatus(),
              style: theme.typography.caption?.copyWith(
                color: _statusColor(context, _rightReplicaStatus()),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // File icon
          Icon(_fileIcon(), size: 16),
          const SizedBox(width: 6),
          // Path
          Expanded(
            child: Text(
              item.path1.toString(),
              style: theme.typography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _directionArrow() {
    return switch (item.replicas) {
      Problem() => '????',
      Different(diff: var d) => switch (d.direction) {
        Replica1ToReplica2() => '---->',
        Replica2ToReplica1() => '<----',
        Conflict() => '<-?->',
        Merge() => '<-M->',
      },
    };
  }

  Color _directionColor(BuildContext context) {
    return switch (item.replicas) {
      Problem() => Colors.red,
      Different(diff: var d) => switch (d.direction) {
        Replica1ToReplica2() => Colors.green,
        Replica2ToReplica1() => Colors.teal,
        Conflict() => Colors.red,
        Merge() => Colors.blue,
      },
    };
  }

  ReplicaStatus? _leftReplicaStatus() {
    if (item.replicas case Different(diff: var d)) {
      return d.rc1.status;
    }
    return null;
  }

  ReplicaStatus? _rightReplicaStatus() {
    if (item.replicas case Different(diff: var d)) {
      return d.rc2.status;
    }
    return null;
  }

  String _leftStatus() => _statusString(_leftReplicaStatus());
  String _rightStatus() => _statusString(_rightReplicaStatus());

  String _statusString(ReplicaStatus? status) {
    return switch (status) {
      ReplicaStatus.created => 'new',
      ReplicaStatus.modified => 'changed',
      ReplicaStatus.deleted => 'deleted',
      ReplicaStatus.propsChanged => 'props',
      ReplicaStatus.unchanged => '',
      null => '',
    };
  }

  Color _statusColor(BuildContext context, ReplicaStatus? status) {
    return switch (status) {
      ReplicaStatus.created => Colors.green,
      ReplicaStatus.modified => Colors.orange,
      ReplicaStatus.deleted => Colors.red,
      ReplicaStatus.propsChanged => Colors.blue,
      _ => FluentTheme.of(context).typography.body?.color ?? Colors.grey,
    };
  }

  IconData _fileIcon() {
    if (item.replicas case Different(diff: var d)) {
      final content = d.direction is Replica1ToReplica2
          ? d.rc1.content
          : d.rc2.content;
      return switch (content) {
        DirContent() => FluentIcons.folder,
        SymlinkContent() => FluentIcons.link,
        Absent() => FluentIcons.delete,
        _ => FluentIcons.page,
      };
    }
    return FluentIcons.warning;
  }
}
