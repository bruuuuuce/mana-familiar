import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/artifact_detail_view.dart';

void main() {
  testWidgets('shows verification facts without calling it approval', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ArtifactDetailView(
          artifact: _summary('verification-result'),
          detail: ManaInspectArtifactDetail.fromJson({
            'schema': inspectArtifactSchema,
            'artifact': _summaryJson('verification-result'),
            'payload': {
              'schema': 'mana.verification.result/v2',
              'result': 'FAILED',
              'checks': [
                {'name': 'tests', 'status': 'FAILED'},
              ],
            },
            'relations': [],
          }),
        ),
      ),
    );
    expect(
      find.text('Overall result: FAILED', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text(
        'Verification evidence is not an approval or merge decision.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('tests: FAILED', skipOffstage: false), findsOneWidget);
  });

  testWidgets('states bounded repair result does not make a merge decision', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ArtifactDetailView(
          artifact: _summary('repair-result'),
          detail: ManaInspectArtifactDetail.fromJson({
            'schema': inspectArtifactSchema,
            'artifact': _summaryJson('repair-result'),
            'payload': {
              'schema': 'mana.repair.bounded/v1',
              'final_result': 'REGRESSED',
              'attempt_count': 2,
            },
            'relations': [],
          }),
        ),
      ),
    );
    expect(
      find.text('Final result: REGRESSED', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('RESOLVED does not mean merge-ready.', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Attempts: 2', skipOffstage: false), findsOneWidget);
  });

  testWidgets(
    'opens a non-cyclic related artifact only when the host resolves it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: ArtifactDetailView(
            artifact: _summary('verification-result'),
            onOpenRelatedArtifact: (id) => opened = id,
            detail: ManaInspectArtifactDetail.fromJson({
              'schema': inspectArtifactSchema,
              'artifact': _summaryJson('verification-result'),
              'payload': {'schema': 'mana.verification.result/v2'},
              'relations': [
                {'to': 'repair:one', 'kind': 'repair'},
                {'to': 'verification-result:one', 'kind': 'cycle'},
              ],
            }),
          ),
        ),
      );
      await tester.tap(find.text('repair:one', skipOffstage: false));
      expect(opened, 'repair:one');
      expect(
        tester
            .widget<ListTile>(
              find
                  .ancestor(
                    of: find.text(
                      'verification-result:one',
                      skipOffstage: false,
                    ),
                    matching: find.byType(ListTile),
                  )
                  .last,
            )
            .onTap,
        isNull,
      );
    },
  );

  testWidgets('keeps review recommendation advisory and approval explicit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ArtifactDetailView(
          artifact: _summary('review-findings'),
          detail: ManaInspectArtifactDetail.fromJson({
            'schema': inspectArtifactSchema,
            'artifact': _summaryJson('review-findings'),
            'payload': {
              'schema': 'mana.review.findings/v1',
              'findings': [
                {
                  'severity': 'blocker',
                  'summary': 'Missing test',
                  'source_reference': 'lib/a.dart:10',
                },
              ],
              'missing_tests': ['integration'],
              'recommendation': 'Request human review',
            },
            'relations': [],
          }),
        ),
      ),
    );
    expect(
      find.text('blocker: Missing test • lib/a.dart:10', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text(
        'Approval requirement was not declared by Mana.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Recommendation (advisory): Request human review',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text('Raw payload (bounded)', skipOffstage: false),
      findsOneWidget,
    );
  });
}

ManaInspectArtifactSummary _summary(String kind) =>
    ManaInspectArtifactSummary.fromJson(_summaryJson(kind));

Map<String, dynamic> _summaryJson(String kind) => {
  'artifact_id': '$kind:one',
  'path': '.mana/$kind.json',
  'family': 'verification',
  'kind': kind,
  'status': 'available',
};
