import 'package:flutter/material.dart';

import '../application/mana_inspect.dart';

enum CatalogFocus { review, evidence }

class CatalogFocusView extends StatelessWidget {
  const CatalogFocusView({
    super.key,
    required this.focus,
    required this.artifacts,
    required this.onOpenArtifact,
  });
  final CatalogFocus focus;
  final List<ManaInspectArtifactSummary> artifacts;
  final ValueChanged<ManaInspectArtifactSummary> onOpenArtifact;

  @override
  Widget build(BuildContext context) {
    final selected = artifacts.where(_includes).toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          focus == CatalogFocus.review ? 'Review' : 'Evidence',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          focus == CatalogFocus.review
              ? 'Producer-reported review/readiness artifacts. Human approval remains outside this application.'
              : 'Producer-reported evidence inventory. Inventory never implies complete coverage.',
        ),
        const SizedBox(height: 12),
        if (selected.isEmpty)
          const Card(
            child: ListTile(
              title: Text(
                'No matching catalog artifacts were reported by Mana.',
              ),
            ),
          ),
        ...selected.map(
          (artifact) => Card(
            child: ListTile(
              leading: Icon(_icon(artifact.status)),
              title: Text(artifact.id),
              subtitle: Text(
                '${artifact.family} • ${artifact.kind} • ${artifact.status}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpenArtifact(artifact),
            ),
          ),
        ),
      ],
    );
  }

  bool _includes(ManaInspectArtifactSummary artifact) {
    final values =
        '${artifact.id} ${artifact.kind} ${artifact.family} ${artifact.raw['schema'] ?? ''}'
            .toLowerCase();
    return switch (focus) {
      CatalogFocus.review =>
        values.contains('review') ||
            values.contains('readiness') ||
            values.contains('validation') ||
            values.contains('decision'),
      CatalogFocus.evidence =>
        values.contains('evidence') ||
            values.contains('verification') ||
            values.contains('repair'),
    };
  }

  IconData _icon(String status) => switch (status) {
    'failed' || 'blocked' => Icons.error_outline,
    'stale' || 'missing' || 'partial' => Icons.warning_amber_outlined,
    _ => Icons.description_outlined,
  };
}
