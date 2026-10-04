// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../application/mana_knowledge.dart';

class KnowledgeCenterPage extends StatefulWidget {
  const KnowledgeCenterPage({
    super.key,
    required this.client,
    this.onReady,
    this.onSettled,
    this.refreshSignal,
  });
  final ManaKnowledgeClient client;
  final VoidCallback? onReady;
  final ValueChanged<bool>? onSettled;
  final ValueListenable<int>? refreshSignal;

  @override
  State<KnowledgeCenterPage> createState() => _KnowledgeCenterPageState();
}

class _KnowledgeCenterPageState extends State<KnowledgeCenterPage> {
  String _scope = 'project';
  late Future<_KnowledgeHome> _home;
  Future<ManaKnowledgeSearch>? _search;
  ManaKnowledgeDocument? _document;
  Object? _documentError;
  bool _documentLoading = false;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _home = _load();
    widget.refreshSignal?.addListener(_reload);
  }

  Future<_KnowledgeHome> _load() async {
    try {
      final home = _KnowledgeHome(
        await widget.client.capabilities(),
        await widget.client.documents(scope: _scope),
        await widget.client.learningCandidates(),
      );
      if (mounted) {
        widget.onReady?.call();
        widget.onSettled?.call(true);
      }
      return home;
    } catch (_) {
      if (mounted) widget.onSettled?.call(false);
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
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_reload);
    _query.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _home = _load();
    _search = null;
    _document = null;
    _documentError = null;
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<_KnowledgeHome>(
    future: _home,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return _message(
          'Knowledge unavailable',
          '${snapshot.error}',
          retry: _reload,
        );
      }
      final home = snapshot.requireData;
      return Row(
        children: [
          SizedBox(width: 360, child: _sidebar(home)),
          const VerticalDivider(width: 1),
          Expanded(child: _content(home)),
        ],
      );
    },
  );

  Widget _sidebar(_KnowledgeHome home) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Knowledge', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 4),
      Text(
        'Index ${home.capabilities.index.freshness} • ${home.capabilities.index.revision ?? 'no revision'}',
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        children: home.capabilities.scopes
            .where((scope) => scope.scope != 'candidate')
            .map(
              (scope) => ChoiceChip(
                label: Text('${_label(scope.scope)} · ${scope.health}'),
                selected: _scope == scope.scope,
                onSelected: (_) {
                  _scope = scope.scope;
                  _reload();
                },
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _query,
        decoration: InputDecoration(
          labelText: 'Search $_scope knowledge',
          suffixIcon: IconButton(
            icon: const Icon(Icons.search),
            onPressed: _runSearch,
          ),
        ),
        onSubmitted: (_) => _runSearch(),
      ),
      const SizedBox(height: 12),
      if (_search case final search?)
        FutureBuilder<ManaKnowledgeSearch>(
          future: search,
          builder: (context, snapshot) => snapshot.hasError
              ? Text('${snapshot.error}')
              : snapshot.hasData
              ? Column(
                  children: snapshot.requireData.results
                      .map(
                        (result) => ListTile(
                          dense: true,
                          title: Text(result.title ?? result.reference),
                          subtitle: Text(
                            '${result.lifecycle} • ${result.snippet ?? 'metadata only'}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _openDocument(
                            result.documentId,
                            snapshot.requireData.index.revision,
                          ),
                        ),
                      )
                      .toList(),
                )
              : const LinearProgressIndicator(),
        )
      else
        ...home.documents.documents.map(
          (document) => ListTile(
            dense: true,
            title: Text(document.title ?? document.reference),
            subtitle: Text(
              '${document.lifecycle} • ${document.byteSize} bytes',
            ),
            onTap: () =>
                _openDocument(document.id, home.documents.index.revision),
          ),
        ),
      const Divider(height: 28),
      Text(
        'Learning review queue',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (home.queue.candidates.isEmpty)
        const Text('No candidates reported by Mana.')
      else
        ...home.queue.candidates.map(
          (candidate) => ListTile(
            dense: true,
            title: Text(candidate.proposal ?? candidate.id),
            subtitle: Text(
              '${candidate.sourceScope} • ${candidate.status}${candidate.promotionEligible ? ' • promotion eligible' : ''}',
            ),
            onTap: () => _candidate(candidate),
          ),
        ),
    ],
  );

  Widget _content(_KnowledgeHome home) {
    if (_documentLoading)
      return const Center(child: CircularProgressIndicator());
    if (_documentError != null)
      return _message('Document unavailable', '$_documentError');
    final document = _document;
    if (document == null) {
      return _message(
        'Select a knowledge document',
        home.capabilities.effectiveContextStatus == 'unavailable'
            ? 'Mana has no authoritative run receipt for effective-context trace. Available knowledge is not presented as material actually read by a run.'
            : 'Choose a document or search result.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Text(
              document.summary.title ?? document.summary.reference,
              style: Theme.of(context).textTheme.headlineSmall,
            );
            final edit = document.editable
                ? FilledButton.tonalIcon(
                    onPressed: () => _edit(document),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      document.summary.scope == 'user'
                          ? 'Edit external source'
                          : 'Edit with revision check',
                    ),
                  )
                : null;
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (edit != null) ...[const SizedBox(height: 8), edit],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: title),
                ?edit,
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        SelectableText(
          '${document.summary.scope} • ${document.summary.lifecycle} • ${document.summary.revision}',
        ),
        if (document.truncated)
          const Text('Content is truncated by the producer byte budget.'),
        const Divider(height: 28),
        ...document.passages.map(
          (passage) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (passage.headingPath.isNotEmpty)
                  Text(
                    passage.headingPath.join(' › '),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                const SizedBox(height: 6),
                SelectableText(passage.body),
                Text(
                  passage.revision,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _runSearch() {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() => _search = widget.client.search(query: query, scope: _scope));
  }

  Future<void> _openDocument(String id, String? revision) async {
    setState(() {
      _documentLoading = true;
      _documentError = null;
    });
    try {
      final response = await widget.client.document(id, ifRevision: revision);
      if (!mounted) return;
      setState(() => _document = response.document);
    } catch (error) {
      if (mounted) setState(() => _documentError = error);
    } finally {
      if (mounted) setState(() => _documentLoading = false);
    }
  }

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
