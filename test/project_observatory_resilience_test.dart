import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/project_observatory_page.dart';

void main() {
  testWidgets('keeps semantic content visible with a refresh warning', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectObservatoryPage(
          client: ManaInspectClient(projectRoot: '/project'),
          knowledge: const SizedBox(),
          initialReadModel: ManaSemanticReadModel(
            project: ManaInspectProject.fromJson(_project),
            mode: ManaSemanticMode.fullSemantic,
            workItems: ManaWorkItemsResponse.fromJson(_workItems),
            refreshError: const ManaInspectException(
              ManaInspectFailure.command,
              'temporary failure',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Nothing needs attention'), findsOneWidget);
    expect(
      find.text('Refresh incomplete. Showing the last successful data.'),
      findsOneWidget,
    );
  });

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

const _workItems = {
  'schema': inspectWorkItemsSchema,
  'work_items': [],
  'coverage': 'none',
  'diagnostics': [],
};

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
