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

ManaSemanticReadModel _noAttentionModel() => ManaSemanticReadModel(
  project: ManaInspectProject.fromJson({
    'schema': inspectProjectSchema,
    'project_id': 'project:test',
    'framework': const {},
    'mana': const {'present': true},
    'operations': const [],
  }),
  mode: ManaSemanticMode.fullSemantic,
  workItems: const ManaWorkItemsResponse(
    workItems: [],
    coverage: 'complete',
    diagnostics: [],
  ),
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
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(page(ManaSemanticMode.fullSemantic));
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.byKey(const Key('cockpit-brand-logo')), findsOneWidget);
    expect(find.text('Project observatory'), findsOneWidget);
    expect(find.text('Nothing needs attention'), findsNothing);
    expect(find.text('Nothing needs typed attention'), findsNothing);
    expect(find.text('Active / relevant work'), findsOneWidget);
    expect(find.text('Project context'), findsOneWidget);
    expect(find.text('View all project knowledge'), findsOneWidget);
    expect(find.text('Review summary'), findsNothing);
    await tester.tap(find.text('Activity').first);
    await tester.pump();
    expect(find.text('Verification completed: passed.'), findsOneWidget);
    expect(find.textContaining('30 May 2026'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pump();
    expect(find.text('PROJ-24342'), findsOneWidget);
  });
  testWidgets(
    'cockpit summarizes context and links to the full Knowledge destination',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(page(ManaSemanticMode.fullSemantic));
      await tester.tap(find.text('View all project knowledge'));
      await tester.pump();
      expect(find.text('Knowledge'), findsAtLeastNWidgets(1));
      expect(find.text('Project decisions'), findsOneWidget);
    },
  );
  testWidgets(
    'compact healthy state does not use technical attention wording',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectObservatoryPage(
            client: ManaInspectClient(projectRoot: '/project'),
            knowledge: const SizedBox(),
            initialReadModel: _noAttentionModel(),
          ),
        ),
      );
      expect(find.text('Nothing needs attention'), findsOneWidget);
      expect(
        find.text('Mana has not reported any issues requiring action.'),
        findsOneWidget,
      );
      expect(find.text('Nothing needs typed attention'), findsNothing);
    },
  );
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
    expect(find.text('PROJ-24342'), findsAtLeastNWidgets(2));
  });
  testWidgets('humanizes Knowledge category labels', (tester) async {
    await tester.pumpWidget(page(ManaSemanticMode.fullSemantic));
    await tester.tap(find.text('Knowledge'));
    await tester.pump();
    expect(find.text('Project decisions'), findsOneWidget);
    expect(find.text('Engineering guards'), findsOneWidget);
  });
  testWidgets('work semantic cockpit degrades unavailable project surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(page(ManaSemanticMode.workSemantic));
    await tester.tap(find.text('Knowledge'));
    await tester.pump();
    expect(
      find.text('Project context is unavailable for this capability mode.'),
      findsOneWidget,
    );
  });
}
