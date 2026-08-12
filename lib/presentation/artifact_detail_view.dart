import 'package:flutter/material.dart';

import '../application/artifact_renderer.dart';
import '../application/mana_inspect.dart';
import '../application/operational_model.dart';
import '../application/governance_model.dart';
import '../source_workspace.dart';
import 'source_reference_view.dart';

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
    this.onOpenRelatedArtifact,
    this.sourceLoader,
    this.projectRoot,
  });

  final ManaInspectArtifactSummary artifact;
  final ManaInspectArtifactDetail? detail;
  final bool loading;
  final Object? error;
  final ArtifactRendererRegistry? registry;
  final ValueChanged<String>? onOpenRelatedArtifact;
  final Future<ManaInspectSourceRelations> Function(String path)? sourceLoader;
  final String? projectRoot;

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
    final rawPayload = renderContext == null
        ? null
        : const JsonArtifactRenderer().render(
            renderContext,
            const ArtifactRenderLimits(),
          );
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
          _payload(context, plan, loadedDetail),
          _rawPayload(rawPayload),
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

  Widget _payload(
    BuildContext context,
    ArtifactRenderPlan plan,
    ManaInspectArtifactDetail detail,
  ) => Card(
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
            ArtifactPayloadView.verification => _verification(detail),
            ArtifactPayloadView.repair => _repair(detail),
            ArtifactPayloadView.review => _review(detail),
            ArtifactPayloadView.evidence => _evidence(detail),
            ArtifactPayloadView.decision => _decision(detail),
            ArtifactPayloadView.governance => _governance(detail),
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
              onTap: relation.cycle || onOpenRelatedArtifact == null
                  ? null
                  : () => onOpenRelatedArtifact!(relation.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rawPayload(ArtifactRenderPlan? plan) => Card(
    child: ExpansionTile(
      title: const Text('Raw payload (bounded)'),
      subtitle: Text(
        plan?.text == null
            ? plan?.reason ?? 'Unavailable'
            : 'Safe JSON representation',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            plan?.text ?? 'Raw payload is available as metadata only.',
          ),
        ),
      ],
    ),
  );

  Widget _verification(ManaInspectArtifactDetail detail) {
    final model = VerificationViewModel.fromPayload(detail.payload, detail.raw);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Overall result: ${model.result}'),
        const Text(
          'Verification evidence is not an approval or merge decision.',
        ),
        if (model.stale)
          const Text(
            'Stale or non-comparable result — assess against the current baseline.',
          ),
        if (model.trustOrigin != null)
          Text('Trust origin: ${model.trustOrigin}'),
        if (model.effect != null) Text('Effect: ${model.effect}'),
        if (model.limits != null) Text('Limits: ${model.limits}'),
        if (model.checks.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Checks'),
          ...model.checks.map(
            (check) => Text(
              '${check['name'] ?? check['id'] ?? 'check'}: ${check['status'] ?? 'UNKNOWN'}',
            ),
          ),
        ],
        if (model.evidencePaths.isNotEmpty)
          Text('Evidence: ${model.evidencePaths.join(', ')}'),
        if (model.rerunContext != null)
          Text('Rerun context: ${model.rerunContext}'),
      ],
    );
  }

  Widget _repair(ManaInspectArtifactDetail detail) {
    final model = RepairViewModel.fromPayload(detail.payload, detail.raw);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Final result: ${model.finalResult}'),
        const Text('RESOLVED does not mean merge-ready.'),
        if (model.concern != null) Text('Targeted concern: ${model.concern}'),
        if (model.allowedPath != null)
          Text('Allowed path: ${model.allowedPath}'),
        if (model.attemptCount != null) Text('Attempts: ${model.attemptCount}'),
        if (model.candidateStatus != null)
          Text('Candidate/import: ${model.candidateStatus}'),
        if (model.baselineRevalidated != null)
          Text('Live baseline revalidation: ${model.baselineRevalidated}'),
      ],
    );
  }

  Widget _review(ManaInspectArtifactDetail detail) {
    final model = ReviewViewModel.fromPayload(detail.payload, detail.raw);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (model.scope != null) Text('Reviewed scope: ${model.scope}'),
        if (model.base != null) Text('Base: ${model.base}'),
        if (model.pr != null) Text('PR identity: ${model.pr}'),
        const Text(
          'Human approval is required; this view cannot approve, request changes, comment, or merge.',
        ),
        if (model.humanApprovalRequired == null)
          const Text('Approval requirement was not declared by Mana.'),
        if (model.humanApprovalRequired == true)
          const Text('Mana declares human approval required.'),
        if (model.findings.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Findings'),
          ...model.findings.map(
            (finding) => Text(
              '${finding.severity.name}: ${finding.summary}${finding.evidence == null ? '' : ' • evidence: ${finding.evidence}'}${finding.source == null ? '' : ' • ${finding.source}'}',
            ),
          ),
        ],
        if (model.missingEvidence.isNotEmpty)
          Text('Missing evidence/tests: ${model.missingEvidence.join(', ')}'),
        if (model.recommendation != null)
          Text('Recommendation (advisory): ${model.recommendation}'),
      ],
    );
  }

  Widget _evidence(ManaInspectArtifactDetail detail) {
    final model = EvidenceInventoryModel.fromPayload(
      detail.payload,
      detail.raw,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Evidence inventory is not evidence coverage.'),
        if (model.items.isEmpty)
          const Text('No structured evidence entries were provided.'),
        ...model.items.map(
          (item) => Text(
            '${item.status}: ${item.id}${item.summary == null ? '' : ' • ${item.summary}'}',
          ),
        ),
      ],
    );
  }

  Widget _decision(ManaInspectArtifactDetail detail) {
    final model = DecisionViewModel.fromPayload(detail.payload, detail.raw);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (model.state != null) Text('Decision state: ${model.state}'),
        if (model.owner != null) Text('Owner: ${model.owner}'),
        if (model.approval != null)
          Text('Approval requirement/state: ${model.approval}'),
        if (model.rationale != null) Text('Rationale: ${model.rationale}'),
        if (model.alternatives.isNotEmpty)
          Text('Alternatives: ${model.alternatives.join(', ')}'),
        if (model.questions.isNotEmpty)
          Text('Unresolved questions: ${model.questions.join(', ')}'),
        if (model.approval == null)
          const Text('No approval state was declared by Mana.'),
      ],
    );
  }

  Widget _governance(ManaInspectArtifactDetail detail) {
    final model = GovernanceViewModel.fromPayload(detail.payload, detail.raw);
    String fields(Map<String, Object?> values) => values.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(' • ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Governance inventory and coverage do not establish correctness.',
        ),
        if (model.inventory.isNotEmpty)
          Text('Inventory: ${fields(model.inventory)}'),
        if (model.coverage.isNotEmpty)
          Text('Coverage: ${fields(model.coverage)}'),
        if (model.lifecycle.isNotEmpty)
          Text('Lifecycle: ${fields(model.lifecycle)}'),
        if (model.staleCount != null)
          Text('Stale results: ${model.staleCount}'),
        if (model.passEvidence != null)
          Text('Actual pass/fail evidence: ${model.passEvidence}'),
      ],
    );
  }

  Widget _sourceAnchors(ManaInspectArtifactDetail detail) {
    final anchors = detail.raw['source_anchors'] ?? detail.raw['anchors'];
    if (anchors is! List || anchors.isEmpty) return const SizedBox.shrink();
    return Column(
      children: anchors.whereType<Map>().map((raw) {
        final anchor = raw.cast<String, dynamic>();
        final path = anchor['path'];
        if (path is! String || sourceLoader == null) {
          return const SizedBox.shrink();
        }
        return SourceReferenceView(
          location: SourceLocation.fromAnchor(projectRoot ?? '.', anchor),
          sourceLoader: sourceLoader!,
          onOpenArtifact: onOpenRelatedArtifact ?? (_) {},
        );
      }).toList(),
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
