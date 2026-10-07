import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/journey_graph.dart';
import 'package:mana_familiar/journey_reading.dart';
import 'package:mana_familiar/main.dart';
import 'package:mana_familiar/presentation/explorer_page.dart';
import 'package:mana_familiar/presentation/journey_reading_view.dart';

Map<String, dynamic> paymentGraph({String revision = 'v1'}) => {
  'schema': JourneyGraph.supportedSchema,
  'journey': {
    'id': 'payment',
    'title': 'Payment request',
    'repository_revision': revision,
    'entry_node_id': 'entry',
    'scope': {
      'start': {'kind': 'symbol', 'value': 'PaymentController.submit'},
      'termination': {'kind': 'boundary', 'condition': 'Provider boundary'},
      'boundaries': {'max_depth': 4},
    },
  },
  'nodes': [
    {'id': 'entry', 'label': 'Receive payment', 'state': 'expanded'},
    {'id': 'provider', 'label': 'Call provider', 'state': 'discovered'},
    {'id': 'retry', 'label': 'Retry payment', 'state': 'discovered'},
    {'id': 'audit', 'label': 'Audit trail', 'state': 'discovered'},
  ],
  'edges': [
    {
      'id': 'entry-provider',
      'from': 'entry',
      'to': 'provider',
      'kind': 'CALLS',
      'rationale': 'Inspect the external call and its timeout.',
    },
    {'id': 'entry-retry', 'from': 'entry', 'to': 'retry', 'kind': 'CALLS'},
    {
      'id': 'entry-audit',
      'from': 'entry',
      'to': 'audit',
      'kind': 'RELATED_TO',
      'disposition': 'deferred',
    },
  ],
  'anchors': [
    {
      'id': 'entry-source',
      'node_id': 'entry',
      'path': 'PaymentController.java',
      'range': {'start_line': 2, 'end_line': 3},
    },
    {
      'id': 'test-source',
      'node_id': 'provider',
      'path': 'PaymentTest.java',
      'range': {'start_line': 1, 'end_line': 2},
    },
  ],
  'evidence': [
    {
      'id': 'entry-evidence',
      'anchor_id': 'entry-source',
      'kind': 'source_range',
      'summary': 'Delegates the request to the payment service.',
    },
    {
      'id': 'timeout-evidence',
      'anchor_id': 'test-source',
      'kind': 'test',
      'summary': 'A timeout case is recorded.',
    },
  ],
  'explanations': [
    {
      'id': 'entry-explanation',
      'subject_node_id': 'entry',
      'status': 'completed',
      'body': 'The controller delegates to **PaymentService**.',
      'epistemic_status': 'documented',
      'evidence_ids': ['entry-evidence', 'timeout-evidence'],
    },
    {
      'id': 'failed-explanation',
      'subject_node_id': 'retry',
      'status': 'failed',
      'body': 'FAILED BODY MUST NOT BECOME A FINDING',
    },
  ],
  'hypotheses': [
    {
      'id': 'timeout-hypothesis',
      'subject_node_id': 'entry',
      'claim': 'The timeout may avoid retaining worker threads.',
      'confidence': 'plausible',
      'verification_suggestions': [
        'Check pool retention under a delayed provider.',
      ],
      'supports': ['timeout-evidence'],
    },
  ],
};

JourneyGraph graph([String revision = 'v1']) =>
    JourneyGraph(paymentGraph(revision: revision));

void main() {
  test(
    'opening a step never marks it read; changes preserve notes and invalidate clarity',
    () {
      final original = const JourneyReadingProgress()
          .reconcile(graph())
          .update(nodeId: 'entry');
      expect(original.markers, isEmpty);
      final saved = original.update(
        nodeId: 'provider',
        status: JourneyReadingStatus.clear,
        note: 'Check provider timeout.',
      );
      final same = JourneyReadingProgress.fromJson(
        saved.toJson(),
      ).reconcile(graph());
      expect(same.lastNodeId, 'provider');
      expect(same.statusFor('provider'), JourneyReadingStatus.clear);
      expect(same.changed, isFalse);
      final changed = same.reconcile(graph('v2'));
      expect(changed.statusFor('provider'), JourneyReadingStatus.revisit);
      expect(changed.notes['provider'], 'Check provider timeout.');
      expect(changed.changed, isTrue);
      expect(
        changed.acknowledgeChange().statusFor('provider'),
        JourneyReadingStatus.revisit,
      );
      expect(changed.acknowledgeChange().changed, isFalse);
      final removed = paymentGraph();
      (removed['nodes'] as List).removeWhere(
        (node) => node['id'] == 'provider',
      );
      final reconciled = saved.reconcile(JourneyGraph(removed));
      expect(reconciled.lastNodeId, isNull);
      expect(reconciled.notes, isEmpty);
      expect(reconciled.markers, isEmpty);
    },
  );

  test(
    'record order is irrelevant; changes to an explanation invalidate reading markers',
    () {
      final reordered = paymentGraph();
      reordered['nodes'] = (reordered['nodes'] as List).reversed.toList();
      reordered['edges'] = (reordered['edges'] as List).reversed.toList();
      expect(
        journeyReadingSignature(JourneyGraph(reordered)),
        journeyReadingSignature(graph()),
      );
      final changed = paymentGraph();
      (changed['explanations'] as List).first['body'] = 'A revised explanation';
      expect(
        journeyReadingSignature(JourneyGraph(changed)),
        isNot(journeyReadingSignature(graph())),
      );
    },
  );

  test(
    'reading state is bounded and malformed markers cannot corrupt preferences',
    () {
      var progress = const JourneyReadingProgress();
      for (var i = 0; i < 2050; i++) {
        progress = progress.update(
          nodeId: 'node-$i',
          status: JourneyReadingStatus.read,
        );
      }
      for (var i = 0; i < 210; i++) {
        progress = progress.update(nodeId: 'node-$i', note: 'x' * 4100);
      }
      expect(progress.markers.length, 2000);
      expect(progress.notes.length, 200);
      expect(progress.notes['node-209']!.length, 4000);
      final parsed = JourneyReadingProgress.fromJson({
        'markers': {'a': 'verified', 'b': 'clear', 3: 'read', 'c': null},
        'notes': {'b': 'a note', 'd': 42},
      });
      expect(parsed.markers, {'b': JourneyReadingStatus.clear});
      expect(parsed.notes, {'b': 'a note'});
      expect(
        progress
            .update(
              nodeId: 'node-209',
              note: '',
              status: JourneyReadingStatus.unread,
            )
            .notes
            .containsKey('node-209'),
        isFalse,
      );
    },
  );

  test(
    'preferences isolate projects, survive reload, and store no source bodies',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'journey-reading-pref-',
      );
      addTearDown(() => root.delete(recursive: true));
      final config = ExplorerConfig(
        projectRoot: root.path,
        manaRoot: root.path,
        preferencesRoot: '${root.path}/prefs',
      );
      final preferences = await ExplorerPreferences.load(config);
      final progress = const JourneyReadingProgress()
          .reconcile(graph())
          .update(
            nodeId: 'provider',
            status: JourneyReadingStatus.clear,
            note: 'My question',
          );
      await Future.wait([
        preferences.saveReadingProgress('/project-a', 'payment', progress),
        preferences.saveReadingProgress(
          '/project-b',
          'payment',
          progress.update(
            nodeId: 'entry',
            status: JourneyReadingStatus.revisit,
          ),
        ),
        preferences.saveThemeMode(ThemeMode.dark),
      ]);
      final reloaded = await ExplorerPreferences.load(config);
      expect(
        reloaded.readingProgress('/project-a', 'payment').lastNodeId,
        'provider',
      );
      expect(
        reloaded.readingProgress('/project-b', 'payment').lastNodeId,
        'entry',
      );
      expect(reloaded.themeMode.value, ThemeMode.dark);
      final raw = await File(
        '${root.path}/prefs/preferences.json',
      ).readAsString();
      expect(raw, contains('My question'));
      expect(raw, isNot(contains('The controller delegates')));
      expect(raw, isNot(contains('PaymentController.java')));
    },
  );

  testWidgets(
    'reading flow presents evidence, manual markers, notes and branch choices; resumes after restart',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = await setup(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: ExplorerPage(
            store: fixture.store,
            preferences: fixture.preferences,
          ),
        ),
      );
      await frames(tester);
      expect(find.byType(JourneyReadingView), findsOneWidget);
      expect(find.text('Support: documented'), findsOneWidget);
      expect(
        find.text('0 marked read · 0 to review · 4 known steps'),
        findsOneWidget,
      );
      expect(
        find.text(
          'This step has several primary continuations. Choose the branch you want to examine.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Inspect the external call and its timeout.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<JourneyReadingView>(find.byType(JourneyReadingView))
            .source
            ?.contents,
        contains('return service.submit'),
      );
      expect(
        find.textContaining('return service.submit', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('FAILED BODY'), findsNothing);

      // Cross-file evidence opens its exact source, preserving the current node.
      await tester.ensureVisible(find.text('A timeout case is recorded.'));
      await tester.tap(find.text('A timeout case is recorded.'));
      await frames(tester);
      expect(find.text('PaymentTest.java:1-2'), findsWidgets);
      expect(find.text('SOURCE WORKSPACE'), findsOneWidget);
      await tester.tap(find.text('Read'));
      await frames(tester);

      final status = find.byKey(const ValueKey('reading-status'));
      await tester.ensureVisible(status);
      await tester.tap(status);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear to me').last);
      await frames(tester);
      expect(
        find.text('1 marked read · 0 to review · 4 known steps'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Add personal note'));
      await tester.tap(find.text('Add personal note'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Why is the provider timeout bounded?',
      );
      await tester.tap(find.text('Save note'));
      await frames(tester);
      await tester.ensureVisible(find.text('Continue to Call provider'));
      await tester.tap(find.text('Continue to Call provider'));
      await frames(tester);
      expect(
        find.textContaining('No explanation is recorded for this step.'),
        findsOneWidget,
      );
      expect(find.textContaining('End of this branch.'), findsOneWidget);
      await tester.ensureVisible(find.text('Review this journey'));
      await tester.tap(find.text('Review this journey'));
      await tester.pumpAndSettle();
      expect(
        find.text('3 steps have no recorded explanation.'),
        findsOneWidget,
      );
      await tester.tap(find.text('With notes'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Why is the provider timeout bounded?'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(JourneyReadingSummary),
          matching: find.text('Retry payment'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Close'));
      await frames(tester);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      late ExplorerPreferences reloaded;
      await tester.runAsync(() async {
        reloaded = await ExplorerPreferences.load(fixture.config);
      });
      expect(
        reloaded.readingProgress(fixture.root.path, 'payment').lastNodeId,
        'provider',
      );
      expect(
        reloaded.readingProgress(fixture.root.path, 'payment').notes['entry'],
        'Why is the provider timeout bounded?',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ExplorerPage(store: fixture.store, preferences: reloaded),
        ),
      );
      await frames(tester);
      expect(find.text('Receive payment  ›  Call provider'), findsOneWidget);
      expect(find.textContaining('End of this branch.'), findsOneWidget);
      expect(
        await tester.runAsync(() => fixture.artifact.readAsString()),
        jsonEncode(paymentGraph()),
      );
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
    },
  );

  testWidgets(
    'refreshing a removed current step falls back safely; narrow layout keeps reading controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = await setup(tester);
      await tester.runAsync(
        () => fixture.preferences.saveReadingProgress(
          fixture.root.path,
          'payment',
          const JourneyReadingProgress()
              .reconcile(graph())
              .update(
                nodeId: 'provider',
                status: JourneyReadingStatus.clear,
                note: 'Timeout question',
              ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ExplorerPage(
            store: fixture.store,
            preferences: fixture.preferences,
          ),
        ),
      );
      await frames(tester);
      expect(find.textContaining('End of this branch.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final changed = paymentGraph(revision: 'v2');
      (changed['nodes'] as List).removeWhere(
        (item) => item['id'] == 'provider',
      );
      (changed['edges'] as List).removeWhere(
        (item) => item['to'] == 'provider',
      );
      await tester.runAsync(
        () => fixture.artifact.writeAsString(jsonEncode(changed)),
      );
      await tester.tap(find.byTooltip('Refresh'));
      await frames(tester);
      expect(find.text('Receive payment'), findsWidgets);
      expect(find.textContaining('This Journey changed.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Dismiss change notice'));
      await frames(tester);
      expect(find.textContaining('This Journey changed.'), findsNothing);
      await tester.ensureVisible(find.text('Add personal note'));
      await tester.tap(find.text('Add personal note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
    },
  );

  testWidgets(
    'a delayed old hydration cannot replace a refreshed journey context',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = await setup(tester);
      final store = DelayedHydrationStore(fixture.config);
      addTearDown(() => store.updates.close());
      await tester.pumpWidget(
        MaterialApp(
          home: ExplorerPage(store: store, preferences: fixture.preferences),
        ),
      );
      await frames(tester);
      expect(store.labelCalls, 1);
      store.current = JourneyGraph(
        paymentGraph(revision: 'v2')..['anchors'] = [],
      );
      store.updates.add(null);
      await frames(tester);
      expect(store.labelCalls, 2);
      store.firstLabels.complete([
        {'key': 'obsolete context'},
      ]);
      await frames(tester);
      await tester.tap(find.text('Source'));
      await frames(tester);
      expect(find.text('fresh context'), findsOneWidget);
      expect(find.text('obsolete context'), findsNothing);
      expect(
        fixture.preferences
            .readingProgress(fixture.root.path, 'payment')
            .signature,
        journeyReadingSignature(store.current),
      );
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
    },
  );

  testWidgets('picker reports content coverage and the saved resume point', (
    tester,
  ) async {
    final fixture = await setup(tester);
    await tester.runAsync(
      () => fixture.preferences.saveReadingProgress(
        fixture.root.path,
        'payment',
        const JourneyReadingProgress()
            .reconcile(graph())
            .update(nodeId: 'retry', status: JourneyReadingStatus.revisit),
      ),
    );
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPickerPage(
          store: fixture.store,
          preferences: fixture.preferences,
          onOpenJourney: (id) => opened = id,
        ),
      ),
    );
    await frames(tester);
    expect(
      find.textContaining('4 known steps · 1 explained step'),
      findsOneWidget,
    );
    expect(find.textContaining('Resume from Retry payment'), findsOneWidget);
    await tester.tap(find.text('Payment request'));
    expect(opened, 'payment');
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });
}

Future<
  ({
    Directory root,
    File artifact,
    ExplorerConfig config,
    JourneyStore store,
    ExplorerPreferences preferences,
  })
>
setup(WidgetTester tester) async {
  late Directory root;
  late File artifact;
  late ExplorerConfig config;
  late ExplorerPreferences preferences;
  await tester.runAsync(() async {
    root = await Directory.systemTemp.createTemp('journey-reading-flow-');
    artifact = File('${root.path}/journey.json');
    await artifact.writeAsString(jsonEncode(paymentGraph()));
    await File('${root.path}/PaymentController.java').writeAsString(
      'class PaymentController {\n  Payment submit(Request request) {\n    return service.submit(request);\n  }\n}',
    );
    await File(
      '${root.path}/PaymentTest.java',
    ).writeAsString('timeout_is_bounded();\nassert_no_retained_threads();');
    config = ExplorerConfig(
      projectRoot: root.path,
      manaRoot: root.path,
      preferencesRoot: '${root.path}/prefs',
      fixturePath: artifact.path,
    );
    preferences = await ExplorerPreferences.load(config);
  });
  addTearDown(() => root.deleteSync(recursive: true));
  return (
    root: root,
    artifact: artifact,
    config: config,
    store: JourneyStore(config),
    preferences: preferences,
  );
}

Future<void> frames(WidgetTester tester) async {
  for (var frame = 0; frame < 32; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
}

class DelayedHydrationStore extends JourneyStore {
  DelayedHydrationStore(super.config);
  JourneyGraph current = JourneyGraph(paymentGraph()..['anchors'] = []);
  final updates = StreamController<void>.broadcast();
  final firstLabels = Completer<List<Map<String, dynamic>>>();
  int labelCalls = 0;

  @override
  Future<List<String>> list() async => ['payment'];
  @override
  Future<JourneyGraph> load(String id) async => current;
  @override
  Stream<void> watch(String id) => updates.stream;
  @override
  Future<List<Map<String, dynamic>>> labels(String id, String node) {
    labelCalls++;
    return labelCalls == 1
        ? firstLabels.future
        : Future.value([
            {'key': 'fresh context'},
          ]);
  }
}
