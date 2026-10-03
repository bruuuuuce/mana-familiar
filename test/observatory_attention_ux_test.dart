import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/project_observatory_page.dart';
import 'package:mana_familiar/semantic_navigation.dart';

const _source = ManaProvenance.explicitWorkspaceManifest;

ManaAttentionItem attention({
  String id = 'duplicate-charge',
  String workItemId = 'feature:PAY-42',
  String? nextAction = 'Inspect retry evidence before another review.',
}) => ManaAttentionItem(
  id: id,
  category: 'verification',
  severity: 'error',
  workItemId: workItemId,
  relatedArtifactIds: const [],
  provenance: _source,
  label: id == 'duplicate-charge'
      ? 'Duplicate charge detected'
      : 'Retry evidence is incomplete',
  nextAction: nextAction,
);

ManaWorkItemSummary work({
  String id = 'feature:PAY-42',
  String ticket = 'PAY-42',
  String title = 'Prevent duplicate payments',
  ManaLifecycleState lifecycle = ManaLifecycleState.blocked,
  ManaReview? review,
  List<ManaAttentionItem> attentionItems = const [],
}) => ManaWorkItemSummary(
  id: id,
  type: ManaWorkItemType.feature,
  externalTicketId: ManaSemanticField(value: ticket, provenance: _source),
  title: ManaSemanticField(value: title, provenance: _source),
  purpose: const ManaSemanticField(value: null, provenance: _source),
  branch: const ManaSemanticField(value: null, provenance: _source),
  canonicalBranch: true,
  lifecycle: ManaLifecycle(lifecycle, _source, 'complete'),
  review:
      review ?? const ManaReview(ManaReviewState.unknown, _source, 'complete'),
  attentionItems: attentionItems,
  artifacts: const [],
);

ManaSemanticReadModel model(List<ManaWorkItemSummary> items) =>
    ManaSemanticReadModel(
      project: ManaInspectProject.fromJson({
        'schema': inspectProjectSchema,
        'project_id': 'synthetic:attention-ux',
        'framework': const {},
        'mana': const {'present': true},
        'operations': const [],
      }),
      mode: ManaSemanticMode.fullSemantic,
      workItems: ManaWorkItemsResponse(
        workItems: items,
        coverage: 'complete',
        diagnostics: const [],
      ),
    );

Widget page(
  List<ManaWorkItemSummary> items, {
  ManaSectionId? section,
  String? workItemId,
  double textScale = 1,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: ProjectObservatoryPage(
      client: ManaInspectClient(projectRoot: '/synthetic'),
      knowledge: const SizedBox(),
      initialReadModel: model(items),
      initialRoute: workItemId == null
          ? null
          : ObservatoryRoute(
              destination: ObservatoryDestination.work,
              workItemId: workItemId,
              section: section,
            ),
    ),
  ),
);

void main() {
  testWidgets(
    'blocked dossier shows cause, work identity, severity and next action',
    (tester) async {
      await tester.pumpWidget(
        page([
          work(attentionItems: [attention()]),
        ], workItemId: 'feature:PAY-42'),
      );

      expect(find.text('Why this work is blocked'), findsOneWidget);
      expect(find.text('Duplicate charge detected'), findsOneWidget);
      expect(find.text('Verification'), findsOneWidget);
      expect(find.text('error'), findsOneWidget);
      expect(
        find.text('Work: PAY-42 — Prevent duplicate payments'),
        findsOneWidget,
      );
      expect(find.text('Work ID: feature:PAY-42'), findsOneWidget);
      expect(
        find.text('Next action: Inspect retry evidence before another review.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'blocked dossier honestly reports absent next action and keeps each cause',
    (tester) async {
      await tester.pumpWidget(
        page([
          work(
            attentionItems: [
              attention(nextAction: null),
              attention(id: 'retry-evidence'),
            ],
          ),
        ], workItemId: 'feature:PAY-42'),
      );

      expect(
        find.text('Next action: Mana did not report one.'),
        findsOneWidget,
      );
      expect(find.text('Retry evidence is incomplete'), findsOneWidget);
    },
  );

  testWidgets('dossier does not invent a blocked-attention container', (
    tester,
  ) async {
    await tester.pumpWidget(
      page([work(attentionItems: const [])], workItemId: 'feature:PAY-42'),
    );
    expect(find.text('Why this work is blocked'), findsNothing);
    expect(find.textContaining('Next action:'), findsNothing);
  });

  testWidgets('blocked action stays laid out at compact 130 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longAction =
        'Inspect retry evidence and the duplicate-charge receipt before requesting another review from the payment provider.';
    await tester.pumpWidget(
      page(
        [
          work(attentionItems: [attention(nextAction: longAction)]),
        ],
        workItemId: 'feature:PAY-42',
        textScale: 1.3,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Next action: $longAction'), findsOneWidget);
  });

  testWidgets(
    'overview makes a resolved attention-to-work association explicit and navigates there',
    (tester) async {
      await tester.pumpWidget(
        page([
          work(attentionItems: [attention()]),
          work(
            id: 'feature:PAY-43',
            ticket: 'PAY-43',
            title: 'Reconcile provider settlements',
            lifecycle: ManaLifecycleState.inProgress,
          ),
        ]),
      );
      expect(
        find.text('Verification · Work: PAY-42 — Prevent duplicate payments'),
        findsOneWidget,
      );
      await tester.tap(find.text('Duplicate charge detected'));
      await tester.pumpAndSettle();
      expect(find.text('PAY-42'), findsAtLeastNWidgets(1));
      expect(find.text('PAY-43'), findsNothing);
    },
  );

  testWidgets(
    'overview does not navigate an unresolved attention association',
    (tester) async {
      final unresolved = attention(workItemId: 'feature:MISSING-9');
      await tester.pumpWidget(
        page([
          work(attentionItems: [unresolved]),
          work(id: 'feature:PAY-43', ticket: 'PAY-43', title: 'Another work'),
        ]),
      );
      expect(
        find.text('Verification · Work association unavailable (MISSING-9)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Duplicate charge detected'));
      await tester.pumpAndSettle();
      expect(
        find.text('Verification · Work association unavailable (MISSING-9)'),
        findsOneWidget,
      );
    },
  );

  for (final state in [
    (
      name: 'unknown is not approval',
      review: const ManaReview(ManaReviewState.unknown, _source, 'complete'),
      text: 'Mana reports the review state as unknown for this work item.',
    ),
    (
      name: 'approval remains explicit',
      review: const ManaReview(ManaReviewState.approved, _source, 'complete'),
      text: 'Review state: Approved',
    ),
    (
      name: 'pending remains explicit',
      review: const ManaReview(ManaReviewState.pending, _source, 'complete'),
      text: 'Review state: Pending',
    ),
    (
      name: 'unavailable review data is not unknown approval',
      review: const ManaReview(
        ManaReviewState.unknown,
        ManaProvenance.unavailable,
        'none',
      ),
      text: 'Mana could not provide review information for this work item.',
    ),
  ]) {
    testWidgets('review state: ${state.name}', (tester) async {
      await tester.pumpWidget(
        page(
          [work(review: state.review)],
          workItemId: 'feature:PAY-42',
          section: ManaSectionId.review,
        ),
      );
      expect(find.text(state.text), findsOneWidget);
      if (state.review.state == ManaReviewState.unknown) {
        expect(find.textContaining('Approved'), findsNothing);
      }
    });
  }
}
