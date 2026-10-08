import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/mana_knowledge.dart';
import 'artifact_detail_view.dart';

enum _ReaderMode { reader, source }

class KnowledgeDocumentReader extends StatefulWidget {
  const KnowledgeDocumentReader({
    super.key,
    required this.document,
    this.initialPassageId,
    this.extraPassage,
    this.onEdit,
    this.onOpenReference,
  });

  final ManaKnowledgeDocument document;
  final String? initialPassageId;
  final ManaKnowledgePassage? extraPassage;
  final VoidCallback? onEdit;
  final ValueChanged<String>? onOpenReference;

  @override
  State<KnowledgeDocumentReader> createState() =>
      _KnowledgeDocumentReaderState();
}

class _KnowledgeDocumentReaderState extends State<KnowledgeDocumentReader> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  var _mode = _ReaderMode.reader;

  late List<ManaKnowledgePassage> _passages;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant KnowledgeDocumentReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document ||
        oldWidget.initialPassageId != widget.initialPassageId ||
        oldWidget.extraPassage != widget.extraPassage) {
      _prepare();
    }
  }

  void _prepare() {
    _passages = [
      ?widget.extraPassage,
      ...widget.document.passages.where((p) => p.id != widget.extraPassage?.id),
    ];
    _keys
      ..clear()
      ..addEntries(_passages.map((p) => MapEntry(p.id, GlobalKey())));
    _mode = _ReaderMode.reader;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.initialPassageId != null) {
        _showPassage(widget.initialPassageId!);
      }
    });
  }

  void _showPassage(String id) {
    final target = _keys[id]?.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target, alignment: .02);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Map<String, ManaKnowledgePassage> get _sections {
    final result = <String, ManaKnowledgePassage>{};
    for (final passage in _passages) {
      if (passage.headingPath.isNotEmpty) {
        result.putIfAbsent(passage.headingPath.join(' › '), () => passage);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            document.summary.title ?? document.summary.reference,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${document.summary.scope} · ${document.summary.lifecycle}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              SegmentedButton<_ReaderMode>(
                segments: const [
                  ButtonSegment(
                    value: _ReaderMode.reader,
                    label: Text('Reader'),
                  ),
                  ButtonSegment(
                    value: _ReaderMode.source,
                    label: Text('Source'),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (values) =>
                    setState(() => _mode = values.first),
              ),
              if (document.editable && widget.onEdit != null)
                FilledButton.tonalIcon(
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(
                    document.summary.scope == 'user'
                        ? 'Edit external source'
                        : 'Edit with revision check',
                  ),
                ),
            ],
          ),
          ExpansionTile(
            key: const Key('knowledge-document-provenance'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Source and revision'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  [
                    document.summary.reference,
                    'Document revision: ${document.summary.revision}',
                    if (document.sourceDisclosure != null)
                      'External source: ${document.sourceDisclosure}',
                  ].join('\n'),
                ),
              ),
            ],
          ),
          if (document.truncated)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Document preview is limited by Mana. Search can open a matching passage beyond this excerpt.',
              ),
            ),
          if (_mode == _ReaderMode.reader && _sections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                key: ValueKey(
                  'knowledge-outline-${document.summary.id}-${widget.initialPassageId}',
                ),
                initialValue:
                    _sections.values.any((p) => p.id == widget.initialPassageId)
                    ? widget.initialPassageId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'On this page',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: _sections.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.value.id,
                        child: Text(entry.key, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id != null) _showPassage(id);
                },
              ),
            ),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                child: SelectionArea(
                  child: _mode == _ReaderMode.source
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (document.exactContent == null)
                              const Text(
                                'Exact source is unavailable. This is the producer passage excerpt.',
                              ),
                            SelectableText(
                              document.exactContent ??
                                  document.passages
                                      .map((p) => p.body)
                                      .join('\n\n'),
                              key: const Key('knowledge-source'),
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_passages.isEmpty)
                              const Text(
                                'No readable passages reported by Mana.',
                              ),
                            for (
                              var index = 0;
                              index < _passages.length;
                              index++
                            )
                              _passage(_passages[index], index),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passage(ManaKnowledgePassage passage, int previous) {
    final match = passage.id == widget.initialPassageId;
    final showHeading =
        passage.headingPath.isNotEmpty &&
        !(passage.headingPath.length == 1 &&
            passage.headingPath.single == widget.document.summary.title) &&
        (previous == 0 ||
            _passages[previous - 1].headingPath.join('/') !=
                passage.headingPath.join('/'));
    final prose = passage.body.replaceAll(
      RegExp(r'^```[^\n]*\n[\s\S]*?^```\s*$', multiLine: true),
      '',
    );
    final links = RegExp(
      r'(?<!!)\[([^\]]+)\]\(([^)\s]+)\)',
    ).allMatches(prose).toList();
    return Container(
      key: _keys[passage.id],
      margin: const EdgeInsets.only(bottom: 16),
      padding: match ? const EdgeInsets.all(12) : EdgeInsets.zero,
      decoration: match
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (match)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Search match', key: Key('knowledge-search-match')),
            ),
          if (passage == widget.extraPassage)
            const Text('Matched passage outside the document preview'),
          if (showHeading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                passage.headingPath.join(' › '),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          MarkdownPassageView(markdown: passage.body),
          if (passage.truncated) const Text('This passage is truncated.'),
          if (links.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final link in links) _link(link.group(1)!, link.group(2)!),
              ],
            ),
        ],
      ),
    );
  }

  Widget _link(String label, String target) {
    final uri = Uri.tryParse(target);
    if (uri == null) return const SizedBox.shrink();
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return TextButton.icon(
        icon: const Icon(Icons.copy_outlined, size: 16),
        label: Text('Copy link: $label'),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: target));
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Link copied')));
          }
        },
      );
    }
    if (uri.hasScheme || uri.hasAuthority) return const SizedBox.shrink();
    return TextButton.icon(
      icon: const Icon(Icons.arrow_forward, size: 16),
      label: Text(label),
      onPressed: () {
        if (target.startsWith('#')) {
          final fragment = Uri.decodeComponent(target.substring(1));
          for (final entry in _sections.entries) {
            final heading = entry.value.headingPath.last
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
                .trim()
                .replaceAll(RegExp(r'\s+'), '-');
            if (heading == fragment) {
              _showPassage(entry.value.id);
              return;
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This section is outside the loaded preview.'),
            ),
          );
        } else {
          widget.onOpenReference?.call(target);
        }
      },
    );
  }
}
