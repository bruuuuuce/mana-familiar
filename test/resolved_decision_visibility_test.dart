import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/human_feedback.dart';
import 'package:mana_familiar/presentation/human_feedback_panel.dart';

void main() {
  testWidgets('shows the resolved choice from the current producer plan', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HumanDecisionPanel(
            repository: _ResolvedRepository(),
            sourcePath: 'plan.json',
            target: const HumanFeedbackTarget(
              projectId: 'project:test',
              artifactId: 'file:plan.json',
              artifactRevision: 'sha256:plan',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resolved decisions in the current plan'), findsOneWidget);
    expect(find.text('Which option?'), findsOneWidget);
    expect(find.text('Chosen B'), findsOneWidget);
    expect(find.byType(RadioListTile<String>), findsNothing);
  });

  test(
    'rejects a projected choice outside the published alternatives',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'familiar-decision-choice-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/mana').writeAsStringSync('');
      final repository = ManaHumanFeedbackRepository(
        projectRoot: root.path,
        run: (_, _, _) async => HumanFeedbackCommandResult(
          exitCode: 0,
          stderr: '',
          stdout: jsonEncode({
            'schemaVersion': 'mana.human-feedback.decision-targets/v1',
            'sourcePath': 'plan.json',
            'sourceRevision': 'sha256:plan',
            'decisions': [
              {
                'decisionId': 'decision_a',
                'question': 'Which option?',
                'status': 'resolved',
                'selectedOptionId': 'foreign',
                'options': [
                  {'optionId': 'b', 'label': 'Chosen B', 'summary': 'Use B'},
                ],
              },
            ],
          }),
        ),
      );
      await expectLater(
        repository.decisionTargets('plan.json'),
        throwsFormatException,
      );
    },
  );
  testWidgets('long decision remains bounded at 200 percent', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: HumanDecisionPanel(
              repository: _LongDecisionRepository(),
              sourcePath: 'plan.json',
              target: const HumanFeedbackTarget(
                projectId: 'project:test',
                artifactId: 'file:plan.json',
                artifactRevision: 'sha256:plan',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('decision-target')), findsOneWidget);
  });
}

class _ResolvedRepository extends Fake implements ManaHumanFeedbackRepository {
  @override
  Future<HumanDecisionTargets> decisionTargets(String sourcePath) async =>
      const HumanDecisionTargets(
        sourcePath: 'plan.json',
        sourceRevision: 'sha256:plan',
        decisions: [
          HumanDecisionTarget(
            id: 'decision_a',
            question: 'Which option?',
            status: 'resolved',
            selectedOptionId: 'b',
            options: [
              HumanDecisionOption(id: 'b', label: 'Chosen B', summary: 'Use B'),
            ],
          ),
        ],
      );
  @override
  Future<HumanDecisionState> decisionState(String decisionId) async =>
      HumanDecisionState(
        decisionId: decisionId,
        revision: '0',
        selectedOptionId: null,
      );
}

class _LongDecisionRepository extends _ResolvedRepository {
  @override
  Future<HumanDecisionTargets> decisionTargets(
    String sourcePath,
  ) async => const HumanDecisionTargets(
    sourcePath: 'plan.json',
    sourceRevision: 'sha256:plan',
    decisions: [
      HumanDecisionTarget(
        id: 'open',
        question:
            'Which solution should preserve draft text and reconcile the selected alternative in the regenerated implementation plan?',
        status: 'open',
        options: [
          HumanDecisionOption(
            id: 'a',
            label: 'Alternative A',
            summary: 'Preserve the local draft.',
          ),
        ],
      ),
    ],
  );
}
