import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/review_inbox_model.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/project_observatory_page.dart';
import 'package:mana_familiar/presentation/review_inbox_page.dart';
import 'package:mana_familiar/semantic_navigation.dart';

import 'support/large_catalog_fixture.dart';

void main() {
  test(
    'parses and derives the large mixed catalog within a bounded local time',
    () {
      final stopwatch = Stopwatch()..start();
      final catalog = ManaInspectCatalog.fromJson(largeCatalogFixture());
      final inbox = ReviewInboxModel.fromCatalog(catalog);
      stopwatch.stop();

      expect(catalog.artifacts, hasLength(largeCatalogArtifactCount));
      expect(inbox.items, isNotEmpty);
      expect(
        catalog.artifacts.where((artifact) => artifact.status == 'malformed'),
        isNotEmpty,
      );
      expect(
        catalog.artifacts.first.raw['relations'],
        contains(
          isA<Map>().having(
            (relation) => relation['to'],
            'cycle target',
            'artifact:00000001',
          ),
        ),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      // This makes the local measurement visible in CI logs without turning it
      // into a hardware-independent product-performance claim.
      // ignore: avoid_print
      print(
        'F10 large catalog: ${catalog.artifacts.length} artifacts, '
        '${inbox.items.length} inbox items in ${stopwatch.elapsedMilliseconds}ms',
      );
    },
  );

  testWidgets('uses a lazy list delegate for the large review inbox', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final catalog = ManaInspectCatalog.fromJson(largeCatalogFixture());
    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewInboxPage(
            artifacts: catalog.artifacts,
            onOpenArtifact: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    stopwatch.stop();

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
    expect(find.text('Limited catalog mode'), findsOneWidget);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    // ignore: avoid_print
    print(
      'F10 lazy review layout: ${catalog.artifacts.length} artifacts in '
      '${stopwatch.elapsedMilliseconds}ms',
    );
  });

  testWidgets('keeps large semantic Work and Activity surfaces bounded', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final stopwatch = Stopwatch()..start();
    final workItems = ManaWorkItemsResponse.fromJson({
      'schema': inspectWorkItemsSchema,
      'work_items': [
        for (var index = 0; index < 1000; index++)
          {
            'work_item_id': 'feature:SCALE-$index',
            'work_item_type': 'feature',
            'external_ticket_id': {
              'value': 'SCALE-$index',
              'provenance': 'explicit_workspace_manifest',
            },
            'title': {'value': null, 'provenance': 'unavailable'},
            'purpose': {'value': null, 'provenance': 'unavailable'},
            'branch': {'value': null, 'provenance': 'unavailable'},
            'canonical_branch': null,
            'lifecycle': {
              'state': 'unknown',
              'provenance': 'unavailable',
              'coverage': 'unknown',
            },
            'review': {
              'state': 'unknown',
              'provenance': 'unavailable',
              'coverage': 'unknown',
            },
            'attention_items': <Object>[],
            'artifacts': <Object>[],
          },
      ],
      'coverage': 'canonical_workspace_manifests',
      'diagnostics': <Object>[],
    });
    final activity = ManaActivityResponse.fromJson({
      'schema': inspectActivitySchema,
      'events': [
        for (var index = 0; index < 2500; index++)
          {
            'event_id': 'event-$index',
            'timestamp': {
              'value': '2026-08-14T09:00:00Z',
              'provenance': 'explicit_domain_timestamp',
            },
            'event_kind': 'unknown',
            'work_item_id': null,
            'related_artifact_ids': <Object>[],
            'summary': null,
            'provenance': 'explicit_workspace_manifest',
          },
      ],
      'coverage': 'explicit_structured_events',
      'diagnostics': <Object>[],
    });
    final project = ManaInspectProject.fromJson({
      'schema': inspectProjectSchema,
      'project_id': 'project:scale',
      'framework': {'compatibility': 'mana-inspect/v1'},
      'mana': {'present': true},
      'operations': const [
        {'name': 'work-items', 'schema': inspectWorkItemsSchema},
        {'name': 'work-item', 'schema': inspectWorkItemSchema},
        {'name': 'project-context', 'schema': inspectProjectContextSchema},
        {'name': 'activity', 'schema': inspectActivitySchema},
      ],
    });
    final model = ManaSemanticReadModel(
      project: project,
      mode: ManaSemanticMode.fullSemantic,
      workItems: workItems,
      activity: activity,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectObservatoryPage(
          client: ManaInspectClient(projectRoot: '/project'),
          knowledge: const SizedBox(),
          initialReadModel: model,
          initialRoute: const ObservatoryRoute(
            destination: ObservatoryDestination.work,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('SCALE-0'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pump();
    expect(find.text('Project'), findsWidgets);
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    // ignore: avoid_print
    print(
      'F16 semantic scale: ${workItems.workItems.length} work items and '
      '${activity.events.length} events in ${stopwatch.elapsedMilliseconds}ms',
    );
  });
}
