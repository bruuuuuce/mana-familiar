import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/human_feedback.dart';
import 'package:mana_familiar/presentation/human_feedback_panel.dart';

void main() {
  const target = HumanFeedbackTarget(
    projectId: 'project:demo',
    artifactId: 'file:.mana/demo.md',
    artifactRevision: 'sha256:demo',
  );

  testWidgets('watcher refresh preserves a failed publication', (tester) async {
    final repository = _FailedPublicationRepository();
    final signal = ValueNotifier<int>(0);
    addTearDown(signal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HumanFeedbackPanel(
            repository: repository,
            target: target,
            refreshSignal: signal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('feedback-author')), 'Ada');
    await tester.enterText(
      find.byKey(const Key('feedback-body')),
      'Keep this text',
    );
    await tester.ensureVisible(find.byKey(const Key('feedback-publish')));
    await tester.tap(find.byKey(const Key('feedback-publish')));
    await tester.pumpAndSettle();
    expect(find.textContaining('synthetic publish failure'), findsOneWidget);
    signal.value++;
    await tester.pumpAndSettle();
    expect(find.textContaining('synthetic publish failure'), findsOneWidget);
    expect(find.byKey(const Key('feedback-retry')), findsOneWidget);
  });

  testWidgets('publishes a separately owned comment', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HumanFeedbackPanel(repository: repository, target: target),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byKey(const Key('feedback-author')), 'Ada');
      await tester.enterText(
        find.byKey(const Key('feedback-body')),
        'Choose option B.',
      );
      await tester.tap(find.byKey(const Key('feedback-publish')));
      await tester.pump();
      await tester.pump();

      expect(repository.created, hasLength(1));
      expect(repository.created.single.body, 'Choose option B.');
      expect(repository.created.single.author, 'Ada');
      expect(
        repository.idempotencyKeys.single,
        matches(r'^[A-Za-z0-9._:-]{1,128}$'),
      );
      expect(find.textContaining('Ada: Choose option B.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('feedback-reply-open-thread-1')));
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'feedback-reply-thread-1',
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('feedback-reply-thread-1')))
            .getSemanticsData()
            .label,
        'Reply',
      );
      await tester.enterText(
        find.byKey(const Key('feedback-reply-thread-1')),
        'Confirmed with the team.',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final replySubmit = find.byKey(
        const Key('feedback-reply-submit-thread-1'),
      );
      await tester.ensureVisible(replySubmit);
      await tester.tap(replySubmit);
      await tester.pumpAndSettle();
      expect(repository.created, hasLength(2));

      await tester.tap(find.text('Resolve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Resolved'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a late publish acknowledgement keeps newer typed text', (
    tester,
  ) async {
    final repository = _DelayedRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HumanFeedbackPanel(repository: repository, target: target),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byKey(const Key('feedback-author')), 'Ada');
    await tester.enterText(find.byKey(const Key('feedback-body')), 'First');
    final publish = find.byKey(const Key('feedback-publish'));
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('feedback-body')), 'New draft');
    repository.complete();
    await tester.pumpAndSettle();

    expect(find.text('New draft'), findsOneWidget);
  });

  testWidgets('publishes the focused composer with Command-Enter', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HumanFeedbackPanel(repository: repository, target: target),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('feedback-author')), 'Ada');
    await tester.enterText(
      find.byKey(const Key('feedback-body')),
      'Published from the keyboard.',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(repository.created.single.body, 'Published from the keyboard.');
  });

  testWidgets('refreshes an open panel after an external publication', (
    tester,
  ) async {
    final repository = _ReloadCountingRepository();
    final signal = ValueNotifier(0);
    addTearDown(signal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HumanFeedbackPanel(
            repository: repository,
            target: target,
            refreshSignal: signal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.loadCalls, 1);

    signal.value++;
    await tester.pumpAndSettle();

    expect(repository.loadCalls, 2);
  });

  testWidgets('defaults to open threads and can reveal resolved history', (
    tester,
  ) async {
    final repository = _Repository().._resolved = true;
    repository.created.add(
      HumanFeedbackEntry(
        id: 'entry-0',
        threadId: 'thread-1',
        body: 'Already decided',
        author: 'Ada',
        recordedAt: DateTime.utc(2026),
        isReply: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HumanFeedbackPanel(repository: repository, target: target),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No open comments.'), findsOneWidget);
    expect(find.textContaining('Already decided'), findsNothing);

    await tester.tap(find.text('All (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Already decided'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
  });

  testWidgets('explicit discard clears the unpublished composer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HumanFeedbackPanel(repository: _Repository(), target: target),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('feedback-author')), 'Ada');
    await tester.enterText(
      find.byKey(const Key('feedback-body')),
      'Keep this?',
    );
    final discard = find.byKey(const Key('feedback-discard-draft'));
    await tester.ensureVisible(discard);
    await tester.tap(discard);
    await tester.pump();

    expect(find.text('Ada'), findsNothing);
    expect(find.text('Keep this?'), findsNothing);
  });

  testWidgets('renders a safe inert Markdown preview', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HumanFeedbackPanel(repository: _Repository(), target: target),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('feedback-body')),
      '# Decision\n\n- Keep [the link](https://example.test)\n<script>alert(1)</script>',
    );
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('feedback-markdown-preview')), findsOneWidget);
    expect(find.text('Decision'), findsOneWidget);
    expect(find.textContaining('Keep [the link]'), findsOneWidget);
    expect(find.textContaining('alert(1)'), findsNothing);
    expect(find.byKey(const Key('feedback-body')), findsNothing);
  });

  testWidgets('keeps the essential composer usable at 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: HumanFeedbackPanel(repository: _Repository(), target: target),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('feedback-author')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('feedback-publish')));
    expect(find.byKey(const Key('feedback-publish')), findsOneWidget);
  });

  testWidgets('retries a failed thread load without discarding typed text', (
    tester,
  ) async {
    final repository = _FlakyRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HumanFeedbackPanel(repository: repository, target: target),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('feedback-retry')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('feedback-author')), 'Ada');
    await tester.enterText(
      find.byKey(const Key('feedback-body')),
      'Still local',
    );
    await tester.tap(find.byKey(const Key('feedback-retry')));
    await tester.pump();
    await tester.pump();

    expect(repository.loadCalls, 2);
    expect(find.byKey(const Key('feedback-retry')), findsNothing);
    expect(find.text('Still local'), findsOneWidget);
  });
}

class _FlakyRepository extends _Repository {
  var loadCalls = 0;

  @override
  Future<List<HumanFeedbackThread>> threads(HumanFeedbackTarget target) async {
    loadCalls++;
    if (loadCalls == 1) throw StateError('temporary unavailable');
    return super.threads(target);
  }
}

class _ReloadCountingRepository extends _Repository {
  var loadCalls = 0;

  @override
  Future<List<HumanFeedbackThread>> threads(HumanFeedbackTarget target) async {
    loadCalls++;
    return super.threads(target);
  }
}

class _DelayedRepository implements HumanFeedbackRepository {
  final Completer<HumanFeedbackThread> _create = Completer();
  late HumanFeedbackTarget _target;

  void complete() => _create.complete(
    HumanFeedbackThread(
      id: 'thread-delayed',
      target: _target,
      state: HumanFeedbackThreadState.open,
      linkState: HumanFeedbackLinkState.valid,
      revision: '1',
      entries: const [],
    ),
  );

  @override
  Future<HumanFeedbackThread> createThread({
    required HumanFeedbackTarget target,
    required String body,
    required String author,
    required String idempotencyKey,
  }) {
    _target = target;
    return _create.future;
  }

  @override
  Future<HumanFeedbackThread> reply({
    required String threadId,
    required String revision,
    required String body,
    required String author,
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<HumanFeedbackThread> setResolved({
    required String threadId,
    required String revision,
    required bool resolved,
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<List<HumanFeedbackThread>> threads(HumanFeedbackTarget target) async =>
      const [];
}

class _Repository implements HumanFeedbackRepository {
  final created = <HumanFeedbackEntry>[];
  final idempotencyKeys = <String>[];
  HumanFeedbackTarget? _target;
  var _resolved = false;
  @override
  Future<List<HumanFeedbackThread>> threads(HumanFeedbackTarget target) async {
    _target = target;
    return [
      if (created.isNotEmpty)
        HumanFeedbackThread(
          id: 'thread-1',
          target: target,
          state: _resolved
              ? HumanFeedbackThreadState.resolved
              : HumanFeedbackThreadState.open,
          linkState: HumanFeedbackLinkState.valid,
          revision: '1',
          entries: created,
        ),
    ];
  }

  @override
  Future<HumanFeedbackThread> createThread({
    required HumanFeedbackTarget target,
    required String body,
    required String author,
    required String idempotencyKey,
  }) async {
    _target = target;
    idempotencyKeys.add(idempotencyKey);
    final entry = HumanFeedbackEntry(
      id: 'entry-${created.length}',
      threadId: 'thread-1',
      body: body,
      author: author,
      recordedAt: DateTime.utc(2026),
      isReply: false,
    );
    created.add(entry);
    return HumanFeedbackThread(
      id: 'thread-1',
      target: target,
      state: HumanFeedbackThreadState.open,
      linkState: HumanFeedbackLinkState.valid,
      revision: '1',
      entries: created,
    );
  }

  @override
  Future<HumanFeedbackThread> reply({
    required String threadId,
    required String revision,
    required String body,
    required String author,
    required String idempotencyKey,
  }) async {
    created.add(
      HumanFeedbackEntry(
        id: 'entry-${created.length}',
        threadId: threadId,
        body: body,
        author: author,
        recordedAt: DateTime.utc(2026),
        isReply: true,
      ),
    );
    return _thread(resolved: false);
  }

  @override
  Future<HumanFeedbackThread> setResolved({
    required String threadId,
    required String revision,
    required bool resolved,
    required String idempotencyKey,
  }) async {
    _resolved = resolved;
    return _thread(resolved: resolved);
  }

  HumanFeedbackThread _thread({required bool resolved}) => HumanFeedbackThread(
    id: 'thread-1',
    target: _target!,
    state: resolved
        ? HumanFeedbackThreadState.resolved
        : HumanFeedbackThreadState.open,
    linkState: HumanFeedbackLinkState.valid,
    revision: '1',
    entries: created,
  );
}

class _FailedPublicationRepository extends _Repository {
  @override
  Future<HumanFeedbackThread> createThread({
    required HumanFeedbackTarget target,
    required String body,
    required String author,
    required String idempotencyKey,
  }) async {
    throw StateError('synthetic publish failure');
  }
}
