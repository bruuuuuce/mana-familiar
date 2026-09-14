import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/artifact_renderer.dart';
import '../application/human_feedback.dart';
import '../native_e2e_bridge.dart';

/// A producer-backed thread panel. It holds recoverable local drafts only; all
/// published contributions travel through [HumanFeedbackRepository].
class HumanFeedbackPanel extends StatefulWidget {
  const HumanFeedbackPanel({
    super.key,
    required this.repository,
    required this.target,
    this.drafts,
    this.refreshSignal,
    this.nativeE2E,
  });

  final HumanFeedbackRepository repository;
  final HumanFeedbackTarget target;
  final HumanFeedbackDraftStore? drafts;

  /// Increments after the Observatory accepts an external Mana publication.
  /// Keeping the panel subscribed avoids showing a stale thread list while a
  /// Story Start regeneration completes underneath an open bottom sheet.
  final ValueListenable<int>? refreshSignal;
  final NativeE2EBridge? nativeE2E;

  @override
  State<HumanFeedbackPanel> createState() => _HumanFeedbackPanelState();
}

class _PublishCommentIntent extends Intent {
  const _PublishCommentIntent();
}

class _HumanFeedbackPanelState extends State<HumanFeedbackPanel> {
  final _body = TextEditingController();
  final _author = TextEditingController();
  final _authorFocus = FocusNode();
  final _bodyFocus = FocusNode();
  final Map<String, TextEditingController> _replies = {};
  final Map<String, String> _replyIdempotencyKeys = {};
  final Set<String> _replying = {};
  late String _idempotencyKey;
  List<HumanFeedbackThread>? _threads;
  Object? _error;
  var _sending = false;
  var _composerEdited = false;
  var _suppressComposerDrafts = false;
  var _showResolved = false;
  var _showPreview = false;
  var _composerDraftLoadState = 'not-requested';
  var _lastComposerBody = '';
  var _lastComposerAuthor = '';
  HumanFeedbackCapabilities? _capabilities;
  NativeE2EPanelBindings? _nativeE2EPanel;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = _newIdempotencyKey();
    _load();
    _loadCapabilities();
    widget.refreshSignal?.addListener(_load);
    unawaited(_loadComposerDraft());
    _body.addListener(_onComposerEdited);
    _author.addListener(_onComposerEdited);
    _registerNativeE2EPanel();
  }

  @override
  void didUpdateWidget(covariant HumanFeedbackPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal == widget.refreshSignal) return;
    oldWidget.refreshSignal?.removeListener(_load);
    widget.refreshSignal?.addListener(_load);
  }

  Future<void> _loadCapabilities() async {
    final repository = widget.repository;
    if (repository is! ManaHumanFeedbackRepository) return;
    try {
      final capabilities = await repository.capabilities();
      if (mounted) setState(() => _capabilities = capabilities);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  bool _supports(String operation) =>
      _capabilities?.supports(operation) ?? true;

  @override
  void dispose() {
    final bindings = _nativeE2EPanel;
    if (bindings != null) widget.nativeE2E?.unregisterPanel(bindings);
    widget.refreshSignal?.removeListener(_load);
    _body.removeListener(_onComposerEdited);
    _author.removeListener(_onComposerEdited);
    _saveDraft();
    _body.dispose();
    _author.dispose();
    _authorFocus.dispose();
    _bodyFocus.dispose();
    for (final reply in _replies.values) {
      reply.dispose();
    }
    super.dispose();
  }

  String _newIdempotencyKey() =>
      // Mana operation IDs are filesystem-safe, project-global identifiers.
      // [HumanFeedbackTarget.key] is intentionally URL/path-shaped and may
      // contain percent escapes and slashes, so it cannot be used verbatim.
      'comment:${DateTime.now().microsecondsSinceEpoch}';

  void _onComposerEdited() {
    if (_suppressComposerDrafts ||
        (_body.text == _lastComposerBody &&
            _author.text == _lastComposerAuthor)) {
      return;
    }
    _lastComposerBody = _body.text;
    _lastComposerAuthor = _author.text;
    _composerEdited = true;
    _saveDraft();
  }

  void _replaceComposer({required String body, required String author}) {
    _suppressComposerDrafts = true;
    _body.text = body;
    _author.text = author;
    _lastComposerBody = body;
    _lastComposerAuthor = author;
    _suppressComposerDrafts = false;
  }

  Future<void> _loadComposerDraft() async {
    final drafts = widget.drafts;
    if (drafts == null) return;
    _composerDraftLoadState = 'loading';
    final draft = await drafts.load(widget.target);
    if (!mounted) return;
    if (draft == null) {
      setState(() => _composerDraftLoadState = 'absent');
      return;
    }
    if (_composerEdited) {
      setState(() => _composerDraftLoadState = 'superseded-by-input');
      return;
    }
    _replaceComposer(body: draft.body, author: draft.author);
    _idempotencyKey = draft.idempotencyKey;
    setState(() => _composerDraftLoadState = 'restored');
  }

  void _saveDraft() {
    final drafts = widget.drafts;
    if (drafts == null ||
        !_composerEdited ||
        (_body.text.isEmpty && _author.text.isEmpty)) {
      return;
    }
    drafts.schedule(
      HumanFeedbackDraft(
        target: widget.target,
        body: _body.text,
        author: _author.text,
        idempotencyKey: _idempotencyKey,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Map<String, Object?> _nativeE2EStatus() => {
    'target': {
      'projectId': widget.target.projectId,
      'artifactId': widget.target.artifactId,
      'artifactRevision': widget.target.artifactRevision,
      'sectionId': widget.target.sectionId,
    },
    'composer': {'author': _author.text, 'body': _body.text},
    'composerDraftLoadState': _composerDraftLoadState,
    'loading': _threads == null,
    'sending': _sending,
    'error': _error?.toString(),
    'threads': _threads
        ?.map(
          (thread) => {
            'id': thread.id,
            'state': thread.state.name,
            'linkState': thread.linkState.name,
            'entries': thread.entries
                .map(
                  (entry) => {
                    'id': entry.id,
                    'author': entry.author,
                    'body': entry.body,
                    'isReply': entry.isReply,
                  },
                )
                .toList(growable: false),
          },
        )
        .toList(growable: false),
  };

  void _registerNativeE2EPanel() {
    final bridge = widget.nativeE2E;
    if (bridge == null) return;
    final bindings = NativeE2EPanelBindings(
      status: _nativeE2EStatus,
      setComposer: _setComposerForNativeE2E,
      publish: _publish,
      setReply: _setReplyForNativeE2E,
      publishReply: _publishReplyForNativeE2E,
      retry: _retryLoad,
    );
    _nativeE2EPanel = bindings;
    bridge.registerPanel(bindings);
  }

  Future<void> _setComposerForNativeE2E(String author, String body) async {
    if (!mounted) throw StateError('comment panel is no longer mounted');
    _author.text = author;
    _body.text = body;
    if (mounted) setState(() {});
  }

  HumanFeedbackThread _threadForNativeE2E(String threadId) {
    final thread = _threads
        ?.where((candidate) => candidate.id == threadId)
        .firstOrNull;
    if (thread == null) throw StateError('thread is not available: $threadId');
    return thread;
  }

  Future<void> _setReplyForNativeE2E(String threadId, String body) async {
    if (!mounted) throw StateError('comment panel is no longer mounted');
    final thread = _threadForNativeE2E(threadId);
    setState(() => _replying.add(threadId));
    _replyController(thread).text = body;
  }

  Future<void> _publishReplyForNativeE2E(String threadId) async {
    if (!mounted) throw StateError('comment panel is no longer mounted');
    await _reply(_threadForNativeE2E(threadId));
  }

  Future<void> _discardComposerDraft() async {
    await widget.drafts?.discard(widget.target);
    if (!mounted) return;
    setState(() {
      _replaceComposer(body: '', author: '');
      _idempotencyKey = _newIdempotencyKey();
      _composerEdited = false;
      _error = null;
    });
  }

  TextEditingController _replyController(HumanFeedbackThread thread) {
    return _replies.putIfAbsent(thread.id, () {
      final controller = TextEditingController();
      final composerId = 'reply:${thread.id}';
      _replyIdempotencyKeys[thread.id] =
          'reply:${thread.id}:${DateTime.now().microsecondsSinceEpoch}';
      controller.addListener(() {
        final drafts = widget.drafts;
        if (drafts == null || controller.text.isEmpty) return;
        drafts.schedule(
          HumanFeedbackDraft(
            target: widget.target,
            body: controller.text,
            author: _author.text,
            idempotencyKey: _replyIdempotencyKeys[thread.id]!,
            updatedAt: DateTime.now(),
            composerId: composerId,
          ),
        );
      });
      widget.drafts?.load(widget.target, composerId).then((draft) {
        if (!mounted || draft == null || controller.text.isNotEmpty) return;
        controller.text = draft.body;
        _replyIdempotencyKeys[thread.id] = draft.idempotencyKey;
      });
      return controller;
    });
  }

  Future<void> _load() async {
    try {
      final repository = widget.repository;
      final threads = repository is ManaHumanFeedbackRepository
          ? await repository.threadsForDisplay(widget.target)
          : await repository.threads(widget.target);
      if (mounted) {
        setState(() {
          _threads = threads;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _retryLoad() async {
    if (mounted) setState(() => _error = null);
    await Future.wait([_load(), _loadCapabilities()]);
  }

  Future<void> _publish() async {
    if (!_supports('create')) {
      setState(() => _error = 'This Mana producer cannot create comments.');
      return;
    }
    final body = _body.text;
    final author = _author.text.trim();
    final sentKey = _idempotencyKey;
    if (body.trim().isEmpty || author.isEmpty) {
      setState(() => _error = 'Write a comment and identify its author.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.drafts?.flush(widget.target);
      // Subsequent typing is a new intent even if the current request has not
      // completed. This prevents an ACK from consuming a later draft.
      _idempotencyKey = _newIdempotencyKey();
      await widget.repository.createThread(
        target: widget.target,
        body: body,
        author: author,
        idempotencyKey: sentKey,
      );
      if (_body.text == body && _author.text.trim() == author) {
        await widget.drafts?.discard(widget.target);
        _replaceComposer(body: '', author: _author.text);
        _composerEdited = false;
      }
      await _load();
    } on HumanFeedbackConflict catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (_body.text == body && _author.text.trim() == author) {
        _idempotencyKey = sentKey;
        _saveDraft();
      }
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggle(HumanFeedbackThread thread) async {
    if (!_supports(
      thread.state == HumanFeedbackThreadState.resolved ? 'reopen' : 'resolve',
    )) {
      setState(() => _error = 'This Mana producer cannot change thread state.');
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.repository.setResolved(
        threadId: thread.id,
        revision: thread.revision,
        resolved: thread.state != HumanFeedbackThreadState.resolved,
        idempotencyKey: 'thread:${thread.id}:${thread.revision}:toggle',
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reply(HumanFeedbackThread thread) async {
    if (!_supports('reply')) {
      setState(() => _error = 'This Mana producer cannot add replies.');
      return;
    }
    final controller = _replyController(thread);
    final body = controller.text;
    final author = _author.text.trim();
    final sentKey = _replyIdempotencyKeys[thread.id]!;
    if (body.trim().isEmpty || author.isEmpty) {
      setState(() => _error = 'Write a reply and identify its author.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      _replyIdempotencyKeys[thread.id] =
          'reply:${thread.id}:${DateTime.now().microsecondsSinceEpoch}';
      await widget.repository.reply(
        threadId: thread.id,
        revision: thread.revision,
        body: body,
        author: author,
        idempotencyKey: sentKey,
      );
      if (controller.text == body) {
        controller.clear();
        await widget.drafts?.discard(widget.target, 'reply:${thread.id}');
        if (mounted) setState(() => _replying.remove(thread.id));
      }
      await _load();
    } on HumanFeedbackConflict catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (error) {
      if (controller.text == body) {
        _replyIdempotencyKeys[thread.id] = sentKey;
      }
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final threads = _threads;
    final visibleThreads = threads == null
        ? null
        : _showResolved
        ? threads
        : threads
              .where(
                (thread) => thread.state != HumanFeedbackThreadState.resolved,
              )
              .toList(growable: false);
    final openCount = threads
        ?.where((thread) => thread.state != HumanFeedbackThreadState.resolved)
        .length;
    return SafeArea(
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter, meta: true):
              _PublishCommentIntent(),
        },
        child: Actions(
          actions: {
            _PublishCommentIntent: CallbackAction<_PublishCommentIntent>(
              onInvoke: (_) {
                if (!_sending) unawaited(_publish());
                return null;
              },
            ),
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final threadListHeight = (constraints.maxHeight * .38).clamp(
                  160.0,
                  480.0,
                );
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Comments',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Comments are saved separately from the generated document.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        if (threads != null)
                          SegmentedButton<bool>(
                            key: const Key('feedback-thread-filter'),
                            segments: [
                              ButtonSegment(
                                value: false,
                                label: Text('Open (${openCount ?? 0})'),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('All (${threads.length})'),
                              ),
                            ],
                            selected: {_showResolved},
                            showSelectedIcon: false,
                            onSelectionChanged: _sending
                                ? null
                                : (selection) => setState(
                                    () => _showResolved = selection.single,
                                  ),
                          ),
                        if (threads != null) const SizedBox(height: 8),
                        SizedBox(
                          height: threadListHeight,
                          child: visibleThreads == null
                              ? const Center(child: CircularProgressIndicator())
                              : ListView(
                                  children: [
                                    if (visibleThreads.isEmpty)
                                      Text(
                                        _showResolved
                                            ? 'No comments yet.'
                                            : 'No open comments.',
                                      ),
                                    ...visibleThreads.map(_thread),
                                  ],
                                ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    '$_error',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  key: const Key('feedback-retry'),
                                  onPressed: _sending ? null : _retryLoad,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('feedback-author'),
                          controller: _author,
                          focusNode: _authorFocus,
                          autofocus: true,
                          onSubmitted: (_) => _bodyFocus.requestFocus(),
                          decoration: const InputDecoration(
                            labelText: 'Author',
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<bool>(
                          key: const Key('feedback-composer-mode'),
                          segments: const [
                            ButtonSegment(value: false, label: Text('Write')),
                            ButtonSegment(value: true, label: Text('Preview')),
                          ],
                          selected: {_showPreview},
                          showSelectedIcon: false,
                          onSelectionChanged: _sending
                              ? null
                              : (selection) => setState(
                                  () => _showPreview = selection.single,
                                ),
                        ),
                        const SizedBox(height: 8),
                        if (_showPreview)
                          _InertMarkdownPreview(markdown: _body.text)
                        else
                          TextField(
                            key: const Key('feedback-body'),
                            controller: _body,
                            focusNode: _bodyFocus,
                            minLines: 3,
                            maxLines: 7,
                            decoration: const InputDecoration(
                              labelText: 'Comment',
                              alignLabelWithHint: true,
                            ),
                          ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                key: const Key('feedback-discard-draft'),
                                onPressed: _sending
                                    ? null
                                    : _discardComposerDraft,
                                child: const Text('Discard draft'),
                              ),
                              FilledButton.icon(
                                key: const Key('feedback-publish'),
                                onPressed: _sending || !_supports('create')
                                    ? null
                                    : _publish,
                                icon: const Icon(Icons.send_outlined),
                                label: const Text('Publish comment'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _thread(HumanFeedbackThread thread) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  thread.state == HumanFeedbackThreadState.resolved
                      ? 'Resolved'
                      : 'Open',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              TextButton(
                onPressed:
                    _sending ||
                        !_supports(
                          thread.state == HumanFeedbackThreadState.resolved
                              ? 'reopen'
                              : 'resolve',
                        )
                    ? null
                    : () => _toggle(thread),
                child: Text(
                  thread.state == HumanFeedbackThreadState.resolved
                      ? 'Reopen'
                      : 'Resolve',
                ),
              ),
            ],
          ),
          if (thread.linkState != HumanFeedbackLinkState.valid)
            Text(
              'Document link: ${thread.linkState.name}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ...thread.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${entry.author}: ${entry.body}'),
            ),
          ),
          const SizedBox(height: 8),
          if (!_replying.contains(thread.id))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('feedback-reply-open-${thread.id}'),
                onPressed: _sending || !_supports('reply')
                    ? null
                    : () => setState(() => _replying.add(thread.id)),
                icon: const Icon(Icons.reply_outlined),
                label: const Text('Reply'),
              ),
            )
          else ...[
            TextField(
              key: Key('feedback-reply-${thread.id}'),
              controller: _replyController(thread),
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Reply'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    key: Key('feedback-reply-cancel-${thread.id}'),
                    onPressed: _sending
                        ? null
                        : () => setState(() => _replying.remove(thread.id)),
                    child: const Text('Cancel'),
                  ),
                  TextButton.icon(
                    key: Key('feedback-reply-submit-${thread.id}'),
                    onPressed: _sending || !_supports('reply')
                        ? null
                        : () => _reply(thread),
                    icon: const Icon(Icons.reply_outlined),
                    label: const Text('Send reply'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// A compact, non-interactive preview for human-authored Markdown. It shares
/// the artifact renderer sanitisation but never follows links, loads images,
/// evaluates HTML or renders executable diagram directives.
class _InertMarkdownPreview extends StatelessWidget {
  const _InertMarkdownPreview({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final safe = safeMarkdownText(markdown);
    final children = <Widget>[];
    for (final line in safe.split('\n')) {
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        children.add(
          Text(
            heading.group(2)!,
            style: heading.group(1)!.length == 1
                ? Theme.of(context).textTheme.titleLarge
                : Theme.of(context).textTheme.titleMedium,
          ),
        );
        continue;
      }
      final list = RegExp(r'^\s*(?:[-*+] |\d+\. )(.*)$').firstMatch(line);
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (list != null)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text('•'),
                ),
              Expanded(
                child: SelectableText(
                  list?.group(1) ?? line,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      label: 'Safe Markdown preview. Links and HTML are inactive.',
      child: Container(
        key: const Key('feedback-markdown-preview'),
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 220),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          child: children.isEmpty
              ? const Text('Nothing to preview.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
        ),
      ),
    );
  }
}

/// Producer-backed choice form for a published Story Start v2 plan. The form
/// never infers alternatives from Markdown; it loads them from Mana first.
class HumanDecisionPanel extends StatefulWidget {
  const HumanDecisionPanel({
    super.key,
    required this.repository,
    required this.sourcePath,
    required this.target,
    this.drafts,
    this.nativeE2E,
  });

  final ManaHumanFeedbackRepository repository;
  final String sourcePath;
  final HumanFeedbackTarget target;
  final HumanFeedbackDraftStore? drafts;
  final NativeE2EBridge? nativeE2E;

  @override
  State<HumanDecisionPanel> createState() => _HumanDecisionPanelState();
}

class _HumanDecisionPanelState extends State<HumanDecisionPanel> {
  final _author = TextEditingController();
  final _rationale = TextEditingController();
  HumanDecisionTargets? _targets;
  Map<String, HumanDecisionState> _states = const {};
  String? _decisionId;
  String? _optionId;
  Object? _error;
  var _saving = false;
  var _draftEdited = false;
  late String _idempotencyKey;
  NativeE2EDecisionBindings? _nativeE2EDecision;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = _newIdempotencyKey();
    _author.addListener(_onDraftEdited);
    _rationale.addListener(_onDraftEdited);
    _registerNativeE2EDecision();
    _load();
  }

  @override
  void dispose() {
    final bindings = _nativeE2EDecision;
    if (bindings != null) widget.nativeE2E?.unregisterDecision(bindings);
    _author.removeListener(_onDraftEdited);
    _rationale.removeListener(_onDraftEdited);
    _saveDraft();
    _author.dispose();
    _rationale.dispose();
    super.dispose();
  }

  String _composerId(String decisionId) =>
      'decision:${widget.sourcePath}:$decisionId';

  String _newIdempotencyKey() =>
      'decision:${DateTime.now().microsecondsSinceEpoch}';

  Map<String, Object?> _nativeE2EDecisionStatus() => {
    'loading': _targets == null && _error == null,
    'saving': _saving,
    'error': _error?.toString(),
    'selectedDecisionId': _decisionId,
    'selectedOptionId': _optionId,
    'author': _author.text,
    'rationale': _rationale.text,
    'decisions': _targets?.decisions
        .map(
          (decision) => {
            'id': decision.id,
            'status': decision.status,
            'options': decision.options
                .map((option) => {'id': option.id})
                .toList(growable: false),
            'state': {
              'revision': _states[decision.id]?.revision,
              'selectedOptionId': _states[decision.id]?.selectedOptionId,
            },
          },
        )
        .toList(growable: false),
  };

  void _registerNativeE2EDecision() {
    final bridge = widget.nativeE2E;
    if (bridge == null) return;
    final bindings = NativeE2EDecisionBindings(
      status: _nativeE2EDecisionStatus,
      setDecision: _setDecisionForNativeE2E,
      publish: _save,
    );
    _nativeE2EDecision = bindings;
    bridge.registerDecision(bindings);
  }

  Future<void> _setDecisionForNativeE2E(
    String decisionId,
    String optionId,
    String author,
    String rationale,
  ) async {
    if (!mounted) throw StateError('decision panel is no longer mounted');
    final decision = _targets?.decisions
        .where((candidate) => candidate.id == decisionId)
        .firstOrNull;
    if (decision == null || decision.status != 'open') {
      throw StateError('decision is not open: $decisionId');
    }
    if (!decision.options.any((option) => option.id == optionId)) {
      throw StateError('option is not available: $optionId');
    }
    setState(() {
      _decisionId = decisionId;
      _optionId = optionId;
      _author.text = author;
      _rationale.text = rationale;
      _draftEdited = true;
    });
    _saveDraft();
  }

  void _onDraftEdited() {
    _draftEdited = true;
    _saveDraft();
  }

  void _saveDraft() {
    final decisionId = _decisionId;
    if (decisionId == null ||
        (_author.text.isEmpty &&
            _rationale.text.isEmpty &&
            _optionId == null)) {
      return;
    }
    widget.drafts?.schedule(
      HumanFeedbackDraft(
        target: widget.target,
        body: _rationale.text,
        author: _author.text,
        idempotencyKey: _idempotencyKey,
        updatedAt: DateTime.now(),
        composerId: _composerId(decisionId),
        selectionId: _optionId,
      ),
    );
  }

  void _loadDraft(String decisionId) {
    widget.drafts?.load(widget.target, _composerId(decisionId)).then((draft) {
      if (!mounted ||
          draft == null ||
          _draftEdited ||
          _decisionId != decisionId) {
        return;
      }
      _author.text = draft.author;
      _rationale.text = draft.body;
      _optionId = draft.selectionId;
      _idempotencyKey = draft.idempotencyKey;
      setState(() {});
    });
  }

  Future<void> _load() async {
    try {
      final targets = await widget.repository.decisionTargets(
        widget.sourcePath,
      );
      final states = await Future.wait(
        targets.decisions.map(
          (decision) => widget.repository.decisionState(decision.id),
        ),
      );
      if (!mounted) return;
      setState(() {
        _targets = targets;
        _states = {for (final state in states) state.decisionId: state};
        _decisionId = targets.decisions
            .where((item) => item.status == 'open')
            .firstOrNull
            ?.id;
        _optionId = _decisionId == null
            ? null
            : _states[_decisionId]?.selectedOptionId;
        _error = null;
      });
      if (_decisionId != null) {
        _loadDraft(_decisionId!);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  HumanDecisionTarget? get _selectedDecision =>
      _targets?.decisions.where((item) => item.id == _decisionId).firstOrNull;

  Future<void> _retryLoad() async {
    if (mounted) setState(() => _error = null);
    await _load();
  }

  Future<void> _save() async {
    final targets = _targets;
    final decision = _selectedDecision;
    final option = _optionId;
    final state = decision == null ? null : _states[decision.id];
    final author = _author.text.trim();
    final rationale = _rationale.text;
    final sentKey = _idempotencyKey;
    if (targets == null ||
        decision == null ||
        option == null ||
        state == null ||
        author.isEmpty ||
        rationale.trim().isEmpty) {
      setState(
        () => _error =
            'Choose an open decision and option, then provide author and rationale.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _idempotencyKey = _newIdempotencyKey();
      await widget.repository.recordDecision(
        targets: targets,
        decisionId: decision.id,
        decisionRevision: state.revision,
        optionId: option,
        author: author,
        rationale: rationale,
        idempotencyKey: sentKey,
      );
      if (_author.text.trim() == author && _rationale.text == rationale) {
        await widget.drafts?.discard(widget.target, _composerId(decision.id));
        _rationale.clear();
      }
      if (mounted) {
        await _load();
      }
      if (mounted) {
        setState(
          () => _error =
              'Decision recorded. Story Start still needs replanning to apply it.',
        );
      }
    } on HumanFeedbackConflict catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (_author.text.trim() == author && _rationale.text == rationale) {
        _idempotencyKey = sentKey;
        _saveDraft();
      }
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    final decision = _selectedDecision;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Record decision',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (targets == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (targets != null) ...[
                DropdownButtonFormField<String>(
                  key: const Key('decision-target'),
                  initialValue: _decisionId,
                  decoration: const InputDecoration(labelText: 'Open decision'),
                  items: targets.decisions
                      .where((item) => item.status == 'open')
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.question),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _saveDraft();
                          _decisionId = value;
                          _optionId = value == null
                              ? null
                              : _states[value]?.selectedOptionId;
                          _draftEdited = false;
                          if (value != null) {
                            _loadDraft(value);
                          }
                        }),
                ),
                if (decision != null) ...[
                  const SizedBox(height: 8),
                  RadioGroup<String>(
                    groupValue: _optionId,
                    onChanged: (value) {
                      if (!_saving) {
                        setState(() {
                          _optionId = value;
                          _onDraftEdited();
                        });
                      }
                    },
                    child: Column(
                      children: decision.options
                          .map(
                            (item) => RadioListTile<String>(
                              title: Text(item.label),
                              subtitle: Text(item.summary),
                              value: item.id,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                TextField(
                  key: const Key('decision-author'),
                  controller: _author,
                  decoration: const InputDecoration(labelText: 'Author'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('decision-rationale'),
                  controller: _rationale,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Rationale',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Recording a decision does not approve the plan or start a provider.',
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Record decision'),
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '$_error',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('decision-retry'),
                        onPressed: _saving ? null : _retryLoad,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
