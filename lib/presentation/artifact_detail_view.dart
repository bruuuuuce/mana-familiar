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
            ArtifactPayloadView.text => SelectableText(plan.text ?? ''),
            ArtifactPayloadView.markdown => MarkdownNoteView(
              markdown: plan.text ?? '',
              source: plan.sourceText,
              artifact: artifact,
              detail: detail,
              onOpenRelatedArtifact: onOpenRelatedArtifact,
            ),
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

/// Small, deliberately inert Markdown preview for producer-owned workspace
/// notes. Links, images, and HTML have already been removed by the renderer.
enum MarkdownReaderMode { reader, source, metadata }

class MarkdownNoteView extends StatefulWidget {
  const MarkdownNoteView({
    super.key,
    required this.markdown,
    this.source,
    this.artifact,
    this.detail,
    this.onOpenRelatedArtifact,
  });

  final String markdown;
  final String? source;
  final ManaInspectArtifactSummary? artifact;
  final ManaInspectArtifactDetail? detail;
  final ValueChanged<String>? onOpenRelatedArtifact;

  @override
  State<MarkdownNoteView> createState() => _MarkdownNoteViewState();
}

class _MarkdownNoteViewState extends State<MarkdownNoteView> {
  var _mode = MarkdownReaderMode.reader;

  @override
  Widget build(BuildContext context) {
    final blocks = _MarkdownBlocks.parse(widget.markdown).blocks;
    final headings = blocks.whereType<_MarkdownHeading>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: MarkdownReaderMode.values
              .map(
                (mode) => ChoiceChip(
                  label: Text(switch (mode) {
                    MarkdownReaderMode.reader => 'Reader',
                    MarkdownReaderMode.source => 'Source',
                    MarkdownReaderMode.metadata => 'Metadata',
                  }),
                  selected: _mode == mode,
                  onSelected: (_) => setState(() => _mode = mode),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        if (_mode == MarkdownReaderMode.source)
          SelectableText(
            widget.source ?? widget.markdown,
            key: const Key('markdown-source'),
            style: const TextStyle(fontFamily: 'monospace'),
          )
        else if (_mode == MarkdownReaderMode.metadata)
          _metadata()
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (headings.isNotEmpty)
                SizedBox(
                  width: 180,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('On this page'),
                      ...headings.map(
                        (h) => Padding(
                          padding: EdgeInsets.only(left: (h.level - 1) * 8.0),
                          child: Text('• ${h.value}'),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: SelectionArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: blocks
                            .map((block) => block.build(context))
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _metadata() {
    final artifact = widget.artifact;
    final raw = artifact?.raw ?? const <String, dynamic>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          [
            'Artifact ID: ${artifact?.id ?? 'unavailable'}',
            'Kind/family: ${artifact?.kind ?? 'unavailable'} / ${artifact?.family ?? 'unavailable'}',
            'Path: ${artifact?.path ?? 'unavailable'}',
            'Status: ${artifact?.status ?? 'unknown'}',
            'work_item_id: ${raw['work_item_id'] ?? raw['workspace'] ?? 'unavailable'}',
            'section_id: ${raw['section_id'] ?? 'unavailable'}',
            'revision: ${raw['revision_id'] ?? 'unavailable'}',
            'provenance: ${raw['provenance'] ?? 'unavailable'}',
            'diagnostics: ${widget.detail?.raw['diagnostics'] ?? raw['diagnostic'] ?? 'none'}',
          ].join('\n'),
        ),
      ),
    );
  }
}

class _MarkdownBlocks {
  const _MarkdownBlocks(this.blocks);
  final List<_MarkdownBlock> blocks;

  factory _MarkdownBlocks.parse(String markdown) {
    final lines = markdown.split('\n');
    final blocks = <_MarkdownBlock>[];
    final paragraph = <String>[];
    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(_MarkdownParagraph(paragraph.join(' ')));
      paragraph.clear();
    }

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.startsWith('```')) {
        flushParagraph();
        final language = line.substring(3).trim();
        final code = <String>[];
        while (++index < lines.length && !lines[index].startsWith('```')) {
          code.add(lines[index]);
        }
        blocks.add(_MarkdownCode(language, code.join('\n')));
      } else if (line.trim().isEmpty) {
        flushParagraph();
      } else if (RegExp(r'^#{1,6}\s+').hasMatch(line)) {
        flushParagraph();
        final match = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line)!;
        blocks.add(_MarkdownHeading(match.group(1)!.length, match.group(2)!));
      } else if (RegExp(r'^\s*([-*+])\s+').hasMatch(line) ||
          RegExp(r'^\s*\d+\.\s+').hasMatch(line)) {
        flushParagraph();
        final items = <String>[];
        final ordered = RegExp(r'^\s*\d+\.\s+').hasMatch(line);
        do {
          items.add(line.replaceFirst(RegExp(r'^\s*(?:[-*+]|\d+\.)\s+'), ''));
          if (index + 1 >= lines.length ||
              !(ordered
                  ? RegExp(r'^\s*\d+\.\s+').hasMatch(lines[index + 1])
                  : RegExp(r'^\s*[-*+]\s+').hasMatch(lines[index + 1]))) {
            break;
          }
          index++;
        } while (index < lines.length);
        blocks.add(_MarkdownList(items, ordered));
      } else if (line.startsWith('> ')) {
        flushParagraph();
        blocks.add(_MarkdownQuote(line.substring(2)));
      } else if (RegExp(r'^\s{0,3}([-*_])(?:\s*\1){2,}\s*$').hasMatch(line)) {
        flushParagraph();
        blocks.add(const _MarkdownRule());
      } else if (line.contains('|') &&
          index + 1 < lines.length &&
          RegExp(
            r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$',
          ).hasMatch(lines[index + 1])) {
        flushParagraph();
        final headers = _tableCells(line);
        index++;
        final rows = <List<String>>[];
        while (index + 1 < lines.length && lines[index + 1].contains('|')) {
          rows.add(_tableCells(lines[++index]));
        }
        blocks.add(_MarkdownTable(headers, rows));
      } else {
        paragraph.add(line.trim());
      }
    }
    flushParagraph();
    return _MarkdownBlocks(blocks);
  }

  static List<String> _tableCells(String line) {
    var text = line.trim();
    if (text.startsWith('|')) text = text.substring(1);
    if (text.endsWith('|')) text = text.substring(0, text.length - 1);
    return text.split('|').map((cell) => cell.trim()).toList();
  }
}

abstract class _MarkdownBlock {
  const _MarkdownBlock();
  Widget build(BuildContext context);

  TextSpan inline(String value, TextStyle style) {
    final spans = <InlineSpan>[];
    final expression = RegExp(
      r'(`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*|\[([^\]]+)\]\(([^)]+)\)|<[^>]*>)',
    );
    var cursor = 0;
    for (final match in expression.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('<')) {
        // HTML is deliberately inert and absent from Reader mode.
      } else if (token.startsWith('[')) {
        spans.add(
          TextSpan(
            text: match.group(2)!,
            style: style.copyWith(
              color: Colors.blue,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      } else if (token.startsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: style.copyWith(
              fontFamily: 'monospace',
              backgroundColor: const Color(0x14000000),
            ),
          ),
        );
      } else if (token.startsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: style.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: style.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return TextSpan(style: style, children: spans);
  }

  Widget rich(String value, TextStyle style) => Text.rich(inline(value, style));
}

class _MarkdownHeading extends _MarkdownBlock {
  const _MarkdownHeading(this.level, this.value);
  final int level;
  final String value;
  @override
  Widget build(BuildContext context) {
    final style = switch (level) {
      1 => Theme.of(context).textTheme.headlineSmall,
      2 => Theme.of(context).textTheme.titleLarge,
      _ => Theme.of(context).textTheme.titleMedium,
    }!;
    return Padding(
      padding: EdgeInsets.only(top: level == 1 ? 4 : 20, bottom: 8),
      child: rich(value, style),
    );
  }
}

class _MarkdownParagraph extends _MarkdownBlock {
  const _MarkdownParagraph(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: rich(
      value,
      Theme.of(context).textTheme.bodyLarge!.copyWith(height: 1.5),
    ),
  );
}

class _MarkdownList extends _MarkdownBlock {
  const _MarkdownList(this.items, this.ordered);
  final List<String> items;
  final bool ordered;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < items.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!ordered && RegExp(r'^\[[ xX]\]\s+').hasMatch(items[index]))
                  Checkbox(
                    value:
                        items[index].startsWith('[x]') ||
                        items[index].startsWith('[X]'),
                    onChanged: null,
                  )
                else
                  SizedBox(
                    width: 28,
                    child: Text(ordered ? '${index + 1}.' : '•'),
                  ),
                Expanded(
                  child: rich(
                    items[index].replaceFirst(RegExp(r'^\[[ xX]\]\s+'), ''),
                    Theme.of(
                      context,
                    ).textTheme.bodyLarge!.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _MarkdownCode extends _MarkdownBlock {
  const _MarkdownCode(this.language, this.value);
  final String language;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: SelectableText(
      value,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium!.copyWith(fontFamily: 'monospace', height: 1.4),
    ),
  );
}

class _MarkdownQuote extends _MarkdownBlock {
  const _MarkdownQuote(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.only(left: 12),
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 3,
        ),
      ),
    ),
    child: rich(
      value,
      Theme.of(
        context,
      ).textTheme.bodyLarge!.copyWith(fontStyle: FontStyle.italic),
    ),
  );
}

class _MarkdownRule extends _MarkdownBlock {
  const _MarkdownRule();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 10),
    child: Divider(),
  );
}

class _MarkdownTable extends _MarkdownBlock {
  const _MarkdownTable(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodyMedium!;
    TableRow row(List<String> cells, {required bool header}) => TableRow(
      children: [
        for (var index = 0; index < headers.length; index++)
          Padding(
            padding: const EdgeInsets.all(10),
            child: rich(
              index < cells.length ? cells[index] : '',
              header ? text.copyWith(fontWeight: FontWeight.w700) : text,
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            row(headers, header: true),
            ...rows.map((cells) => row(cells, header: false)),
          ],
        ),
      ),
    );
  }
}
