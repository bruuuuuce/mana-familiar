import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/application/mana_workspace_watcher.dart';
import 'package:mana_familiar/presentation/project_observatory_page.dart';

void main() {
  Widget observatory(ManaInspectCatalog catalog) => MaterialApp(
    home: ProjectObservatoryPage(
      key: ValueKey(catalog.partial),
      client: ManaInspectClient(projectRoot: '/project'),
      knowledge: const Text('Knowledge module'),
      initialCatalog: catalog,
    ),
  );

  testWidgets('shows overview attention and stable top-level navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = ManaInspectClient(
      projectRoot: '/project',
      snapshotPath: '/snapshot.json',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectObservatoryPage(
          client: client,
          knowledge: const Text('Knowledge module'),
          initialCatalog: ManaInspectCatalog.fromJson(_catalog),
          artifactDetailLoader: (_) async =>
              ManaInspectArtifactDetail.fromJson(_detail),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Project overview'), findsOneWidget);
    expect(
      find.text(
        'Semantic cockpit is unavailable in legacy catalog mode. Use Advanced for the catalog.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Activity'));
    await tester.pump();
    expect(find.text('Semantic activity is unavailable'), findsOneWidget);
    await tester.tap(find.text('Advanced'));
    await tester.pump();
    await tester.tap(find.text('verification:failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Artifact detail'), findsOneWidget);
    expect(find.text('Mana verification result'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('Artifact catalog'), findsAtLeastNWidgets(1));
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('Semantic activity is unavailable'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('Project overview'), findsOneWidget);
    await tester.tap(find.text('Reviews'));
    await tester.pump();
    expect(find.text('Limited catalog mode'), findsOneWidget);
    await tester.tap(find.text('Knowledge'));
    await tester.pump();
    expect(find.text('Legacy journeys'), findsOneWidget);
  });

  testWidgets('makes empty and partial catalog state explicit', (tester) async {
    await tester.pumpWidget(
      observatory(
        ManaInspectCatalog.fromJson({
          'schema': inspectArtifactsSchema,
          'artifacts': const [],
          'guarantees': const {},
          'diagnostics': const [],
        }),
      ),
    );
    expect(find.text('Empty project catalog'), findsOneWidget);

    await tester.pumpWidget(
      observatory(
        ManaInspectCatalog.fromJson({
          'schema': inspectArtifactsSchema,
          'artifacts': [
            {
              'artifact_id': 'available',
              'path': '.mana/available.json',
              'family': 'workspace',
              'kind': 'file',
              'status': 'available',
            },
            'not-an-artifact',
          ],
          'guarantees': const {},
          'diagnostics': const [],
        }),
      ),
    );
    await tester.pump();
    expect(find.text('Partial catalog'), findsOneWidget);
  });

  testWidgets(
    'marks Refresh when the Mana workspace changes and clears it manually',
    (tester) async {
      final watcher = _FakeWatcher();
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectObservatoryPage(
            client: ManaInspectClient(projectRoot: '/project'),
            knowledge: const Text('Knowledge module'),
            initialCatalog: ManaInspectCatalog.fromJson(_catalog),
            watcher: watcher,
            onRefresh: () async {},
          ),
        ),
      );
      await tester.pump();
      watcher.add(ManaWorkspaceWatchEvent.changed);
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('refresh-button')))
            .isSelected,
        isTrue,
      );
      expect(
        find.byKey(const Key('refresh-pending-indicator')),
        findsOneWidget,
      );
      expect(find.byTooltip('Refresh — changes detected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('refresh-button')));
      await tester.pump();

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('refresh-button')))
            .isSelected,
        isFalse,
      );
      expect(find.byKey(const Key('refresh-pending-indicator')), findsNothing);
    },
  );

  testWidgets('shows a non-blocking warning when .mana cannot be watched', (
    tester,
  ) async {
    final watcher = _FakeWatcher();
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectObservatoryPage(
          client: ManaInspectClient(projectRoot: '/project'),
          knowledge: const Text('Knowledge module'),
          initialCatalog: ManaInspectCatalog.fromJson(_catalog),
          watcher: watcher,
        ),
      ),
    );
    watcher.add(ManaWorkspaceWatchEvent.unavailable);
    await tester.pump();

    expect(
      find.text(
        'Changes to .mana cannot be observed. Refresh remains available manually.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('refresh-button')), findsOneWidget);
  });

  testWidgets('disposes the Mana workspace watcher', (tester) async {
    final watcher = _FakeWatcher();
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectObservatoryPage(
          client: ManaInspectClient(projectRoot: '/project'),
          knowledge: const Text('Knowledge module'),
          initialCatalog: ManaInspectCatalog.fromJson(_catalog),
          watcher: watcher,
        ),
      ),
    );

    await tester.pumpWidget(const SizedBox());

    expect(watcher.disposed, isTrue);
  });
}

class _FakeWatcher implements ManaWorkspaceWatcher {
  final StreamController<ManaWorkspaceWatchEvent> _events =
      StreamController.broadcast();
  var disposed = false;

  @override
  Stream<ManaWorkspaceWatchEvent> get events => _events.stream;

  void add(ManaWorkspaceWatchEvent event) => _events.add(event);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }

  @override
  Future<void> start() async {}
}

const _catalog = {
  'schema': 'mana.inspect.artifacts/v1',
  'artifacts': [
    {
      'artifact_id': 'verification:failed',
      'path': '.mana/result.json',
      'family': 'workspace',
      'kind': 'verification-result',
      'status': 'failed',
    },
  ],
  'guarantees': {},
  'diagnostics': [],
};

const _detail = {
  'schema': 'mana.inspect.artifact/v1',
  'artifact': {
    'artifact_id': 'verification:failed',
    'path': '.mana/result.json',
    'family': 'workspace',
    'kind': 'verification-result',
    'status': 'failed',
  },
  'payload': {'summary': 'safe'},
  'relations': [],
};
