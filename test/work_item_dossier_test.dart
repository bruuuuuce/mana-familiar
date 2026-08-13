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
  testWidgets('dossier exposes only the seven stable semantic sections', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    for (final label in [
      'overview',
      'requirements',
      'plan',
      'decisions',
      'evidence',
      'review',
      'timeline',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('artifacts'), findsNothing);
  });
  testWidgets('dossier keeps work identity and review unknown state', (
    tester,
  ) async {
    await tester.pumpWidget(page(section: ManaSectionId.review));
    expect(find.text('feature:PROJ-24342'), findsOneWidget);
    expect(find.textContaining('Review state: unknown'), findsOneWidget);
  });
  testWidgets('work semantic dossier remains available', (tester) async {
    await tester.pumpWidget(
      page(
        mode: ManaSemanticMode.workSemantic,
        section: ManaSectionId.evidence,
      ),
    );
    expect(find.text('evidence'), findsOneWidget);
  });
}
