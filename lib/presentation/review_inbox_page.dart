import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/mana_inspect.dart';
import '../application/review_inbox_model.dart';

/// Read-only attention queue. It only copies a producer-documented command;
/// no command is started from this client.
class ReviewInboxPage extends StatefulWidget {
  const ReviewInboxPage({
    super.key,
    required this.artifacts,
    required this.onOpenArtifact,
  });

  final List<ManaInspectArtifactSummary> artifacts;
  final ValueChanged<ManaInspectArtifactSummary> onOpenArtifact;

  @override
  State<ReviewInboxPage> createState() => _ReviewInboxPageState();
}

class _ReviewInboxPageState extends State<ReviewInboxPage> {
  var _filter = ReviewInboxFilter.all;

  @override
  Widget build(BuildContext context) {
    final model = ReviewInboxModel.fromCatalog(
      ManaInspectCatalog(artifacts: widget.artifacts, raw: const {}),
    );
    final items = model.filtered(_filter);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Review Inbox', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text(
          'Mana Familiar observes and hands off. Mana performs governed actions; this view never executes a command.',
        ),
        const SizedBox(height: 12),
        DropdownButton<ReviewInboxFilter>(
          value: _filter,
          onChanged: (value) {
            if (value != null) setState(() => _filter = value);
          },
          items: ReviewInboxFilter.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_filterLabel(value)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text(
                'No matching human attention is currently reported by Mana.',
              ),
            ),
          ),
        ...items.map(_itemCard),
      ],
    );
  }

  Widget _itemCard(ReviewInboxItem item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_priorityIcon(item.priority)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(label: Text(_priorityLabel(item.priority))),
            ],
          ),
          const SizedBox(height: 8),
          Text(item.reason),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(item.artifact.id),
            subtitle: Text(
              '${item.artifact.kind} • ${item.artifact.status} • ${item.updatedAt == null ? 'age not recorded by Mana' : 'updated ${item.updatedAt}'}',
            ),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => widget.onOpenArtifact(item.artifact),
          ),
          if (item.owner != null) Text('Owner: ${item.owner}'),
          if (item.approvalRequirement != null)
            Text('Approval: ${item.approvalRequirement}'),
          if (item.relatedReferences.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Related source/evidence: ${item.relatedReferences.join(', ')}',
            ),
          ],
          const SizedBox(height: 8),
          Text('Next step: ${item.nextStep}'),
          const SizedBox(height: 8),
          if (item.command case final command?)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                SelectableText(
                  command.shellDisplay,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copy(command),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy command'),
                ),
              ],
            )
          else
            const Text(
              'Command unavailable: required action metadata is absent.',
            ),
        ],
      ),
    ),
  );

  Future<void> _copy(ManaCliHandoff command) async {
    await Clipboard.setData(ClipboardData(text: command.shellDisplay));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mana command copied; it has not been run.'),
        ),
      );
    }
  }

  String _filterLabel(ReviewInboxFilter filter) => switch (filter) {
    ReviewInboxFilter.all => 'All attention',
    ReviewInboxFilter.blockers => 'Blockers',
    ReviewInboxFilter.pending => 'Pending',
    ReviewInboxFilter.warnings => 'Warnings',
    ReviewInboxFilter.unknown => 'Unknown',
  };

  String _priorityLabel(ReviewInboxPriority priority) => switch (priority) {
    ReviewInboxPriority.blocker => 'Blocker',
    ReviewInboxPriority.pending => 'Pending',
    ReviewInboxPriority.warning => 'Warning',
    ReviewInboxPriority.unknown => 'Unknown',
  };

  IconData _priorityIcon(ReviewInboxPriority priority) => switch (priority) {
    ReviewInboxPriority.blocker => Icons.error_outline,
    ReviewInboxPriority.pending => Icons.pending_actions_outlined,
    ReviewInboxPriority.warning => Icons.warning_amber_outlined,
    ReviewInboxPriority.unknown => Icons.help_outline,
  };
}
