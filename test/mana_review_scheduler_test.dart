import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/mana_review_scheduler.dart';
import 'package:mana_familiar/presentation/scheduled_review_inbox_page.dart';

void main() {
  test('reads scheduler state and emits only explicit local actions', () async {
    final root = await Directory.systemTemp.createTemp(
      'familiar-review-inbox-',
    );
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/mana').writeAsString('');
    final calls = <List<String>>[];
    final client = ManaReviewSchedulerClient(
      projectRoot: root.path,
      run: (_, arguments, {workingDirectory}) async {
        calls.add(arguments);
        final response = arguments.contains('status')
            ? _status
            : arguments.contains('inbox')
            ? _inbox
            : arguments.contains('show')
            ? {
                'schema': manaReviewRunSchema,
                'run': {
                  ..._run,
                  'findings': [_finding],
                },
              }
            : {
                'schema': 'mana.review-scheduler.action-receipt/v1',
                'action': arguments[1],
                'run_id': _run['run_id'],
                'outcome': 'queued',
              };
        return ProcessResult(1, 0, jsonEncode(response), '');
      },
    );

    expect((await client.status()).credentialsStored, isFalse);
    final summary = (await client.inbox()).items.single;
    expect(summary.findings, isEmpty);
    final detail = await client.show(summary.id);
    expect(detail.findings.single.title, 'Null guard');
    await client.retry(detail);
    expect(
      calls.last,
      containsAllInOrder([
        'review-inbox',
        'retry',
        detail.id,
        '--expected-draft-revision',
        detail.draftRevision!,
        '--json',
      ]),
    );
    await client.cancel(
      {..._run, 'status': 'queued'}.let(ManaReviewRun.fromJson),
    );
    expect(calls.last.take(2), ['review-inbox', 'cancel']);
  });

  test('rejects malformed scheduler identities', () {
    expect(
      () => ManaReviewInbox.fromJson({
        ..._inbox,
        'items': [
          {..._run, 'repository': '../escape'},
        ],
      }),
      throwsA(isA<ManaReviewSchedulerException>()),
    );
  });

  testWidgets('loads the PR Inbox after the State is mounted', (tester) async {
    final root = Directory.systemTemp.createTempSync('familiar-review-ui-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/mana').writeAsStringSync('');
    final client = ManaReviewSchedulerClient(
      projectRoot: root.path,
      run: (_, arguments, {workingDirectory}) async => ProcessResult(
        1,
        0,
        jsonEncode(arguments.contains('status') ? _status : _inbox),
        '',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ScheduledReviewInboxPage(client: client)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('PR Inbox'), findsOneWidget);
    expect(find.textContaining('Guard payment callback'), findsOneWidget);
    expect(find.textContaining('acme/payments #17'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

extension _MapApply on Map<String, dynamic> {
  T let<T>(T Function(Map<String, dynamic>) transform) => transform(this);
}

const _revision =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _status = <String, dynamic>{
  'schema': manaReviewStatusSchema,
  'configured': true,
  'enabled': true,
  'state': 'current',
  'policy': 'analyse',
  'credentials_stored': false,
  'counts': {'completed': 1},
};
const _run = <String, dynamic>{
  'run_id': 'review_aaaaaaaaaaaaaaaaaaaaaaaa',
  'repository': 'acme/payments',
  'pr_number': 17,
  'head_sha': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'reviewer': 'alice',
  'profile_revision': _revision,
  'context_revision': 'ctx-1',
  'title': 'Guard payment callback',
  'url': 'https://example.invalid/acme/payments/pull/17',
  'updated_at': '2026-09-28T10:00:00Z',
  'status': 'completed',
  'attempt': 1,
  'draft_revision': _revision,
  'error_code': null,
  'publication_status': null,
  'created_at': '2026-09-28T10:00:00Z',
  'changed_at': '2026-09-28T10:01:00Z',
  'stale': false,
};
const _finding = <String, dynamic>{
  'draft_id': 'draft-1',
  'severity': 'high',
  'title': 'Null guard',
  'body': 'The callback dereferences a nullable field.',
};
const _inbox = <String, dynamic>{
  'schema': manaReviewInboxSchema,
  'items': [_run],
};
