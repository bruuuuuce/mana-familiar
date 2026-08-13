import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/project_observatory_page.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(
          File(
            '../mana/contracts/mana-inspect/v1/fixtures/$name',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

ManaSemanticReadModel _model(ManaSemanticMode mode) => ManaSemanticReadModel(
  project: ManaInspectProject.fromJson({
    'schema': inspectProjectSchema,
    'project_id': 'project:test',
    'framework': const {},
    'mana': const {'present': true},
    'operations': const [],
  }),
  mode: mode,
  workItems: ManaWorkItemsResponse.fromJson(_fixture('work-items.json')),
  projectContext: mode == ManaSemanticMode.fullSemantic
      ? ManaProjectContextResponse.fromJson(_fixture('project-context.json'))
      : null,
  activity: mode == ManaSemanticMode.fullSemantic
      ? ManaActivityResponse.fromJson(_fixture('activity.json'))
      : null,
);

void main() {
  Widget page(ManaSemanticMode mode) => MaterialApp(
    home: ProjectObservatoryPage(
      client: ManaInspectClient(projectRoot: '/project'),
      knowledge: const SizedBox(),
      initialReadModel: _model(mode),
    ),
  );
  testWidgets('full semantic cockpit uses typed work context and activity', (
    tester,
  ) async {
    await tester.pumpWidget(page(ManaSemanticMode.fullSemantic));
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Active / relevant work'), findsOneWidget);
    expect(find.text('Project context'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pump();
    expect(find.text('feature:PROJ-24342'), findsOneWidget);
  });
  testWidgets('work controls filter and search typed work fields', (
    tester,
  ) async {
    await tester.pumpWidget(page(ManaSemanticMode.workSemantic));
    await tester.tap(find.text('Work'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'no-match');
    await tester.pump();
    expect(find.text('No work items match these controls.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'PROJ-24342');
    await tester.pump();
    expect(find.text('feature:PROJ-24342'), findsOneWidget);
  });
  testWidgets('work semantic cockpit degrades unavailable project surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(page(ManaSemanticMode.workSemantic));
    expect(
      find.text('Project context is unavailable in WORK_SEMANTIC mode.'),
      findsOneWidget,
    );
  });
}
