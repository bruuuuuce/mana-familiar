import 'package:flutter/material.dart';

import '../investigation_inspector.dart';
import '../journey_graph.dart';
import '../journey_reading.dart';
import '../source_workspace.dart';
import 'artifact_detail_view.dart';

/// A reading surface over existing producer records. Questions, learning
/// outcomes and conclusions are never generated from topology alone.
class JourneyReadingView extends StatelessWidget {
  const JourneyReadingView({
    super.key,
    required this.graph,
    required this.nodeId,
    required this.projectRoot,
    required this.progress,
    required this.source,
    required this.onNavigate,
    required this.onOpenSource,
    required this.onStatus,
    required this.onNote,
    required this.onReview,
    required this.onEvidence,
    required this.onAcknowledgeChange,
  });

  final JourneyGraph graph;
  final String nodeId;
  final String projectRoot;
  final JourneyReadingProgress progress;
  final ResolvedSource? source;
  final ValueChanged<String> onNavigate;
  final VoidCallback onOpenSource;
  final ValueChanged<JourneyReadingStatus> onStatus;
  final VoidCallback onNote;
  final VoidCallback onReview;
  final ValueChanged<InspectorEvidence> onEvidence;
  final VoidCallback onAcknowledgeChange;

  @override
  Widget build(BuildContext context) {
    final node = graph.node(nodeId)!;
    final inspector = InvestigationInspectorModel.build(
      graph: graph,
      nodeId: nodeId,
      projectRoot: projectRoot,
    );
    final path = graph.logicalPathFor(nodeId);
    final marked = progress.markers.values
        .where(
          (status) =>
              status == JourneyReadingStatus.read ||
              status == JourneyReadingStatus.clear,
        )
        .length;
    final revisit = progress.markers.values
        .where((status) => status == JourneyReadingStatus.revisit)
        .length;
    final explanations = graph.readableExplanations
        .where((item) => item['subject_node_id'] == nodeId)
        .toList();
    return SingleChildScrollView(
      key: ValueKey('reading-$nodeId'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '$marked marked read · $revisit to review · ${graph.nodes.length} known steps',
                  ),
                  TextButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.summarize_outlined),
                    label: const Text('Reading summary'),
                  ),
                ],
              ),
              const Text(
                'Personal markers describe your reading, not verified understanding.',
              ),
              if (progress.changed) ...[
                const SizedBox(height: 12),
                const Text(
                  'This Journey changed. Previous reading markers now need review; your notes have been kept.',
                ),
                TextButton(
                  onPressed: onAcknowledgeChange,
                  child: const Text('Dismiss change notice'),
                ),
              ],
              const SizedBox(height: 12),
              _scope(context),
              const SizedBox(height: 24),
              Text(
                'CURRENT STEP',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Text(
                node['label'] as String? ?? nodeId,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                path.map((id) => graph.node(id)?['label'] ?? id).join(' → '),
              ),
              const SizedBox(height: 20),
              _heading(context, 'Explanation'),
              if (explanations.isEmpty)
                const Text(
                  'No explanation is recorded for this step. Read the linked evidence or source; a connection in the graph does not establish why the code was designed this way.',
                )
              else
                ...explanations.map(
                  (explanation) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Support: ${explanation['epistemic_status'] ?? 'not reported'}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        MarkdownPassageView(
                          markdown: explanation['body'] as String,
                        ),
                        if ((explanation['evidence_ids'] as List? ?? const [])
                            .isEmpty)
                          const Text(
                            'No evidence references are attached to this explanation.',
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              _heading(context, 'Evidence'),
              if (inspector.evidence.isEmpty)
                const Text('No evidence is linked to this step.')
              else
                ...inspector.evidence.map(
                  (evidence) => Card(
                    child: ListTile(
                      title: Text(evidence.summary),
                      onTap: evidence.location == null
                          ? null
                          : () => onEvidence(evidence),
                      trailing: evidence.location == null
                          ? null
                          : const Icon(Icons.code),
                      subtitle: Text(
                        [
                          evidence.kind,
                          if (evidence.relationship != null)
                            evidence.relationship!,
                          if (evidence.location != null)
                            evidence.location!.reference,
                        ].join(' · '),
                      ),
                    ),
                  ),
                ),
              if (graph.anchorsFor(nodeId).isNotEmpty) ...[
                const SizedBox(height: 16),
                _heading(context, 'Source excerpt'),
                if (source == null)
                  const Text('Loading the recorded source…')
                else ...[
                  Text('${source!.location.reference} · ${source!.status}'),
                  if (source!.available)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: SelectableText(
                        _excerpt(source!),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
                TextButton.icon(
                  onPressed: onOpenSource,
                  icon: const Icon(Icons.code),
                  label: const Text('Open source workspace'),
                ),
              ],
              if (inspector.hypotheses.isNotEmpty) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Hypotheses and checks (${inspector.hypotheses.length})',
                  ),
                  children: inspector.hypotheses
                      .map(
                        (hypothesis) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hypothesis['claim'] as String? ??
                                    'No claim recorded',
                              ),
                              Text(
                                'Confidence: ${hypothesis['confidence'] ?? 'not reported'}',
                              ),
                              ...((hypothesis['verification_suggestions']
                                              as List? ??
                                          const [])
                                      .whereType<String>())
                                  .map((text) => Text('Check: $text')),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 24),
              _heading(context, 'Your reading'),
              DropdownButton<JourneyReadingStatus>(
                key: const ValueKey('reading-status'),
                value: progress.statusFor(nodeId),
                items: JourneyReadingStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(status.label),
                      ),
                    )
                    .toList(),
                onChanged: (status) {
                  if (status != null) onStatus(status);
                },
              ),
              if (progress.notes[nodeId] case final note?) SelectableText(note),
              TextButton.icon(
                onPressed: onNote,
                icon: const Icon(Icons.edit_note),
                label: Text(
                  progress.notes.containsKey(nodeId)
                      ? 'Edit personal note'
                      : 'Add personal note',
                ),
              ),
              const SizedBox(height: 24),
              _heading(context, 'Continue the path'),
              if (inspector.primary.isEmpty)
                Text(
                  inspector.isTerminal
                      ? 'End of this branch. Review your notes and open questions before choosing another path.'
                      : 'No primary continuation is recorded. Optional branches are available below.',
                ),
              if (inspector.primary.length > 1)
                const Text(
                  'This step has several primary continuations. Choose the branch you want to examine.',
                ),
              ...inspector.primary.map((relation) => _next(context, relation)),
              if (inspector.isTerminal)
                OutlinedButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.summarize_outlined),
                  label: const Text('Review this journey'),
                ),
              if (inspector.alternatives.isNotEmpty ||
                  inspector.deferred.isNotEmpty ||
                  inspector.related.isNotEmpty) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Optional branches and related steps'),
                  children: [
                    for (final entry in {
                      'Alternative': inspector.alternatives,
                      'Deferred': inspector.deferred,
                      'Related': inspector.related,
                    }.entries)
                      for (final relation in entry.value)
                        ListTile(
                          title: Text(relation.label),
                          subtitle: Text(
                            '${entry.key} · ${relation.kind}${relation.edge['rationale'] is String ? '\n${relation.edge['rationale']}' : ''}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => onNavigate(relation.targetId),
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  Widget _scope(BuildContext context) {
    final journey = graph.raw['journey'] as Map<String, dynamic>;
    final scope = journey['scope'] as Map<String, dynamic>?;
    final start = scope?['start'] as Map<String, dynamic>?;
    final termination = scope?['termination'] as Map<String, dynamic>?;
    return Card(
      child: ExpansionTile(
        title: const Text('About this journey'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Start: ${start?['value'] ?? 'not reported'}'),
          Text(
            'Stop condition: ${termination?['condition'] ?? 'not reported'}',
          ),
          if (scope?['boundaries'] case final Map boundaries)
            ...boundaries.entries.map(
              (entry) => Text('${entry.key}: ${entry.value}'),
            ),
          Text(
            'Source revision: ${journey['repository_revision'] ?? 'not reported'}',
          ),
          const SizedBox(height: 8),
          const Text(
            'This format reports exploration scope. Learning objectives and prerequisites are not supplied.',
          ),
        ],
      ),
    );
  }

  Widget _next(BuildContext context, InspectorRelation relation) => Card(
    child: ListTile(
      title: Text('Continue to ${relation.label}'),
      subtitle: Text(
        relation.edge['rationale'] as String? ??
            'Recorded connection: ${relation.kind}',
      ),
      trailing: const Icon(Icons.arrow_forward),
      onTap: () => onNavigate(relation.targetId),
    ),
  );

  String _excerpt(ResolvedSource source) {
    final lines = source.contents!.split('\n');
    final start = (source.location.startLine - 1).clamp(0, lines.length);
    final end = source.location.endLine.clamp(start, lines.length);
    final excerpt = lines.sublist(start, end);
    final text = excerpt
        .take(24)
        .map((line) => line.length > 300 ? '${line.substring(0, 300)}…' : line)
        .join('\n');
    return '$text${excerpt.length > 24 ? '\n… Open source workspace for the full range.' : ''}';
  }
}

class JourneyReadingSummary extends StatefulWidget {
  const JourneyReadingSummary({
    super.key,
    required this.graph,
    required this.progress,
  });

  final JourneyGraph graph;
  final JourneyReadingProgress progress;

  @override
  State<JourneyReadingSummary> createState() => _JourneyReadingSummaryState();
}

class _JourneyReadingSummaryState extends State<JourneyReadingSummary> {
  String filter = 'all';

  @override
  Widget build(BuildContext context) {
    final graph = widget.graph;
    final progress = widget.progress;
    final nodes = graph.nodes.where((node) {
      final id = node['id'] as String;
      return switch (filter) {
        'review' => progress.statusFor(id) == JourneyReadingStatus.revisit,
        'notes' => progress.notes.containsKey(id),
        _ => true,
      };
    }).toList();
    final explained = graph.explainedNodeIds;
    return AlertDialog(
      title: const Text('Your journey reading summary'),
      content: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(graph.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '${graph.nodes.where((node) => !explained.contains(node['id'])).length} steps have no recorded explanation.',
            ),
            const Text(
              'Reading markers and notes are personal. Reaching the end of a branch does not verify understanding.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const {
                  'all': 'All steps',
                  'review': 'Needs review',
                  'notes': 'With notes',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: filter == entry.key,
                    onSelected: (_) => setState(() => filter = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: nodes.isEmpty
                  ? const Center(child: Text('No steps match this filter.'))
                  : ListView.builder(
                      itemCount: nodes.length,
                      itemBuilder: (context, index) {
                        final node = nodes[index];
                        final id = node['id'] as String;
                        return ListTile(
                          title: Text(node['label'] as String? ?? id),
                          subtitle: Text(
                            [
                              progress.statusFor(id).label,
                              ?progress.notes[id],
                              if (!explained.contains(id))
                                'No explanation recorded',
                            ].join('\n'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class JourneyReadingNoteDialog extends StatefulWidget {
  const JourneyReadingNoteDialog({super.key, required this.initialNote});

  final String initialNote;

  @override
  State<JourneyReadingNoteDialog> createState() =>
      _JourneyReadingNoteDialogState();
}

class _JourneyReadingNoteDialogState extends State<JourneyReadingNoteDialog> {
  late final controller = TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Personal reading note'),
    content: SizedBox(
      width: 520,
      child: TextField(
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        maxLength: 4000,
        decoration: const InputDecoration(
          labelText: 'What is clear, uncertain, or worth checking?',
          helperText: 'Saved in Familiar, separate from Mana evidence.',
          helperMaxLines: 2,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('Save note'),
      ),
    ],
  );
}
