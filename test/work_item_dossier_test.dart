import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/project_observatory_page.dart';
import 'package:mana_familiar/semantic_navigation.dart';

Map<String, dynamic> _f(String name) =>
    jsonDecode(
          File(
            '../mana/contracts/mana-inspect/v1/fixtures/$name',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
void main() {
  final item = ManaWorkItemsResponse.fromJson(_f('work-items.json'));
  ManaSemanticReadModel model(ManaSemanticMode mode) => ManaSemanticReadModel(
    project: ManaInspectProject.fromJson({
      'schema': inspectProjectSchema,
      'project_id': 'project:test',
      'framework': const {},
      'mana': const {'present': true},
      'operations': const [],
    }),
    mode: mode,
    workItems: item,
    activity: ManaActivityResponse.fromJson(_f('activity.json')),
  );
  Widget page({
    ManaSemanticMode mode = ManaSemanticMode.fullSemantic,
    ManaSectionId? section,
  }) => MaterialApp(
    home: ProjectObservatoryPage(
      client: ManaInspectClient(projectRoot: '/project'),
      knowledge: const SizedBox(),
      initialReadModel: model(mode),
      initialRoute: ObservatoryRoute(
        destination: ObservatoryDestination.work,
        workItemId: item.workItems.single.id,
        section: section,
      ),
      artifactDetailLoader: (_) async => ManaInspectArtifactDetail.fromJson({
        'schema': inspectArtifactSchema,
        'artifact': {
          'artifact_id': 'file:.mana/features/PROJ-24342/index.md',
          'path': '.mana/features/PROJ-24342/index.md',
          'family': 'semantic',
          'kind': 'markdown',
          'status': 'available',
        },
        'payload': {'content_type': 'text/markdown', 'content': '# Document'},
        'relations': [],
      }),
    ),
  );
  testWidgets(
    'work item opens directly in Overview with stable section navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(page());
      for (final label in [
        'Overview',
        'Requirements',
        'Plan',
        'Decisions',
        'Evidence',
        'Review',
        'Timeline',
      ]) {
        expect(find.text(label), findsAtLeastNWidgets(1));
      }
      expect(find.text('artifacts'), findsNothing);
      expect(
        find.text('Choose a section to explore this work item.'),
        findsNothing,
      );
      expect(find.text('Dossier'), findsNothing);
      expect(find.text('Overview'), findsAtLeastNWidgets(2));

      await tester.tap(find.text('Requirements').first);
      await tester.pump();
      expect(find.text('Requirements'), findsAtLeastNWidgets(2));
      await tester.tap(find.text('Plan').first);
      await tester.pump();
      expect(find.text('Plan'), findsAtLeastNWidgets(2));
      await tester.tap(find.text('Evidence').first);
      await tester.pump();
      expect(find.text('Evidence'), findsAtLeastNWidgets(2));
    },
  );
  testWidgets('dossier keeps work identity and review unknown state', (
    tester,
  ) async {
    await tester.pumpWidget(page(section: ManaSectionId.review));
    expect(find.text('PROJ-24342'), findsAtLeastNWidgets(1));
    expect(
      find.text('Mana has not reported a review state for this work item.'),
      findsOneWidget,
    );
  });
  testWidgets('work semantic dossier remains available', (tester) async {
    await tester.pumpWidget(
      page(
        mode: ManaSemanticMode.workSemantic,
        section: ManaSectionId.evidence,
      ),
    );
    expect(find.text('Evidence'), findsAtLeastNWidgets(2));
  });
}
