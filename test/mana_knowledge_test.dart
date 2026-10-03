import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/mana_knowledge.dart';
import 'package:mana_familiar/presentation/knowledge_center_page.dart';

void main() {
  test(
    'consumes published knowledge reads and revision-checked actions',
    () async {
      final root = await Directory.systemTemp.createTemp('familiar-knowledge-');
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/mana').writeAsString('');
      final calls = <List<String>>[];
      String? proposed;
      final client = ManaKnowledgeClient(
        projectRoot: root.path,
        run: (_, arguments, {workingDirectory}) async {
          calls.add(arguments);
          Map<String, dynamic> response;
          if (arguments.contains('capabilities')) {
            response = _capabilities;
          } else if (arguments.contains('documents')) {
            response = _documents;
          } else if (arguments.contains('document')) {
            response = _document;
          } else if (arguments.contains('search')) {
            response = _search;
          } else if (arguments.contains('learning-candidates')) {
            response = _queue;
          } else {
            final file = File(
              arguments[arguments.indexOf('--content-file') + 1],
            );
            expect(file.existsSync(), isTrue);
            proposed = file.readAsStringSync();
            response = _receipt;
          }
          return ProcessResult(1, 0, jsonEncode(response), '');
        },
      );

      final capabilities = await client.capabilities();
      expect(capabilities.index.freshness, 'current');
      expect(
        capabilities.scopes
            .where((scope) => scope.scope == 'user')
            .single
            .editable,
        isTrue,
      );
      final documents = await client.documents(scope: 'project');
      expect(
        documents.documents.single.reference,
        '.mana/global/architecture.md',
      );
      final detail = (await client.document(
        documents.documents.single.id,
      )).document!;
      expect(detail.editable, isTrue);
      expect(detail.exactContent, '# Architecture\n');
      expect(
        (await client.search(
          query: 'architecture',
          scope: 'project',
        )).results.single.snippet,
        'Architecture guidance',
      );
      expect(
        (await client.learningCandidates()).candidates.single.promotionEligible,
        isFalse,
      );
      final receipt = await client.editProjectDocument(
        document: detail,
        content: '# Updated\n',
      );
      expect(receipt.outcome, 'applied');
      expect(proposed, '# Updated\n');
      expect(calls.last.take(2), ['action', 'knowledge-edit']);
      expect(
        calls.last,
        containsAllInOrder(['--expected-revision', _revision]),
      );
    },
  );

  test('rejects unsafe producer references', () {
    expect(
      () => ManaKnowledgeDocuments.fromJson({
        ..._documents,
        'documents': [
          {
            ...(_documents['documents'] as List).single as Map<String, dynamic>,
            'source_reference': '/private/source.md',
          },
        ],
      }),
      throwsA(isA<ManaKnowledgeException>()),
    );
  });

  test('confirms external user edits and keeps promotion separate', () async {
    final root = await Directory.systemTemp.createTemp(
      'familiar-user-knowledge-',
    );
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/mana').writeAsString('');
    final calls = <List<String>>[];
    final client = ManaKnowledgeClient(
      projectRoot: root.path,
      run: (_, arguments, {workingDirectory}) async {
        calls.add(arguments);
        return ProcessResult(2, 0, jsonEncode(_receipt), '');
      },
    );
    final document = ManaKnowledgeDocument.fromJson(_userDocument);
    final candidate = ManaLearningQueue.fromJson(_userQueue).candidates.single;

    await client.editDocument(document: document, content: '# Updated user\n');
    expect(
      calls.single,
      containsAllInOrder([
        'action',
        'knowledge-edit',
        '--scope',
        'user',
        '--target',
        'preferences.md',
        '--confirm-user-source',
        '/example/user-context',
      ]),
    );

    await client.promoteCandidate(candidate);
    expect(
      calls.last,
      containsAllInOrder([
        'action',
        'user-learning-promote',
        '--review-id',
        candidate.reviewId,
        '--expected-revision',
        candidate.reviewRevision,
      ]),
    );
  });

  testWidgets('loads the Knowledge Center after the State is mounted', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('familiar-knowledge-ui-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/mana').writeAsStringSync('');
    final client = ManaKnowledgeClient(
      projectRoot: root.path,
      run: (_, arguments, {workingDirectory}) async => ProcessResult(
        1,
        0,
        jsonEncode(
          arguments.contains('capabilities')
              ? _capabilities
              : arguments.contains('documents')
              ? _documents
              : _queue,
        ),
        '',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: KnowledgeCenterPage(client: client)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Knowledge'), findsOneWidget);
    expect(find.textContaining('Index current'), findsOneWidget);
    expect(find.text('Architecture'), findsOneWidget);
    expect(find.text('Learning review queue'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('offers promotion only as a separate explicit user action', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('familiar-promotion-ui-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/mana').writeAsStringSync('');
    final client = ManaKnowledgeClient(
      projectRoot: root.path,
      run: (_, arguments, {workingDirectory}) async => ProcessResult(
        3,
        0,
        jsonEncode(
          arguments.contains('capabilities')
              ? _capabilities
              : arguments.contains('documents')
              ? _documents
              : _userQueue,
        ),
        '',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: KnowledgeCenterPage(client: client)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Prefer durable recovery.'));
    await tester.pumpAndSettle();

    expect(
      find.text('Review never promotes knowledge automatically.'),
      findsOneWidget,
    );
    expect(find.text('Promote approved review'), findsOneWidget);
    expect(find.text('Accept for separate promotion'), findsNothing);
  });
}

const _revision =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _passageRevision =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

const _capabilities = <String, dynamic>{
  'schema': manaKnowledgeCapabilitiesSchema,
  'index': {
    'freshness': 'current',
    'reason': null,
    'revision': _revision,
    'ranking': 'sqlite-fts5-bm25/v1',
  },
  'scopes': [
    {'scope': 'framework', 'health': 'current', 'editable': false},
    {
      'scope': 'user',
      'health': 'current',
      'editable': true,
      'reason': 'explicit-source-confirmation-required',
      'source_disclosure': '/example/user-context',
    },
    {'scope': 'project', 'health': 'current', 'editable': true},
    {'scope': 'candidate', 'health': 'current', 'editable': false},
  ],
  'operations': [
    'capabilities',
    'documents',
    'document',
    'search',
    'passage',
    'learning-candidates',
  ],
  'effective_context_trace': {
    'status': 'unavailable',
    'reason': 'no-authoritative-run-receipt-adapter',
  },
  'diagnostics': [],
};

const _summary = <String, dynamic>{
  'document_id': 'doc_aaaaaaaaaaaaaaaaaaaaaaaa',
  'source_reference': '.mana/global/architecture.md',
  'source_scope': 'project',
  'lifecycle_state': 'active',
  'title': 'Architecture',
  'document_revision': _revision,
  'byte_size': 15,
};

const _documents = <String, dynamic>{
  'schema': manaKnowledgeDocumentsSchema,
  'index': {'freshness': 'current', 'reason': null, 'revision': _revision},
  'filters': {
    'scopes': ['project'],
    'lifecycles': ['active'],
  },
  'documents': [_summary],
  'next_offset': null,
  'diagnostics': [],
};

const _document = <String, dynamic>{
  'schema': manaKnowledgeDocumentSchema,
  'index': {'freshness': 'current', 'reason': null, 'revision': _revision},
  'document': {
    ..._summary,
    'returned_bytes': 15,
    'truncated': false,
    'passages': [
      {
        'passage_id': 'psg_aaaaaaaaaaaaaaaaaaaaaaaa',
        'ordinal': 0,
        'heading_path': ['Architecture'],
        'body': '# Architecture\n',
        'passage_revision': _passageRevision,
        'truncated': false,
      },
    ],
    'edit_capability': {
      'available': true,
      'expected_revision': _revision,
      'exact_content': '# Architecture\n',
      'target': '.mana/global/architecture.md',
      'source_disclosure': null,
    },
  },
  'diagnostics': [],
};

const _search = <String, dynamic>{
  'schema': manaKnowledgeSearchSchema,
  'query': 'architecture',
  'index': {'freshness': 'current', 'reason': null, 'revision': _revision},
  'filters': {
    'scopes': ['project'],
    'lifecycles': ['active'],
  },
  'limits': {'results': 20, 'returned_bytes': 16384},
  'results': [
    {
      'passage_id': 'psg_aaaaaaaaaaaaaaaaaaaaaaaa',
      'document_id': 'doc_aaaaaaaaaaaaaaaaaaaaaaaa',
      'title': 'Architecture',
      'heading_path': ['Architecture'],
      'snippet': 'Architecture guidance',
      'source_reference': '.mana/global/architecture.md',
      'source_scope': 'project',
      'lifecycle_state': 'active',
      'document_revision': _revision,
      'passage_revision': _passageRevision,
      'rank': {
        'position': 1,
        'score': -1.0,
        'algorithm': 'sqlite-fts5-bm25/v1',
        'reasons': ['lexical_match'],
      },
    },
  ],
  'returned_bytes': 21,
  'gaps': [],
  'guarantees': {
    'generated_answer': false,
    'model_calls': 0,
    'network_calls': 0,
  },
};

const _queue = <String, dynamic>{
  'schema': manaLearningQueueSchema,
  'index': {'freshness': 'current', 'reason': null, 'revision': _revision},
  'candidates': [
    {
      'candidate_id': 'learning-deadbeef',
      'source_scope': 'project',
      'revision': _revision,
      'status': 'candidate',
      'proposal': 'Capture timeout guidance',
      'evidence': ['event-1'],
      'counter_evidence': 'One success',
      'limitations': 'One service',
      'target_scope': 'project',
      'source_reference': '.mana/learning/candidates/learning-deadbeef.json',
      'review_id': null,
      'review_revision': null,
      'promotion_eligible': false,
      'promoted': false,
    },
  ],
  'diagnostics': [],
};

const _userDocument = <String, dynamic>{
  'document_id': 'doc_bbbbbbbbbbbbbbbbbbbbbbbb',
  'source_reference': '.mana/user-context/preferences.md',
  'source_scope': 'user',
  'lifecycle_state': 'active',
  'title': 'Preferences',
  'document_revision': _revision,
  'byte_size': 13,
  'returned_bytes': 13,
  'truncated': false,
  'passages': <Object>[],
  'edit_capability': {
    'available': true,
    'expected_revision': _revision,
    'exact_content': '# Preferences\n',
    'target': 'preferences.md',
    'source_disclosure': '/example/user-context',
  },
};

const _userQueue = <String, dynamic>{
  'schema': manaLearningQueueSchema,
  'index': {'freshness': 'current', 'reason': null, 'revision': _revision},
  'candidates': [
    {
      'candidate_id':
          'user-context-candidate-1111111111111111111111111111111111111111111111111111111111111111',
      'source_scope': 'user',
      'revision': _revision,
      'status': 'reviewed',
      'proposal': 'Prefer durable recovery.',
      'evidence': ['cluster-1'],
      'counter_evidence': <Object>[],
      'limitations': <Object>[],
      'target_scope': 'reliability',
      'source_reference':
          'mana-user-state://user-learning/candidates/user-context-candidate-1111111111111111111111111111111111111111111111111111111111111111',
      'review_id':
          'review-2222222222222222222222222222222222222222222222222222222222222222',
      'review_revision': _passageRevision,
      'promotion_eligible': true,
      'promoted': false,
    },
  ],
  'diagnostics': <Object>[],
};

const _receipt = <String, dynamic>{
  'schema': manaActionReceiptSchema,
  'action_id': 'act_aaaaaaaaaaaaaaaaaaaaaaaa',
  'action': 'knowledge-edit',
  'target': {'scope': 'project', 'reference': '.mana/global/architecture.md'},
  'expected_revision': _revision,
  'before_revision': _revision,
  'after_revision': _passageRevision,
  'outcome': 'applied',
  'proposal_artifact': null,
  'details': {},
  'recorded_at': '2026-09-28T10:00:00Z',
  'guarantees': {
    'model_calls': 0,
    'network_calls': 0,
    'automatic_promotion': false,
  },
  'receipt_artifact':
      'mana-cache://actions/receipts/act_aaaaaaaaaaaaaaaaaaaaaaaa.json',
  'receipt_revision': _revision,
};
