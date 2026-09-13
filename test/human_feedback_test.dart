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
    'terminates a stalled producer instead of waiting indefinitely',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mana-feedback-client-',
      );
      addTearDown(() => root.delete(recursive: true));
      final wrapper = File('${root.path}${Platform.pathSeparator}mana');
      await wrapper.writeAsString('#!/bin/sh\nexec sleep 5\n');
      await Process.run('chmod', ['+x', wrapper.path]);
      final repository = ManaHumanFeedbackRepository(
        projectRoot: root.path,
        commandTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        repository.threads(target),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
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
