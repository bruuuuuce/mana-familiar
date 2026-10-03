import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/human_feedback.dart';

void main() {
  const target = HumanFeedbackTarget(
    projectId: 'project:demo',
    artifactId: 'file:.mana/features/DEMO/planning/plan.md',
    artifactRevision: 'sha256:abc',
    sectionId: 'decisions',
  );

  test('draft survives a flush and retains its producer target', () async {
    final root = await Directory.systemTemp.createTemp('mana-feedback-draft-');
    addTearDown(() => root.delete(recursive: true));
    final store = HumanFeedbackDraftStore(root, debounce: Duration.zero);
    final draft = HumanFeedbackDraft(
      target: target,
      body: 'Scelta B: evita duplicati. 👩🏽‍💻\n\n`literal`',
      author: 'Ada',
      idempotencyKey: 'operation-1',
      updatedAt: DateTime.utc(2026, 9, 11),
    );

    store.schedule(draft);
    await store.flush(target);
    final loaded = await store.load(target);

    expect(loaded?.body, draft.body);
    expect(loaded?.author, 'Ada');
    expect(loaded?.target.sectionId, 'decisions');
    expect(loaded?.idempotencyKey, 'operation-1');
  });

  test('draft survives a newer revision in the same window session', () async {
    final root = await Directory.systemTemp.createTemp('mana-feedback-draft-');
    addTearDown(() => root.delete(recursive: true));
    final store = HumanFeedbackDraftStore(
      root,
      debounce: Duration.zero,
      sessionId: 'window-A',
    );
    final draft = HumanFeedbackDraft(
      target: target,
      body: 'Keep this during regeneration.',
      author: 'Ada',
      idempotencyKey: 'regeneration-draft',
      updatedAt: DateTime.utc(2026),
    );
    store.schedule(draft);
    await store.flush(target);
    const regenerated = HumanFeedbackTarget(
      projectId: 'project:demo',
      artifactId: 'file:.mana/features/DEMO/planning/plan.md',
      artifactRevision: 'sha256:def',
      sectionId: 'decisions',
    );

    final restored = await store.load(regenerated);

    expect(restored?.body, draft.body);
    expect(restored?.target.artifactRevision, 'sha256:abc');
  });

  test('two window sessions keep drafts for one target independent', () async {
    final root = await Directory.systemTemp.createTemp('mana-feedback-draft-');
    addTearDown(() => root.delete(recursive: true));
    final first = HumanFeedbackDraftStore(
      root,
      debounce: Duration.zero,
      sessionId: 'window-A',
    );
    final second = HumanFeedbackDraftStore(
      root,
      debounce: Duration.zero,
      sessionId: 'window-B',
    );
    first.schedule(
      HumanFeedbackDraft(
        target: target,
        body: 'A only',
        author: 'Ada',
        idempotencyKey: 'draft-A',
        updatedAt: DateTime.utc(2026),
      ),
    );
    second.schedule(
      HumanFeedbackDraft(
        target: target,
        body: 'B only',
        author: 'Bea',
        idempotencyKey: 'draft-B',
        updatedAt: DateTime.utc(2026),
      ),
    );
    await Future.wait([first.flush(target), second.flush(target)]);

    expect((await first.load(target))?.body, 'A only');
    expect((await second.load(target))?.body, 'B only');
  });

  test('discard removes a local draft without touching its artifact', () async {
    final root = await Directory.systemTemp.createTemp('mana-feedback-draft-');
    addTearDown(() => root.delete(recursive: true));
    final store = HumanFeedbackDraftStore(root, debounce: Duration.zero);
    store.schedule(
      HumanFeedbackDraft(
        target: target,
        body: 'temporary',
        author: 'Ada',
        idempotencyKey: 'operation-2',
        updatedAt: DateTime.utc(2026, 9, 11),
      ),
    );
    await store.flush(target);
    await store.discard(target);

    expect(await store.load(target), isNull);
    expect(
      await Directory('${root.path}${Platform.pathSeparator}.mana').exists(),
      isFalse,
    );
  });

  test('malformed drafts are ignored safely', () async {
    final root = await Directory.systemTemp.createTemp('mana-feedback-draft-');
    addTearDown(() => root.delete(recursive: true));
    final store = HumanFeedbackDraftStore(root);
    final file = File(
      '${root.path}${Platform.pathSeparator}${target.key}${Platform.pathSeparator}comment.json',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('{not json');

    expect(await store.load(target), isNull);
  });

  test(
    'reply and document drafts stay separate for the same artifact',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mana-feedback-draft-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = HumanFeedbackDraftStore(root, debounce: Duration.zero);
      final comment = HumanFeedbackDraft(
        target: target,
        body: 'Document comment',
        author: 'Ada Rossi',
        idempotencyKey: 'comment-op',
        updatedAt: DateTime.utc(2026, 9, 12),
      );
      final reply = HumanFeedbackDraft(
        target: target,
        body: 'A saved reply',
        author: 'Ada Rossi',
        idempotencyKey: 'reply-op',
        updatedAt: DateTime.utc(2026, 9, 12),
        composerId: 'reply:thread-1',
      );
      store.schedule(comment);
      store.schedule(reply);
      await store.flush(target);
      await store.flush(target, 'reply:thread-1');

      expect((await store.load(target))?.body, 'Document comment');
      expect(
        (await store.load(target, 'reply:thread-1'))?.body,
        'A saved reply',
      );
    },
  );

  test(
    'repository sends comment text on stdin with structured arguments',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mana-feedback-client-',
      );
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}${Platform.pathSeparator}mana').writeAsString('');
      late List<String> arguments;
      late String request;
      final repository = ManaHumanFeedbackRepository(
        projectRoot: root.path,
        run: (executable, actualArguments, actualRequest) async {
          arguments = actualArguments;
          request = actualRequest;
          return const HumanFeedbackCommandResult(
            exitCode: 0,
            stderr: '',
            stdout:
                '{"schemaVersion":"mana.human-feedback.result/v1","status":"persisted","threadId":"thread_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","threadRevision":"1"}',
          );
        },
      );

      await repository.createThread(
        target: target,
        body: 'Commento con `markdown` e emoji 👩🏽‍💻',
        author: 'Ada',
        idempotencyKey: 'operation-stdin',
      );

      expect(arguments, containsAll(['create', '--request-stdin', '--json']));
      expect(arguments.join(' '), isNot(contains('Commento con')));
      expect(request, contains('Commento con `markdown`'));
    },
  );

  test(
    'repository loads producer decision targets and preserves their revision',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mana-feedback-client-',
      );
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}${Platform.pathSeparator}mana').writeAsString('');
      final requests = <Map<String, dynamic>>[];
      final repository = ManaHumanFeedbackRepository(
        projectRoot: root.path,
        run: (_, arguments, request) async {
          requests.add({
            'arguments': arguments,
            'request': jsonDecode(request),
          });

          if (arguments.contains('decision-targets')) {
            return const HumanFeedbackCommandResult(
              exitCode: 0,
              stderr: '',
              stdout:
                  '{"schemaVersion":"mana.human-feedback.decision-targets/v1","sourcePath":".mana/features/P/planning/story-start-implementation-plan-v2.json","sourceRevision":"sha256:plan","decisions":[{"decisionId":"decision_a","question":"Which option?","status":"open","options":[{"optionId":"option_b","label":"B","summary":"Use B"}]}]}',
            );
          }
          return const HumanFeedbackCommandResult(
            exitCode: 0,
            stderr: '',
            stdout:
                '{"schemaVersion":"mana.human-feedback.decision-result/v1","status":"recorded","decisionId":"decision_a","selectedOptionId":"option_b","decisionRevision":"1","planUpdate":"replanning_required"}',
          );
        },
      );

      final targets = await repository.decisionTargets(
        '.mana/features/P/planning/story-start-implementation-plan-v2.json',
      );
      expect(targets.sourceRevision, 'sha256:plan');
      expect(targets.decisions.single.options.single.id, 'option_b');
      await repository.recordDecision(
        targets: targets,
        decisionId: 'decision_a',
        decisionRevision: '0',
        optionId: 'option_b',
        author: 'Ada Rossi',
        rationale: 'B satisfies the constraint.',
        idempotencyKey: 'decision-op',
      );
      expect(requests.last['arguments'], contains('decide'));
      expect(requests.last['request']['decisionSourceRevision'], 'sha256:plan');
      expect(requests.last['request']['optionId'], 'option_b');
    },
  );

  test(
    'structured decision drafts retain their stable selected option',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mana-feedback-draft-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = HumanFeedbackDraftStore(root, debounce: Duration.zero);
      final decision = HumanFeedbackDraft(
        target: const HumanFeedbackTarget(
          projectId: 'project:demo',
          artifactId: 'file:.mana/plan.json',
          artifactRevision: 'sha256:plan',
        ),
        body: 'Chosen because it meets the acceptance criterion.',
        author: 'Ada',
        idempotencyKey: 'decision-key',
        updatedAt: DateTime.utc(2026),
        composerId: 'decision:.mana/plan.json:decision-1',
        selectionId: 'option-2',
      );
      store.schedule(decision);
      await store.flush(decision.target, decision.composerId);

      final restored = await store.load(decision.target, decision.composerId);
      expect(restored?.selectionId, 'option-2');
      expect(restored?.body, decision.body);
    },
  );

  test(
    'simultaneous timer and lifecycle flushes serialize one draft file',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mana-feedback-draft-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = HumanFeedbackDraftStore(root, debounce: Duration.zero);
      final draft = HumanFeedbackDraft(
        target: target,
        body: 'Do not lose this draft.',
        author: 'Ada',
        idempotencyKey: 'serialized-flush',
        updatedAt: DateTime.utc(2026),
      );
      store.schedule(draft);
      await Future.wait([store.flush(target), store.dispose()]);

      final restored = await store.load(target);
      expect(restored?.body, draft.body);
    },
  );

  test('producer busy result remains typed and retryable', () async {
    final root = await Directory.systemTemp.createTemp('mana-feedback-client-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}${Platform.pathSeparator}mana').writeAsString('');
    final repository = ManaHumanFeedbackRepository(
      projectRoot: root.path,
      run: (executable, arguments, request) async =>
          const HumanFeedbackCommandResult(
            exitCode: 75,
            stderr: '',
            stdout:
                '{"schemaVersion":"mana.human-feedback.busy/v1","status":"busy","retryable":true}',
          ),
    );

    await expectLater(
      repository.createThread(
        target: target,
        body: 'Draft',
        author: 'Ada',
        idempotencyKey: 'busy-operation',
      ),
      throwsA(isA<HumanFeedbackBusy>()),
    );
  });

  test(
    'restarts a paginated read once when the producer view changes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mana-feedback-client-',
      );
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}${Platform.pathSeparator}mana').writeAsString('');
      final cursors = <String?>[];
      var firstPageCalls = 0;
      final repository = ManaHumanFeedbackRepository(
        projectRoot: root.path,
        run: (_, arguments, request) async {
          expect(arguments, contains('list'));
          final cursor =
              (jsonDecode(request) as Map<String, dynamic>)['cursor']
                  as String?;
          cursors.add(cursor);
          if (cursor == null) {
            firstPageCalls++;
            return HumanFeedbackCommandResult(
              exitCode: 0,
              stderr: '',
              stdout: _threadPage(
                threadId: firstPageCalls == 1 ? 'thread-old' : 'thread-new',
                nextCursor: 'next',
                viewRevision: firstPageCalls == 1 ? 'view-1' : 'view-2',
              ),
            );
          }
          return HumanFeedbackCommandResult(
            exitCode: 0,
            stderr: '',
            stdout: _threadPage(
              threadId: 'thread-last',
              nextCursor: null,
              viewRevision: firstPageCalls == 1 ? 'view-2' : 'view-2',
            ),
          );
        },
      );

      final threads = await repository.threads(target);

      expect(cursors, [null, 'next', null, 'next']);
      expect(threads.map((thread) => thread.id), ['thread-new', 'thread-last']);
    },
  );

  test(
    'loads source targets and changed links from history-capable Mana',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mana-feedback-client-',
      );
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}${Platform.pathSeparator}mana').writeAsString('');
      final repository = ManaHumanFeedbackRepository(
        projectRoot: root.path,
        run: (executable, arguments, request) async {
          if (arguments.contains('capabilities')) {
            return const HumanFeedbackCommandResult(
              exitCode: 0,
              stderr: '',
              stdout:
                  '{"schemaVersion":"mana.human-feedback.capabilities/v1","operations":["list-history"]}',
            );
          }
          expect(arguments, contains('list-history'));
          return const HumanFeedbackCommandResult(
            exitCode: 0,
            stderr: '',
            stdout:
                '{"schemaVersion":"mana.human-feedback.thread-history/v1","threads":[{"threadId":"thread_history","revision":"1","state":"open","target":{"artifactId":"file:.mana/features/DEMO/planning/plan.md","artifactRevision":"sha256:older","sectionId":"decisions"},"linkState":"changed","entries":[]}],"nextCursor":null,"viewRevision":"history-1"}',
          );
        },
      );

      final threads = await repository.threadsForDisplay(target);

      expect(threads.single.target.artifactRevision, 'sha256:older');
      expect(threads.single.linkState, HumanFeedbackLinkState.changed);
    },
  );

  test('uses producer-declared stable section targets when available', () async {
    final root = await Directory.systemTemp.createTemp('mana-feedback-client-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}${Platform.pathSeparator}mana').writeAsString('');
    final repository = ManaHumanFeedbackRepository(
      projectRoot: root.path,
      run: (executable, arguments, request) async {
        if (arguments.contains('capabilities')) {
          return const HumanFeedbackCommandResult(
            exitCode: 0,
            stderr: '',
            stdout:
                '{"schemaVersion":"mana.human-feedback.capabilities/v1","operations":["targets"]}',
          );
        }
        expect(arguments, contains('targets'));
        return const HumanFeedbackCommandResult(
          exitCode: 0,
          stderr: '',
          stdout:
              '{"schemaVersion":"mana.human-feedback.targets/v1","stableSections":true,"sections":[{"sectionId":"base-implementation-plan","headingIndex":3}]}',
        );
      },
    );

    final targets = await repository.targets(target);

    expect(targets.stableSections, isTrue);
    expect(targets.sections.single.id, 'base-implementation-plan');
    expect(targets.sections.single.headingIndex, 3);
  });

  test(
    'terminates a stalled producer instead of waiting indefinitely',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mana-feedback-client-',
      );
      addTearDown(() => root.delete(recursive: true));
      final wrapper = File('${root.path}${Platform.pathSeparator}mana');
      await wrapper.writeAsString('');
      final fixture = File('${root.path}${Platform.pathSeparator}stall.dart');
      await fixture.writeAsString(
        "import 'dart:async';\n"
        'Future<void> main() async {\n'
        '  await Future<void>.delayed(const Duration(seconds: 60));\n'
        '}\n',
      );
      Process? producer;
      addTearDown(() => producer?.kill());
      final repository = ManaHumanFeedbackRepository(
        projectRoot: root.path,
        commandTimeout: const Duration(milliseconds: 250),
        startProcess: (_, _) async {
          producer = await Process.start(_dartExecutable(), [fixture.path]);
          return producer!;
        },
      );

      await expectLater(
        repository.threads(target),
        throwsA(isA<TimeoutException>()),
      );
      expect(producer, isNotNull);
      await producer!.exitCode.timeout(const Duration(seconds: 2));
    },
  );
}

String _dartExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}dart-sdk'
      '${Platform.pathSeparator}bin${Platform.pathSeparator}'
      '${Platform.isWindows ? 'dart.exe' : 'dart'}',
    );
    if (candidate.existsSync()) return candidate.path;
    if (directory.parent.path == directory.path) {
      throw StateError('Cannot locate the Flutter test runner Dart SDK.');
    }
    directory = directory.parent;
  }
}

String _threadPage({
  required String threadId,
  required String? nextCursor,
  required String viewRevision,
}) => jsonEncode({
  'schemaVersion': 'mana.human-feedback.threads/v1',
  'threads': [
    {
      'threadId': threadId,
      'revision': '1',
      'state': 'open',
      'entries': [
        {
          'entryId': '$threadId-entry',
          'author': 'Ada',
          'body': 'Body',
          'recordedAt': '2026-09-12T00:00:00Z',
          'kind': 'comment',
        },
      ],
    },
  ],
  'nextCursor': nextCursor,
  'viewRevision': viewRevision,
});
