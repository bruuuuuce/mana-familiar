import 'package:flutter/material.dart';

import '../application/artifact_renderer.dart';
import '../application/mana_inspect.dart';

/// Composes stable artifact chrome around a renderer-selected payload view.
/// All content is rendered as inert Flutter text; this view never creates a
/// WebView, opens links, or executes producer-provided instructions.
class ArtifactDetailView extends StatelessWidget {
  const ArtifactDetailView({
    super.key,
    required this.artifact,
    this.detail,
    this.loading = false,
    this.error,
    this.registry,
  });

  final ManaInspectArtifactSummary artifact;
  final ManaInspectArtifactDetail? detail;
  final bool loading;
  final Object? error;
  final ArtifactRendererRegistry? registry;

  @override
  Widget build(BuildContext context) {
    final loadedDetail = detail;
    final rendererRegistry = registry ?? ArtifactRendererRegistry.standard();
    final renderContext = loadedDetail == null
        ? null
        : ArtifactRenderContext.fromDetail(loadedDetail);
    final plan = renderContext == null
        ? null
        : rendererRegistry.render(renderContext);
    final relations = renderContext == null
        ? const <RelationPreview>[]
        : boundedRelationPreviews(
            renderContext.relations,
            rootArtifactId: artifact.id,
          );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Artifact detail',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        _summary(context),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (error != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Artifact details are unavailable'),
              subtitle: Text('$error'),
            ),
          ),
        if (plan != null) ...[
          _warnings(loadedDetail!),
          _payload(context, plan),
          _relations(relations),
          _sourceAnchors(loadedDetail),
          _provenance(loadedDetail),
        ],
        if (!loading && plan == null && error == null)
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Artifact payload was not requested'),
              subtitle: Text(
                'The summary remains available without interpreting raw paths.',
              ),
            ),
          ),
      ],
    );
  }

  Widget _summary(BuildContext context) => Card(
    child: ListTile(
      title: Text(artifact.id),
      subtitle: Text(
        '${artifact.family} • ${artifact.kind} • ${artifact.status}',
      ),
      trailing: const Icon(Icons.inventory_2_outlined),
    ),
  );

  Widget _warnings(ManaInspectArtifactDetail detail) {
    final messages = <String>[];
    for (final key in ['warnings', 'diagnostics', 'parse_warnings']) {
      final values = detail.raw[key];
      if (values is List) {
        messages.addAll(
          values
              .map(
                (item) =>
                    item is Map ? item['message']?.toString() : item.toString(),
              )
              .whereType<String>(),
        );
      }
    }
    if (messages.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.warning_amber_outlined),
        title: const Text('Compatibility or parse warnings'),
        subtitle: Text(messages.take(3).join('\n')),
      ),
    );
  }

  Widget _payload(BuildContext context, ArtifactRenderPlan plan) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payload', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(plan.reason),
          const SizedBox(height: 10),
          switch (plan.view) {
            ArtifactPayloadView.journey => const _JourneyArtifactModule(),
            ArtifactPayloadView.json ||
            ArtifactPayloadView.text ||
            ArtifactPayloadView.markdown => SelectableText(plan.text ?? ''),
            ArtifactPayloadView.metadata => const Text(
              'Metadata only; payload content is not displayed.',
            ),
          },
        ],
      ),
    ),
  );

  Widget _relations(List<RelationPreview> relations) {
    if (relations.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Column(
        children: [
          const ListTile(title: Text('Related artifacts')),
          ...relations.map(
            (relation) => ListTile(
              leading: Icon(
                relation.cycle ? Icons.loop : Icons.account_tree_outlined,
              ),
              title: Text(relation.id),
              subtitle: Text(
                relation.cycle
                    ? '${relation.kind} • cycle not expanded'
                    : relation.kind,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceAnchors(ManaInspectArtifactDetail detail) {
    final anchors = detail.raw['source_anchors'] ?? detail.raw['anchors'];
    if (anchors is! List || anchors.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.source_outlined),
        title: const Text('Source anchors'),
        subtitle: Text(
          '${anchors.length} producer-provided anchors (navigation is available in a later source phase).',
        ),
      ),
    );
  }

  Widget _provenance(ManaInspectArtifactDetail detail) {
    final provenance = detail.raw['provenance'];
    if (provenance == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.verified_outlined),
        title: const Text('Provenance'),
        subtitle: Text(
          provenance is String
              ? provenance
              : 'Producer-provided provenance metadata',
        ),
      ),
    );
  }
}

/// Registry entry for Journey artifacts. Existing direct Journey exploration is
/// deliberately retained; richer in-shell navigation is scheduled for F08.
class _JourneyArtifactModule extends StatelessWidget {
  const _JourneyArtifactModule();

  @override
  Widget build(BuildContext context) => const Text(
    'Journey renderer module registered. Use Knowledge for the existing Journey explorer.',
  );
}
