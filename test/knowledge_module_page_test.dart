import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/knowledge_module_page.dart';

void main() {
  testWidgets('keeps Journeys as the Knowledge entry point', (tester) async {
    await tester.pumpWidget(_module());

    expect(find.text('Existing Journey Explorer'), findsOneWidget);
    expect(find.text('Concepts'), findsOneWidget);
  });

  testWidgets('shows only matching Mana catalog artifacts per section', (
    tester,
  ) async {
    ManaInspectArtifactSummary? opened;
    await tester.pumpWidget(
      _module(onOpenArtifact: (artifact) => opened = artifact),
    );

    await tester.tap(find.text('Concepts'));
    await tester.pump();
    expect(find.text('concept:payments'), findsOneWidget);
    expect(find.text('architecture:payment-flow'), findsNothing);

    await tester.tap(find.text('concept:payments'));
    expect(opened?.id, 'concept:payments');

    await tester.tap(find.text('Architecture'));
    await tester.pump();
    expect(find.text('architecture:payment-flow'), findsOneWidget);

    await tester.tap(find.text('Rationale'));
    await tester.pump();
    expect(find.text('decision:retry-policy'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pump();
    expect(find.text('history:run-42'), findsOneWidget);

    await tester.tap(find.text('Candidates'));
    await tester.pump();
    expect(find.text('learning-candidate:retry'), findsOneWidget);
  });

  testWidgets('opens a Journey parent declared by a Journey record path', (
    tester,
  ) async {
    String? requestedJourney;
    await tester.pumpWidget(
      _module(
        journeysBuilder: (journeyId) {
          requestedJourney = journeyId;
          return Text('Journey explorer: $journeyId');
        },
      ),
    );

    await tester.tap(find.text('Concepts'));
    await tester.pump();
    await tester.tap(find.text('Journey'));
    await tester.pump();

    expect(requestedJourney, 'jrn_000000000000000000000000');
    expect(
      find.text('Journey explorer: jrn_000000000000000000000000'),
      findsOneWidget,
    );
  });
}

Widget _module({
  ValueChanged<ManaInspectArtifactSummary>? onOpenArtifact,
  Widget Function(String? journeyId)? journeysBuilder,
}) => MaterialApp(
  home: Scaffold(
    body: KnowledgeModulePage(
      journeys: const Text('Existing Journey Explorer'),
      journeysBuilder: journeysBuilder,
      artifacts: _artifacts,
      onOpenArtifact: onOpenArtifact ?? (_) {},
    ),
  ),
);

final _artifacts = [
  _artifact(
    'journey:payments',
    'knowledge',
    'journey',
    '.mana/learning/journeys/jrn_000000000000000000000000/journey.yaml',
  ),
  _artifact(
    'concept:payments',
    'knowledge',
    'journey_record',
    '.mana/learning/journeys/jrn_000000000000000000000000/records/occ-concept_occurrence.yaml',
  ),
  _artifact(
    'architecture:payment-flow',
    'knowledge',
    'journey_record',
    '.mana/learning/journeys/jrn_000000000000000000000000/records/dia-diagram.yaml',
  ),
  _artifact(
    'decision:retry-policy',
    'governance',
    'decision',
    '.mana/decisions/retry.yaml',
  ),
  _artifact(
    'history:run-42',
    'workspace',
    'history',
    '.mana/history/run-42.json',
  ),
  _artifact(
    'learning-candidate:retry',
    'learning',
    'file',
    '.mana/learning/candidates/retry.json',
  ),
];

ManaInspectArtifactSummary _artifact(
  String id,
  String family,
  String kind,
  String path,
) => ManaInspectArtifactSummary.fromJson({
  'artifact_id': id,
  'path': path,
  'family': family,
  'kind': kind,
  'status': 'available',
});
