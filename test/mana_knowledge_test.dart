import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/mana_knowledge.dart';
import 'package:mana_familiar/presentation/knowledge_center_page.dart';
import 'package:mana_familiar/presentation/knowledge_document_reader.dart';
import 'package:mana_familiar/presentation/explorer_page.dart';
import 'package:mana_familiar/application/explorer_config.dart';

void main() {
  final liveProject = Platform.environment['KNOWLEDGE_PROJECT_ROOT'];
  final liveMana = Platform.environment['KNOWLEDGE_MANA_ROOT'];
  test(
    'reads cross-source pages and passages from the real Mana producer',
    () async {
      final client = ManaKnowledgeClient(
        projectRoot: liveProject!,
        manaRoot: liveMana!,
      );
      final capabilities = await client.capabilities();
      expect(capabilities.index.freshness, 'current');
      final documents = await client.documents(scope: 'all', limit: 5);
      expect(documents.documents, isNotEmpty);
      if (documents.nextOffset case final offset?) {
        final next = await client.documents(
          scope: 'all',
          limit: 5,
          offset: offset,
        );
        expect(next.index.revision, documents.index.revision);
        expect(
          next.documents
              .map((d) => d.id)
              .toSet()
              .intersection(documents.documents.map((d) => d.id).toSet()),
          isEmpty,
        );
      }
      final search = await client.search(query: 'Synthetic', scope: 'all');
      expect(search.results, isNotEmpty);
      final match = search.results.first;
      final document = await client.document(
        match.documentId,
        ifRevision: search.index.revision,
      );
      expect(document.document!.summary.revision, match.documentRevision);
      final passage = await client.passage(
        match.passageId,
        ifRevision: search.index.revision,
      );
      expect(passage.documentId, match.documentId);
      expect(passage.passage.revision, match.revision);
      expect(passage.passage.body, isNotEmpty);
      expect(passage.passage.headingPath, match.headingPath);
    },
    skip: liveProject == null || liveMana == null
        ? 'Set KNOWLEDGE_PROJECT_ROOT and KNOWLEDGE_MANA_ROOT after preparing a derived index.'
        : false,
  );
  test(
    'expands cross-source and lifecycle filters through published CLI arguments',
    () async {
      final calls = <List<String>>[];
      final client = _uiClient((args) async {
        calls.add(args);
        return _defaultResponse(args);
      });
      await client.documents(scope: 'all', lifecycle: 'archived', offset: 50);
      expect(
        calls.single,
        containsAllInOrder([
          '--scope',
          'project',
          '--scope',
          'user',
          '--scope',
          'framework',
          '--lifecycle',
          'archived',
          '--offset',
          '50',
        ]),
      );
      await client.search(query: 'retry', scope: 'all', lifecycle: 'all');
      expect(calls.last, isNot(contains('all')));
      expect(
        calls.last,
        containsAllInOrder([
          '--lifecycle',
          'active',
          '--lifecycle',
          'candidate',
        ]),
      );
      final result = ManaKnowledgeSearch.fromJson(_search).results.single;
      expect(result.headingPath, ['Architecture']);
      expect(result.documentRevision, _revision);
    },
  );

  testWidgets('search opens and highlights the exact producer passage', (
    tester,
  ) async {
    final calls = <List<String>>[];
    final client = _uiClient((args) async {
      calls.add(args);
      return _defaultResponse(args);
    });
    await _mountKnowledge(tester, client);
    await tester.enterText(
      find.byKey(const Key('knowledge-search')),
      'architecture',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('knowledge-result-psg_aaaaaaaaaaaaaaaaaaaaaaaa'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('knowledge-search-match')), findsOneWidget);
    final reader = tester.widget<KnowledgeDocumentReader>(
      find.byType(KnowledgeDocumentReader),
    );
    expect(reader.initialPassageId, 'psg_aaaaaaaaaaaaaaaaaaaaaaaa');
    expect(
      calls.last,
      containsAllInOrder([
        'document',
        _summary['document_id'],
        '--if-revision',
        _revision,
      ]),
    );
    expect(find.text('On this page'), findsOneWidget);
    await tester.tap(find.text('Source'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('knowledge-source')), findsOneWidget);
  });

  testWidgets('retrieves a search passage beyond a truncated preview', (
    tester,
  ) async {
    final calls = <List<String>>[];
    const passageId = 'psg_cccccccccccccccccccccccc';
    final client = _uiClient((args) async {
      calls.add(args);
      if (args.contains('search')) {
        return {
          ..._search,
          'results': [
            {
              ...(_search['results'] as List).single as Map<String, dynamic>,
              'passage_id': passageId,
            },
          ],
        };
      }
      if (args.contains('document')) {
        return {
          ..._document,
          'document': {
            ..._document['document'] as Map<String, dynamic>,
            'truncated': true,
          },
        };
      }
      if (args.contains('passage')) {
        return {
          'schema': manaKnowledgePassageSchema,
          'index': _documents['index'],
          'passage': {
            ..._summary,
            'passage_id': passageId,
            'heading_path': ['Later guidance'],
            'body': '**Exact later match**',
            'passage_revision': _passageRevision,
            'truncated': false,
          },
        };
      }
      return _defaultResponse(args);
    });
    await _mountKnowledge(tester, client);
    await tester.enterText(find.byKey(const Key('knowledge-search')), 'later');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('knowledge-result-$passageId')));
    await tester.pumpAndSettle();
    expect(
      find.text('Matched passage outside the document preview'),
      findsOneWidget,
    );
    expect(find.text('Exact later match'), findsOneWidget);
    expect(
      calls.last,
      containsAllInOrder(['passage', passageId, '--if-revision', _revision]),
    );
  });

  testWidgets(
    'loads the next library page and deduplicates document identities',
    (tester) async {
      final calls = <List<String>>[];
      final client = _uiClient((args) async {
        calls.add(args);
        if (args.contains('documents')) {
          return {
            ..._documents,
            'documents':
                args.contains('50') &&
                    args[args.indexOf('--offset') + 1] == '50'
                ? [_summary, _otherSummary]
                : [_summary],
            'next_offset': args[args.indexOf('--offset') + 1] == '50'
                ? null
                : 50,
          };
        }
        return _defaultResponse(args);
      });
      await _mountKnowledge(tester, client);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more documents'));
      await tester.pumpAndSettle();
      expect(find.text('Architecture'), findsOneWidget);
      expect(find.text('Recovery policy'), findsOneWidget);
      expect(find.text('2 loaded documents'), findsOneWidget);
      expect(find.text('Load more documents'), findsNothing);
      expect(calls.last, containsAllInOrder(['--offset', '50']));
    },
  );

  testWidgets('does not mix pages from different index revisions', (
    tester,
  ) async {
    final client = _uiClient((args) async {
      if (args.contains('documents')) {
        return {
          ..._documents,
          'next_offset': 50,
          if (args[args.indexOf('--offset') + 1] == '50')
            'index': {
              ..._documents['index'] as Map<String, dynamic>,
              'revision': _passageRevision,
            },
          if (args[args.indexOf('--offset') + 1] == '50')
            'documents': [_otherSummary],
        };
      }
      return _defaultResponse(args);
    });
    await _mountKnowledge(tester, client);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more documents'));
    await tester.pumpAndSettle();
    expect(find.text('Recovery policy'), findsNothing);
    expect(find.textContaining('The index changed.'), findsOneWidget);
    expect(find.text('Architecture'), findsOneWidget);
  });

  testWidgets(
    'an older document response cannot replace the latest selection',
    (tester) async {
      final first = Completer<Map<String, dynamic>>();
      final second = Completer<Map<String, dynamic>>();
      final client = _uiClient((args) async {
        if (args.contains('documents')) {
          return {
            ..._documents,
            'documents': [_summary, _otherSummary],
          };
        }
        if (args.contains('document')) {
          return args.contains(_summary['document_id'])
              ? first.future
              : second.future;
        }
        return _defaultResponse(args);
      });
      await _mountKnowledge(tester, client);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Architecture'));
      await tester.pump();
      await tester.tap(find.text('Recovery policy'));
      second.complete({
        ..._document,
        'document': {
          ..._document['document'] as Map<String, dynamic>,
          ..._otherSummary,
        },
      });
      await tester.pumpAndSettle();
      first.complete(_document);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<KnowledgeDocumentReader>(
              find.byType(KnowledgeDocumentReader),
            )
            .document
            .summary
            .title,
        'Recovery policy',
      );
    },
  );

  testWidgets('refresh invalidates a pending document response', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    final signal = ValueNotifier(0);
    addTearDown(signal.dispose);
    final client = _uiClient(
      (args) async =>
          args.contains('document') ? response.future : _defaultResponse(args),
    );
    await _mountKnowledge(tester, client, refreshSignal: signal);
    await tester.tap(find.text('Architecture'));
    await tester.pump();
    signal.value++;
    await tester.pumpAndSettle();
    response.complete(_document);
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeDocumentReader), findsNothing);
  });

  testWidgets(
    'Journeys loads only when selected and Learning exposes evidence',
    (tester) async {
      var journeyBuilds = 0;
      final client = _uiClient((args) async => _defaultResponse(args));
      await _mountKnowledge(
        tester,
        client,
        journeysBuilder: () {
          journeyBuilds++;
          return const Text('Connected Journey picker');
        },
      );
      expect(journeyBuilds, 0);
      await tester.tap(find.text('Journeys'));
      await tester.pumpAndSettle();
      expect(find.text('Connected Journey picker'), findsOneWidget);
      await tester.tap(find.text('Learning'));
      await tester.pumpAndSettle();
      expect(find.text('Evidence and limitations'), findsOneWidget);
      await tester.tap(find.text('Evidence and limitations'));
      await tester.pumpAndSettle();
      expect(find.text('event-1'), findsOneWidget);
      expect(find.text('One success'), findsOneWidget);
      expect(find.text('One service'), findsOneWidget);
      expect(find.text('Review proposal'), findsOneWidget);
    },
  );

  testWidgets('Knowledge reader remains usable in a narrow window', (
    tester,
  ) async {
    final client = _uiClient((args) async => _defaultResponse(args));
    await _mountKnowledge(tester, client, size: const Size(480, 850));
    await tester.tap(find.text('Architecture'));
    await tester.pumpAndSettle();
    expect(find.text('Back to library'), findsOneWidget);
    expect(find.byType(KnowledgeDocumentReader), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Back to library'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('knowledge-library-list')), findsOneWidget);
  });

  test(
    'reading history persists locally, is bounded and isolates projects',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'knowledge-preferences-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final config = ExplorerConfig(
        projectRoot: '/project-a',
        manaRoot: '/mana',
        preferencesRoot: root.path,
      );
      final preferences = await ExplorerPreferences.load(config);
      final document = ManaKnowledgeDocumentSummary.fromJson(_summary);
      await preferences.rememberKnowledgeDocument('/project-a', document);
      await preferences.rememberKnowledgeDocument(
        '/project-b',
        ManaKnowledgeDocumentSummary.fromJson(_otherSummary),
      );
      await preferences.rememberKnowledgeDocument('/project-a', document);
      final loaded = await ExplorerPreferences.load(config);
      expect(
        loaded.recentKnowledgeDocuments['/project-a']!.single.id,
        document.id,
      );
      expect(
        loaded.recentKnowledgeDocuments['/project-b']!.single.title,
        'Recovery policy',
      );
      final content = File('${root.path}/preferences.json').readAsStringSync();
      expect(content, isNot(contains('exact_content')));
      expect(content, isNot(contains('passages')));
      await Future.wait([
        loaded.saveThemeMode(ThemeMode.dark),
        for (var i = 0; i < 12; i++)
          loaded.rememberKnowledgeDocument(
            '/project-a',
            ManaKnowledgeDocumentSummary.fromJson({
              ..._summary,
              'document_id': 'doc_${i.toRadixString(16).padLeft(24, '0')}',
            }),
          ),
      ]);
      final bounded = await ExplorerPreferences.load(config);
      expect(bounded.recentKnowledgeDocuments['/project-a'], hasLength(8));
      expect(bounded.themeMode.value, ThemeMode.dark);
    },
  );

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
    expect(find.text('Sources are up to date'), findsOneWidget);
    expect(find.text('Architecture'), findsOneWidget);
    expect(find.text('Learning review queue'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('refresh notification reloads Knowledge producer reads', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync(
      'familiar-knowledge-refresh-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/mana').writeAsStringSync('');
    final refresh = ValueNotifier(0);
    addTearDown(refresh.dispose);
    var reads = 0;
    var ready = 0;
    final client = ManaKnowledgeClient(
      projectRoot: root.path,
      run: (_, arguments, {workingDirectory}) async {
        reads++;
        return ProcessResult(
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
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnowledgeCenterPage(
            client: client,
            refreshSignal: refresh,
            onReady: () => ready++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 3);
    expect(ready, 1);
    refresh.value++;
    await tester.pumpAndSettle();
    expect(reads, 6);
    expect(ready, 2);
    expect(find.text('Architecture'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    refresh.value++;
    await tester.pump();
    expect(reads, 6);
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

ManaKnowledgeClient _uiClient(
  Future<Map<String, dynamic>> Function(List<String>) respond,
) {
  final root = Directory.systemTemp.createTempSync('knowledge-workspace-test-');
  addTearDown(() => root.deleteSync(recursive: true));
  File('${root.path}/mana').writeAsStringSync('');
  return ManaKnowledgeClient(
    projectRoot: root.path,
    run: (_, args, {workingDirectory}) async =>
        ProcessResult(1, 0, jsonEncode(await respond(args)), ''),
  );
}

Map<String, dynamic> _defaultResponse(List<String> args) =>
    args.contains('capabilities')
    ? _capabilities
    : args.contains('documents')
    ? _documents
    : args.contains('document')
    ? _document
    : args.contains('search')
    ? _search
    : _queue;

Future<void> _mountKnowledge(
  WidgetTester tester,
  ManaKnowledgeClient client, {
  Size size = const Size(1280, 1000),
  ValueListenable<int>? refreshSignal,
  Widget Function()? journeysBuilder,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: KnowledgeCenterPage(
          client: client,
          refreshSignal: refreshSignal,
          journeysBuilder: journeysBuilder,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _otherSummary = <String, dynamic>{
  ..._summary,
  'document_id': 'doc_bbbbbbbbbbbbbbbbbbbbbbbb',
  'title': 'Recovery policy',
  'source_reference': '.mana/global/recovery.md',
};

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
