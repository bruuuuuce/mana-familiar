import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/project_observatory_page.dart';

void main() {
  for (final scenario in [
    (
      name: 'complete successful empty attention permits a positive conclusion',
      coverage: 'complete',
      refreshFailed: false,
      attention: false,
      positive: true,
      state: 'Nothing needs attention',
    ),
    (
      name: 'partial successful empty attention limits the conclusion',
      coverage: 'partial',
      refreshFailed: false,
      attention: false,
      positive: false,
      state: 'Attention data is partial',
    ),
    (
      name: 'none successful empty attention is not determinable',
      coverage: 'none',
      refreshFailed: false,
      attention: false,
      positive: false,
      state: 'Attention data is unavailable',
    ),
    (
      name: 'failed refresh with empty attention does not reassure',
      coverage: 'complete',
      refreshFailed: true,
      attention: false,
      positive: false,
      state: 'Attention data may be stale',
    ),
    (
      name: 'failed refresh preserves reported attention as stale',
      coverage: 'complete',
      refreshFailed: true,
      attention: true,
      positive: false,
      state: 'Needs attention (last data may be stale)',
    ),
  ]) {
    testWidgets(scenario.name, (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectObservatoryPage(
            client: ManaInspectClient(projectRoot: '/project'),
            knowledge: const SizedBox(),
            initialReadModel: _model(
              coverage: scenario.coverage,
              refreshFailed: scenario.refreshFailed,
              attention: scenario.attention,
            ),
          ),
        ),
      );

      expect(find.text(scenario.state), findsOneWidget);
      expect(
        find.text('Nothing needs attention'),
        scenario.positive ? findsOneWidget : findsNothing,
      );
      if (scenario.refreshFailed) {
        expect(
          find.text('Refresh incomplete. Showing the last successful data.'),
          findsOneWidget,
        );
      }
      if (scenario.attention) {
        expect(find.text('Payment verification failed'), findsOneWidget);
      } else if (!scenario.positive) {
        expect(find.text('Refresh data'), findsOneWidget);
        expect(find.textContaining('cannot be determined'), findsOneWidget);
      }
    });
  }

  testWidgets(
    'suppresses stale detail responses and reuses the current revision cache',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final first = Completer<ManaInspectArtifactDetail>();
      final second = Completer<ManaInspectArtifactDetail>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectObservatoryPage(
            client: ManaInspectClient(projectRoot: '/project'),
            knowledge: const SizedBox(),
            initialCatalog: ManaInspectCatalog.fromJson(_catalog),
            artifactDetailLoader: (_) =>
                ++calls == 1 ? first.future : second.future,
          ),
        ),
      );

      await tester.tap(find.text('Advanced'));
      await tester.pump();
      await tester.tap(find.text('verification:one'));
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.tap(find.text('verification:one'));
      await tester.pump();
      expect(calls, 2);

      second.complete(_detail('PASSED'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Overall result: PASSED'), findsOneWidget);

      first.complete(_detail('FAILED'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Overall result: PASSED'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.tap(find.text('verification:one'));
      await tester.pump();
      expect(calls, 2);
      expect(find.text('Overall result: PASSED'), findsOneWidget);
    },
  );
}

const _catalog = {
  'schema': inspectArtifactsSchema,
  'artifacts': [_summary],
  'guarantees': {},
  'diagnostics': [],
};

const _project = {
  'schema': inspectProjectSchema,
  'project_id': 'project:test',
  'framework': {'compatibility': 'mana-inspect/v1'},
  'mana': {'present': true},
  'operations': [
    {'name': 'work-items', 'schema': inspectWorkItemsSchema},
    {'name': 'work-item', 'schema': inspectWorkItemSchema},
    {'name': 'project-context', 'schema': inspectProjectContextSchema},
    {'name': 'activity', 'schema': inspectActivitySchema},
  ],
};

ManaSemanticReadModel _model({
  required String coverage,
  required bool refreshFailed,
  required bool attention,
}) {
  const field = ManaProvenance.explicitWorkspaceManifest;
  final items = attention
      ? [
          ManaWorkItemSummary(
            id: 'feature:PAY-42',
            type: ManaWorkItemType.feature,
            externalTicketId: const ManaSemanticField(
              value: 'PAY-42',
              provenance: field,
            ),
            title: const ManaSemanticField(
              value: 'Prevent duplicate payments',
              provenance: field,
            ),
            purpose: const ManaSemanticField(value: null, provenance: field),
            branch: const ManaSemanticField(value: null, provenance: field),
            canonicalBranch: true,
            lifecycle: const ManaLifecycle(
              ManaLifecycleState.blocked,
              field,
              'complete',
            ),
            review: const ManaReview(ManaReviewState.unknown, field, 'none'),
            attentionItems: const [
              ManaAttentionItem(
                id: 'verification-failed',
                category: 'verification',
                severity: 'error',
                workItemId: 'feature:PAY-42',
                relatedArtifactIds: [],
                provenance: field,
                label: 'Payment verification failed',
              ),
            ],
            artifacts: const [],
          ),
        ]
      : const <ManaWorkItemSummary>[];
  return ManaSemanticReadModel(
    project: ManaInspectProject.fromJson(_project),
    mode: ManaSemanticMode.fullSemantic,
    workItems: ManaWorkItemsResponse(
      workItems: items,
      coverage: coverage,
      diagnostics: const [],
    ),
    refreshError: refreshFailed
        ? const ManaInspectException(
            ManaInspectFailure.command,
            'temporary failure',
          )
        : null,
  );
}

const _summary = {
  'artifact_id': 'verification:one',
  'path': '.mana/verification/one.json',
  'family': 'workspace',
  'kind': 'verification-result',
  'status': 'failed',
  'revision_id':
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
};

ManaInspectArtifactDetail _detail(String result) =>
    ManaInspectArtifactDetail.fromJson({
      'schema': inspectArtifactSchema,
      'artifact': _summary,
      'payload': {'schema': 'mana.verification.result/v2', 'result': result},
      'relations': [],
    });
