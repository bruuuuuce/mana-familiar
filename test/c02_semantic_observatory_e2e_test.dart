import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/artifact_renderer.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/artifact_detail_view.dart';

void main() {
  final projectRoot = Platform.environment['C02_PROJECT_ROOT'];
  final manaRoot = Platform.environment['C02_MANA_ROOT'];
  final outputRoot = Platform.environment['C02_OUTPUT_ROOT'];

  test(
    'consumes every real semantic operation in FULL_SEMANTIC mode',
    () async {
      expect(projectRoot, isNotNull);
      expect(manaRoot, isNotNull);
      final client = ManaInspectClient(
        projectRoot: projectRoot!,
        manaRoot: manaRoot!,
      );
      final repository = ManaSemanticRepository(client);
      final model = await repository.refresh();

      expect(model.mode, ManaSemanticMode.fullSemantic);
      expect(model.catalog, isNotNull);
      expect(
        model.workItems!.workItems.map((item) => item.type),
        containsAll([ManaWorkItemType.feature, ManaWorkItemType.session]),
      );
      expect(model.projectContext!.categories, hasLength(8));
      expect(
        model.activity!.events.map((event) => event.timestampProvenance),
        containsAll([
          ManaTimestampProvenance.explicitDomainTimestamp,
          ManaTimestampProvenance.filesystemMtimeEpoch,
        ]),
      );

      final detail = await repository.workItem(
        'feature:FEAT-ACCEPT',
        model.project,
      );
      expect(
        detail.attentionItems.map((item) => item.category),
        containsAll([
          'failed_verification',
          'stale_evidence',
          'pending_decision',
        ]),
      );
      final document = detail.sections
          .firstWhere((section) => section.id == ManaSectionId.requirements)
          .artifacts
          .single;
      final artifact = await client.artifact(document.id);
      expect(
        ArtifactRendererRegistry.standard()
            .render(ArtifactRenderContext.fromDetail(artifact))
            .view,
        ArtifactPayloadView.markdown,
      );
      expect((await client.source('README.md')).availability, 'present');
    },
    skip: projectRoot == null || manaRoot == null
        ? 'Run through tests/run-c02-semantic-observatory-harness.sh.'
        : false,
  );

  test(
    'real output snapshots parse without reordering producer activity',
    () {
      expect(outputRoot, isNotNull);
      Map<String, dynamic> response(String name) =>
          jsonDecode(File('$outputRoot/$name.json').readAsStringSync())
              as Map<String, dynamic>;

      final activity = ManaActivityResponse.fromJson(response('activity'));
      final rawIds = (response('activity')['events'] as List)
          .map((event) => (event as Map)['event_id'])
          .toList();
      expect(activity.events.map((event) => event.id), orderedEquals(rawIds));
      expect(
        ManaWorkItemsResponse.fromJson(response('work-items')).workItems,
        hasLength(2),
      );
      expect(
        ManaWorkItemResponse.fromJson(response('work-item')).sections,
        isNotEmpty,
      );
      expect(
        ManaProjectContextResponse.fromJson(
          response('project-context'),
        ).categories,
        hasLength(8),
      );
      expect(
        ManaInspectArtifactDetail.fromJson(response('artifact')).artifact.id,
        isNotEmpty,
      );
      expect(
        ManaInspectSourceRelations.fromJson(response('source')).path,
        'README.md',
      );
    },
    skip: outputRoot == null
        ? 'Run through tests/run-c02-semantic-observatory-harness.sh.'
        : false,
  );

  test('controlled capability sets select only their frozen modes', () {
    ManaSemanticMode mode(List<Map<String, String>> operations) =>
        ManaInspectProject.fromJson({
          'schema': inspectProjectSchema,
          'project_id': 'project:controlled',
          'framework': {'compatibility': 'mana-inspect/v1'},
          'mana': {'present': true},
          'operations': operations,
        }).semanticMode;
    const work = [
      {'name': 'work-items', 'schema': inspectWorkItemsSchema},
      {'name': 'work-item', 'schema': inspectWorkItemSchema},
    ];
    expect(
      mode([
        ...work,
        {'name': 'project-context', 'schema': inspectProjectContextSchema},
        {'name': 'activity', 'schema': inspectActivitySchema},
      ]),
      ManaSemanticMode.fullSemantic,
    );
    expect(mode(work), ManaSemanticMode.workSemantic);
    expect(
      mode(const [
        {'name': 'artifacts', 'schema': inspectArtifactsSchema},
      ]),
      ManaSemanticMode.legacyCatalog,
    );
  });

  testWidgets('hostile Markdown stays inert in Reader and Source', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longCode = List.filled(4096, 'x').join();
    final hostile =
        '''
# Safe heading
<script>alert(1)</script>
<iframe src="file:///etc/passwd"></iframe>
[script](javascript:alert(1)) [file](file:///etc/passwd)
![remote](https://example.invalid/pixel.png)
<object data="../secret"></object>
[absolute](/etc/passwd) [traversal](../secret) [encoded](%2e%2e/secret)
control\u{0000}character [malformed](
```text
$longCode
```
''';
    final summary = ManaInspectArtifactSummary.fromJson(const {
      'artifact_id': 'file:.mana/document.md',
      'path': '.mana/document.md',
      'family': 'workspace',
      'kind': 'markdown',
      'status': 'available',
    });
    final detail = ManaInspectArtifactDetail.fromJson({
      'schema': inspectArtifactSchema,
      'artifact': summary.raw,
      'payload': {'included': true, 'kind': 'text', 'value': hostile},
      'relations': const [],
    });
    var sourceCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtifactDetailView(
            artifact: summary,
            detail: detail,
            documentPresentation: true,
            sourceLoader: (_) async {
              sourceCalls++;
              throw StateError('Document content must not trigger source IO.');
            },
          ),
        ),
      ),
    );
    expect(find.text('Safe heading'), findsWidgets);
    expect(find.textContaining('alert(1)'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(sourceCalls, 0);

    await tester.tap(find.text('Metadata'));
    await tester.pump();
    expect(sourceCalls, 0);

    await tester.tap(find.text('Source'));
    await tester.pump();
    expect(find.textContaining('<script>alert(1)</script>'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(sourceCalls, 0);
  });
}
