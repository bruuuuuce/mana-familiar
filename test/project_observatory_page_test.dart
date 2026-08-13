import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
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
    expect(
      find.text('Mana-reported operational timeline; no synthetic events.'),
      findsOneWidget,
    );
    await tester.tap(find.text('verification:failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Artifact detail'), findsOneWidget);
    expect(find.text('Mana verification result'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('Activity'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('Project overview'), findsOneWidget);
    await tester.tap(find.text('Reviews'));
    await tester.pump();
    expect(find.text('Review Inbox'), findsOneWidget);
    await tester.tap(find.text('Knowledge'));
    await tester.pump();
    expect(find.text('Journeys'), findsOneWidget);
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
