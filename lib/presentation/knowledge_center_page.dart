// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../application/mana_knowledge.dart';
import 'knowledge_document_reader.dart';

enum _KnowledgeView { home, library, learning, journeys }

class KnowledgeCenterPage extends StatefulWidget {
  const KnowledgeCenterPage({
    super.key,
    required this.client,
    this.onReady,
    this.onSettled,
    this.refreshSignal,
    this.contextOverview,
    this.journeysBuilder,
    this.recentDocuments = const [],
    this.onDocumentOpened,
  });
  final ManaKnowledgeClient client;
  final VoidCallback? onReady;
  final ValueChanged<bool>? onSettled;
  final ValueListenable<int>? refreshSignal;
  final Widget? contextOverview;
  final Widget Function()? journeysBuilder;
  final List<ManaKnowledgeDocumentSummary> recentDocuments;
  final Future<void> Function(ManaKnowledgeDocumentSummary document)?
  onDocumentOpened;

  @override
  State<KnowledgeCenterPage> createState() => _KnowledgeCenterPageState();
}

class _KnowledgeCenterPageState extends State<KnowledgeCenterPage> {
  String _scope = 'project';
  String _lifecycle = 'active';
  String _learningFilter = 'all';
  var _view = _KnowledgeView.home;
  late Future<_KnowledgeHome> _home;
  Future<ManaKnowledgeSearch>? _search;
  ManaKnowledgeDocument? _document;
  ManaKnowledgePassage? _extraPassage;
  String? _selectedPassageId;
  Object? _documentError;
  bool _documentLoading = false;
  final _query = TextEditingController();
  final _extraDocuments = <ManaKnowledgeDocumentSummary>[];
  late List<ManaKnowledgeDocumentSummary> _recents;
  int? _nextOffset;
  bool _paging = false;
  Object? _pageError;
  int _generation = 0;
  int _documentRequest = 0;

  @override
  void initState() {
    super.initState();
    _recents = widget.recentDocuments.take(8).toList();
    _home = _load(_generation);
    widget.refreshSignal?.addListener(_reload);
  }

  Future<_KnowledgeHome> _load(int generation) async {
    final scope = _scope;
    final lifecycle = _lifecycle;
    try {
      final home = _KnowledgeHome(
        await widget.client.capabilities(),
        await widget.client.documents(scope: scope, lifecycle: lifecycle),
        await widget.client.learningCandidates(),
      );
      if (mounted && generation == _generation) {
        _nextOffset = home.documents.nextOffset;
        widget.onReady?.call();
        widget.onSettled?.call(true);
      }
      return home;
    } catch (_) {
      if (mounted && generation == _generation) widget.onSettled?.call(false);
      rethrow;
    }
  }

  @override
  void didUpdateWidget(covariant KnowledgeCenterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_reload);
      widget.refreshSignal?.addListener(_reload);
    }
    if (oldWidget.client.projectRoot != widget.client.projectRoot ||
        oldWidget.client.manaRoot != widget.client.manaRoot) {
      _recents = widget.recentDocuments.take(8).toList();
      _scope = 'project';
      _lifecycle = 'active';
      _view = _KnowledgeView.home;
      _query.clear();
      _reload();
    }
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_reload);
    _query.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _generation++;
    _documentRequest++;
    _extraDocuments.clear();
    _nextOffset = null;
    _paging = false;
    _pageError = null;
    _documentLoading = false;
    _document = null;
    _extraPassage = null;
    _selectedPassageId = null;
    _documentError = null;
    _home = _load(_generation);
    _search = _query.text.trim().isEmpty ? null : _searchQuery();
  });

  Future<ManaKnowledgeSearch> _searchQuery() => widget.client.search(
    query: _query.text.trim(),
    scope: _scope,
    lifecycle: _lifecycle,
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Knowledge',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh Knowledge',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('knowledge-search'),
              controller: _query,
              decoration: InputDecoration(
                hintText: 'Find guidance, decisions, or reusable knowledge',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search Knowledge',
                  onPressed: _runSearch,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _runSearch(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final view in _KnowledgeView.values)
                  ChoiceChip(
                    label: Text(switch (view) {
                      _KnowledgeView.home => 'Home',
                      _KnowledgeView.library => 'Library',
                      _KnowledgeView.learning => 'Learning',
                      _KnowledgeView.journeys => 'Journeys',
                    }),
                    selected: _view == view,
                    onSelected: (_) => setState(() => _view = view),
                  ),
              ],
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: _view == _KnowledgeView.journeys
            ? widget.journeysBuilder?.call() ??
                  _message(
                    'Journeys unavailable',
                    'No Journey reader is connected for this project.',
                  )
            : FutureBuilder<_KnowledgeHome>(
                future: _home,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done)
                    return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError)
                    return _message(
                      'Knowledge unavailable',
                      '${snapshot.error}',
                      retry: _reload,
                    );
                  final home = snapshot.requireData;
                  return switch (_view) {
                    _KnowledgeView.home => _dashboard(home),
                    _KnowledgeView.learning => _learning(home),
                    _ => _library(home),
                  };
                },
              ),
      ),
    ],
  );

  Widget _dashboard(_KnowledgeHome home) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Your knowledge workspace',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Find what you need, revisit a source, or review what the project has learned.',
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _shortcut(
            'Browse documents',
            Icons.menu_book_outlined,
            () => setState(() => _view = _KnowledgeView.library),
          ),
          _shortcut(
            'Review learning',
            Icons.lightbulb_outline,
            () => setState(() => _view = _KnowledgeView.learning),
          ),
          if (widget.journeysBuilder != null)
            _shortcut(
              'Explore Journeys',
              Icons.route_outlined,
              () => setState(() => _view = _KnowledgeView.journeys),
            ),
        ],
      ),
      const SizedBox(height: 24),
      _indexStatus(home),
      if (_recents.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text(
          'Continue reading',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final document in _recents) _documentTile(document, null),
      ],
      const SizedBox(height: 24),
      Text('From your library', style: Theme.of(context).textTheme.titleMedium),
      if (home.documents.documents.isEmpty)
        const Text(
          'No documents in this source and state. Try another source in Library.',
        ),
      for (final document
          in home.documents.documents
              .where((d) => !_recents.any((recent) => recent.id == d.id))
              .take(5))
        _documentTile(document, home.documents.index.revision),
      if (widget.contextOverview != null) ...[
        const SizedBox(height: 24),
        Text(
          'Project categories',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        widget.contextOverview!,
      ],
      const SizedBox(height: 24),
      Text(
        'Learning review queue',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (home.queue.candidates.isEmpty)
        const Text('No candidates reported by Mana.'),
      for (final candidate in home.queue.candidates.take(3))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(candidate.proposal ?? candidate.id),
          subtitle: Text('${candidate.sourceScope} · ${candidate.status}'),
          trailing: const Icon(Icons.rate_review_outlined),
          onTap: () => _candidate(candidate),
        ),
      const SizedBox(height: 16),
      if (home.capabilities.effectiveContextStatus == 'unavailable')
        const Text(
          'These are available sources. Mana has not reported which material was used by a particular run.',
        ),
    ],
  );

  Widget _shortcut(String label, IconData icon, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      );

  Widget _indexStatus(_KnowledgeHome home) => Text(
    home.capabilities.index.freshness == 'current'
        ? 'Sources are up to date'
        : 'Sources ${home.capabilities.index.freshness}${home.capabilities.index.reason == null ? '' : ' · ${home.capabilities.index.reason}'}',
    style: Theme.of(context).textTheme.bodySmall,
  );

  Widget _library(_KnowledgeHome home) => LayoutBuilder(
    builder: (context, constraints) {
      final showReader =
          _document != null || _documentLoading || _documentError != null;
      if (constraints.maxWidth < 760) {
        if (!showReader) return _libraryList(home);
        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _documentRequest++;
                  _document = null;
                  _documentError = null;
                  _documentLoading = false;
                }),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to library'),
              ),
            ),
            Expanded(child: _content(home)),
          ],
        );
      }
      return Row(
        children: [
          SizedBox(width: 320, child: _libraryList(home)),
          const VerticalDivider(width: 1),
          Expanded(child: _content(home)),
        ],
      );
    },
  );

  List<ManaKnowledgeDocumentSummary> _documents(_KnowledgeHome home) => [
    ...home.documents.documents,
    ..._extraDocuments,
  ];

  Widget _libraryList(_KnowledgeHome home) => ListView(
    key: const Key('knowledge-library-list'),
    padding: const EdgeInsets.all(20),
    children: [
      _indexStatus(home),
      const SizedBox(height: 12),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final scope in [
            'all',
            ...home.capabilities.scopes
                .where((value) => value.scope != 'candidate')
                .map((value) => value.scope),
          ])
            ChoiceChip(
              label: Text(scope == 'all' ? 'All sources' : _label(scope)),
              selected: _scope == scope,
              onSelected: (_) {
                _scope = scope;
                _reload();
              },
            ),
        ],
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey('knowledge-lifecycle-$_lifecycle'),
        initialValue: _lifecycle,
        decoration: const InputDecoration(labelText: 'State', isDense: true),
        items: const [
          DropdownMenuItem(value: 'active', child: Text('Active')),
          DropdownMenuItem(value: 'archived', child: Text('Archived')),
          DropdownMenuItem(value: 'superseded', child: Text('Superseded')),
          DropdownMenuItem(value: 'all', child: Text('All states')),
        ],
        onChanged: (value) {
          if (value != null) {
            _lifecycle = value;
            _reload();
          }
        },
      ),
      for (final scope in home.capabilities.scopes.where(
        (scope) =>
            scope.scope != 'candidate' &&
            scope.health != 'current' &&
            (_scope == 'all' || _scope == scope.scope),
      ))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${_label(scope.scope)}: ${scope.health}${scope.reason == null ? '' : ' · ${scope.reason}'}',
          ),
        ),
      const SizedBox(height: 16),
      if (_search case final search?) ...[
        Row(
          children: [
            const Expanded(child: Text('Search results')),
            TextButton(
              onPressed: () => setState(() {
                _query.clear();
                _search = null;
              }),
              child: const Text('Clear'),
            ),
          ],
        ),
        FutureBuilder<ManaKnowledgeSearch>(
          future: search,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done)
              return const LinearProgressIndicator();
            if (snapshot.hasError) return Text('${snapshot.error}');
            final results = snapshot.requireData;
            if (results.results.isEmpty)
              return const Text(
                'No matching passages. Try a different query or source.',
              );
            return Column(
              children: [
                for (final result in results.results)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    key: ValueKey('knowledge-result-${result.passageId}'),
                    title: Text(result.title ?? result.reference),
                    subtitle: Text(
                      [
                        '${result.scope} · ${result.lifecycle}',
                        if (result.headingPath.isNotEmpty)
                          result.headingPath.join(' › '),
                        result.snippet ?? 'Metadata only',
                      ].join('\n'),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _openDocument(
                      result.documentId,
                      results.index.revision,
                      result: result,
                    ),
                  ),
              ],
            );
          },
        ),
      ] else ...[
        Text(
          '${_documents(home).length}${_nextOffset == null ? '' : '+'} loaded documents',
        ),
        if (_documents(home).isEmpty)
          const Text('No documents in this source and state.'),
        for (final document in _documents(home))
          _documentTile(document, home.documents.index.revision),
        if (_pageError != null)
          Text('Could not load more documents: $_pageError'),
        if (_nextOffset != null)
          TextButton.icon(
            onPressed: _paging ? null : () => _loadMore(home),
            icon: _paging
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more),
            label: const Text('Load more documents'),
          ),
      ],
    ],
  );

  Widget _documentTile(
    ManaKnowledgeDocumentSummary document,
    String? revision,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    selected: _document?.summary.id == document.id,
    title: Text(document.title ?? document.reference),
    subtitle: Text('${document.scope} · ${document.lifecycle}'),
    onTap: () => _openDocument(document.id, revision),
  );

  Future<void> _loadMore(_KnowledgeHome home) async {
    final offset = _nextOffset;
    if (offset == null || _paging) return;
    final generation = _generation;
    final scope = _scope;
    final lifecycle = _lifecycle;
    setState(() {
      _paging = true;
      _pageError = null;
    });
    try {
      final page = await widget.client.documents(
        scope: scope,
        lifecycle: lifecycle,
        offset: offset,
      );
      if (!mounted || generation != _generation) return;
      if (page.index.revision != home.documents.index.revision)
        throw const ManaKnowledgeException(
          'The index changed. Refresh the library before continuing.',
        );
      if (page.nextOffset != null && page.nextOffset! <= offset)
        throw const ManaKnowledgeException(
          'Mana returned a non-advancing page cursor.',
        );
      final known = _documents(home).map((d) => d.id).toSet();
      setState(() {
        _extraDocuments.addAll(page.documents.where((d) => known.add(d.id)));
        _nextOffset = page.nextOffset;
      });
    } catch (error) {
      if (mounted && generation == _generation)
        setState(() => _pageError = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _paging = false);
    }
  }

  Widget _content(_KnowledgeHome home) {
    if (_documentLoading)
      return const Center(child: CircularProgressIndicator());
    if (_documentError != null)
      return _message('Document unavailable', '$_documentError');
    final document = _document;
    if (document == null)
      return _message(
        'Find a document',
        'Browse the library or search for a passage. Choose a source and state to narrow the results.',
      );
    return KnowledgeDocumentReader(
      key: ValueKey(document.summary.id),
      document: document,
      initialPassageId: _selectedPassageId,
      extraPassage: _extraPassage,
      onEdit: document.editable ? () => _edit(document) : null,
      onOpenReference: (target) {
        final uri = Uri.tryParse(target);
        if (uri == null || uri.hasScheme || uri.hasAuthority) return;
        final reference = Uri.parse(
          document.summary.reference,
        ).resolveUri(uri).path;
        final linked = _documents(home)
            .where(
              (d) =>
                  d.reference == reference && d.scope == document.summary.scope,
            )
            .firstOrNull;
        if (linked == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This source is not in the loaded library. Search for it or load more documents.',
              ),
            ),
          );
          return;
        }
        _openDocument(linked.id, home.documents.index.revision);
      },
    );
  }

  void _runSearch() {
    final query = _query.text.trim();
    setState(() {
      _view = _KnowledgeView.library;
      _documentRequest++;
      _document = null;
      _documentLoading = false;
      _documentError = null;
      _search = query.isEmpty ? null : _searchQuery();
    });
  }

  Future<void> _openDocument(
    String id,
    String? revision, {
    ManaKnowledgeSearchResult? result,
  }) async {
    final request = ++_documentRequest;
    setState(() {
      _view = _KnowledgeView.library;
      _documentLoading = true;
      _documentError = null;
    });
    try {
      final response = await widget.client.document(id, ifRevision: revision);
      if (!mounted || request != _documentRequest) return;
      if (revision != null && response.index.revision != revision)
        throw const ManaKnowledgeException(
          'The index changed. Refresh or search again.',
        );
      final document = response.document;
      if (document == null)
        throw const ManaKnowledgeException(
          'Mana did not return this document.',
        );
      if (document.summary.id != id ||
          (result?.documentRevision != null &&
              result!.documentRevision != document.summary.revision))
        throw const ManaKnowledgeException(
          'The search source changed. Search again before opening it.',
        );
      ManaKnowledgePassage? extra;
      if (result != null) {
        final passage = document.passages
            .where((p) => p.id == result.passageId)
            .firstOrNull;
        if (passage != null && passage.revision != result.revision)
          throw const ManaKnowledgeException(
            'The matching passage changed. Search again.',
          );
        if (passage == null || passage.truncated) {
          final found = await widget.client.passage(
            result.passageId,
            ifRevision: revision,
          );
          if (!mounted || request != _documentRequest) return;
          if ((revision != null && found.index.revision != revision) ||
              found.documentId != id ||
              found.documentRevision != document.summary.revision ||
              found.passage.id != result.passageId ||
              found.passage.revision != result.revision)
            throw const ManaKnowledgeException(
              'The matching passage changed. Search again.',
            );
          extra = found.passage;
        }
      }
      setState(() {
        _document = document;
        _extraPassage = extra;
        _selectedPassageId = result?.passageId;
        _recents = [
          document.summary,
          ..._recents.where((d) => d.id != id),
        ].take(8).toList();
      });
      unawaited(_rememberDocument(document.summary));
    } catch (error) {
      if (mounted && request == _documentRequest)
        setState(() => _documentError = error);
    } finally {
      if (mounted && request == _documentRequest)
        setState(() => _documentLoading = false);
    }
  }

  Future<void> _rememberDocument(ManaKnowledgeDocumentSummary document) async {
    try {
      await widget.onDocumentOpened?.call(document);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The document opened, but reading history could not be saved.',
            ),
          ),
        );
    }
  }

  Widget _learning(_KnowledgeHome home) {
    final candidates = home.queue.candidates
        .where((c) => _learningFilter == 'all' || c.status == _learningFilter)
        .toList();
    final states = home.queue.candidates.map((c) => c.status).toSet().toList()
      ..sort();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Learning review queue',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Review proposals against their evidence. Acceptance and promotion remain separate actions.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final state in ['all', ...states])
              ChoiceChip(
                label: Text(state == 'all' ? 'All reviews' : _label(state)),
                selected: _learningFilter == state,
                onSelected: (_) => setState(() => _learningFilter = state),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (candidates.isEmpty) const Text('No candidates in this state.'),
        for (final candidate in candidates)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.proposal ?? candidate.id,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${candidate.sourceScope} · ${candidate.status}${candidate.promoted ? ' · promoted' : ''}',
                  ),
                  if (candidate.targetScope != null)
                    Text('Proposed destination: ${candidate.targetScope}'),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Evidence and limitations'),
                    children: [
                      _evidence('Evidence', candidate.evidence),
                      _evidence('Counter-evidence', candidate.counterEvidence),
                      _evidence('Limitations', candidate.limitations),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _candidate(candidate),
                      icon: const Icon(Icons.rate_review_outlined),
                      label: const Text('Review proposal'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _evidence(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          SelectableText(
            value == null || (value is List && value.isEmpty)
                ? 'None reported by Mana.'
                : _evidenceText(value),
          ),
        ],
      ),
    ),
  );

  String _evidenceText(Object? value) => switch (value) {
    List values => values.map(_evidenceText).join('\n'),
    Map values =>
      values.entries
          .map((entry) => '${entry.key}: ${_evidenceText(entry.value)}')
          .join('\n'),
    _ => '$value',
  };

  Future<void> _edit(ManaKnowledgeDocument document) async {
    final controller = TextEditingController(text: document.exactContent);
    final proposed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Revision-checked ${document.summary.scope} edit'),
        content: SizedBox(
          width: 720,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Target: ${document.summary.reference}'),
              if (document.sourceDisclosure != null)
                SelectableText(
                  'External User Context source: ${document.sourceDisclosure}',
                ),
              SelectableText('Expected: ${document.expectedRevision}'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 10,
                maxLines: 20,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Proposed exact content',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Review change'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (proposed == null || proposed == document.exactContent || !mounted)
      return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm exact revision'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current (${document.exactContent!.length} chars)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SelectableText(document.exactContent!, maxLines: 8),
              const Divider(),
              Text(
                'Proposed (${proposed.length} chars)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SelectableText(proposed, maxLines: 8),
              const SizedBox(height: 8),
              SelectableText(
                'Apply only if ${document.expectedRevision} is still current.',
              ),
              if (document.sourceDisclosure != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  'This writes the configured external User Context source at ${document.sourceDisclosure}; the generated .mana/user-context mirror remains read-only and is refreshed by Mana.',
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _action(
      () => widget.client.editDocument(document: document, content: proposed),
    );
  }

  Future<void> _candidate(ManaLearningCandidate candidate) async {
    final disposition = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(candidate.proposal ?? candidate.id),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Source: ${candidate.sourceScope} • Status: ${candidate.status}',
              ),
              Text('Evidence: ${candidate.evidence}'),
              Text(
                'Counter-evidence: ${candidate.counterEvidence ?? 'None reported'}',
              ),
              Text('Limitations: ${candidate.limitations ?? 'None reported'}'),
              Text('Target: ${candidate.targetScope ?? 'Not reported'}'),
              const SizedBox(height: 8),
              const Text('Review never promotes knowledge automatically.'),
            ],
          ),
        ),
        actions:
            candidate.promotionEligible &&
                candidate.sourceScope == 'user' &&
                !candidate.promoted
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'promote'),
                  child: const Text('Promote approved review'),
                ),
              ]
            : candidate.sourceScope == 'project'
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'archive'),
                  child: const Text('Archive'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'reject'),
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'review'),
                  child: const Text('Mark reviewed'),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'defer'),
                  child: const Text('Defer'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'reject'),
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'accept'),
                  child: const Text('Accept for separate promotion'),
                ),
              ],
      ),
    );
    if (disposition == null) return;
    await _action(
      () => disposition == 'promote'
          ? widget.client.promoteCandidate(candidate)
          : widget.client.disposeCandidate(candidate, disposition),
    );
  }

  Future<void> _action(Future<ManaActionReceipt> Function() invoke) async {
    try {
      final receipt = await invoke();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Action ${receipt.outcome}'),
          content: SelectableText(
            '${receipt.action}\n${receipt.actionId}\nExpected: ${receipt.expectedRevision}\nAfter: ${receipt.afterRevision ?? 'unchanged'}${receipt.proposalArtifact == null ? '' : '\nProposal: ${receipt.proposalArtifact}'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      _reload();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Widget _message(String title, String text, {VoidCallback? retry}) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            if (retry != null)
              TextButton(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );

  String _label(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)}';
}

class _KnowledgeHome {
  const _KnowledgeHome(this.capabilities, this.documents, this.queue);
  final ManaKnowledgeCapabilities capabilities;
  final ManaKnowledgeDocuments documents;
  final ManaLearningQueue queue;
}
