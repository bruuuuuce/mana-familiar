import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(
          File(
            '../mana/contracts/mana-inspect/v1/fixtures/$name',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  test('parses all frozen M10 semantic fixture responses', () {
    final list = ManaWorkItemsResponse.fromJson(fixture('work-items.json'));
    final detail = ManaWorkItemResponse.fromJson(
      fixture('feature-work-item.json'),
    );
    final sparse = ManaWorkItemResponse.fromJson(
      fixture('sparse-work-item.json'),
    );
    final context = ManaProjectContextResponse.fromJson(
      fixture('project-context.json'),
    );
    final activity = ManaActivityResponse.fromJson(fixture('activity.json'));
    expect(list.workItems.single.id, 'feature:PROJ-24342');
    expect(detail.sections.first.id, ManaSectionId.overview);
    expect(
      detail.sections.first.artifacts.single.workItemId,
      detail.workItem.id,
    );
    expect(sparse.workItem.title.value, isNull);
    expect(sparse.diagnostics.single.kind, 'malformed_canonical_source');
    expect(
      context.categories.where((c) => c.coverage == 'missing'),
      isNotEmpty,
    );
    expect(
      activity.events.last.timestampProvenance,
      ManaTimestampProvenance.filesystemMtimeEpoch,
    );
    expect(activity.events.last.kind, ManaActivityKind.artifactUpdated);
  });

  test('unknown additions and semantic enum values stay explicit and safe', () {
    final json = fixture('work-items.json');
    final item = (json['work_items'] as List).first as Map<String, dynamic>;
    item['work_item_type'] = 'future-type';
    item['lifecycle'] = {
      ...item['lifecycle'] as Map<String, dynamic>,
      'state': 'future',
    };
    item['future'] = true;
    final parsed = ManaWorkItemsResponse.fromJson(json);
    expect(parsed.workItems.single.type, ManaWorkItemType.unknown);
    expect(parsed.workItems.single.lifecycle.state, ManaLifecycleState.unknown);
  });

  test('rejects missing required semantic fields', () {
    final json = fixture('activity.json')..remove('events');
    expect(
      () => ManaActivityResponse.fromJson(json),
      throwsA(isA<ManaInspectException>()),
    );
  });

  test('negotiates full, work-only, and legacy modes', () {
    ManaInspectProject project(List<Map<String, String>> operations) =>
        ManaInspectProject.fromJson({
          'schema': inspectProjectSchema,
          'project_id': 'project:test',
          'framework': const {},
          'mana': const {'present': true},
          'operations': operations,
        });
    final work = [
      {'name': 'work-items', 'schema': inspectWorkItemsSchema},
      {'name': 'work-item', 'schema': inspectWorkItemSchema},
    ];
    expect(
      project([
        ...work,
        {'name': 'project-context', 'schema': inspectProjectContextSchema},
        {'name': 'activity', 'schema': inspectActivitySchema},
      ]).semanticMode,
      ManaSemanticMode.fullSemantic,
    );
    expect(project(work).semanticMode, ManaSemanticMode.workSemantic);
    expect(project(const []).semanticMode, ManaSemanticMode.legacyCatalog);
  });

  test('uses the exact stable work-item id as one process argument', () async {
    final root = await Directory.systemTemp.createTemp('semantic-inspect-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/mana').writeAsString('');
    final calls = <List<String>>[];
    final client = ManaInspectClient(
      projectRoot: root.path,
      run: (_, args, {workingDirectory}) async {
        calls.add(args);
        final response = args.contains('project')
            ? _projectWithSemantic
            : fixture('feature-work-item.json');
        return ProcessResult(0, 0, jsonEncode(response), '');
      },
    );
    await client.workItem('feature:PROJ-24342');
    expect(calls.last, [
      'inspect',
      'work-item',
      'feature:PROJ-24342',
      '--json',
    ]);
  });

  test(
    'one refresh invokes each supported operation once and survives optional failure',
    () async {
      final root = await Directory.systemTemp.createTemp('semantic-refresh-');
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/mana').writeAsString('');
      final calls = <String>[];
      final client = ManaInspectClient(
        projectRoot: root.path,
        run: (_, args, {workingDirectory}) async {
          final operation = args[args.indexOf('inspect') + 1];
          calls.add(operation);
          if (operation == 'project') {
            return ProcessResult(0, 0, jsonEncode(_projectWithSemantic), '');
          }
          if (operation == 'activity') {
            return ProcessResult(0, 5, '', 'unavailable');
          }
          final file = switch (operation) {
            'artifacts' => 'mixed-artifacts.json',
            'work-items' => 'work-items.json',
            'project-context' => 'project-context.json',
            _ => 'activity.json',
          };
          return ProcessResult(0, 0, jsonEncode(fixture(file)), '');
        },
      );
      final repository = ManaSemanticRepository(client);
      final result = await Future.wait([
        repository.refresh(),
        repository.refresh(),
      ]);
      expect(result.first.workItems, isNotNull);
      expect(result.first.projectContext, isNotNull);
      expect(result.first.refreshError, isNotNull);
      expect(calls.where((call) => call == 'project'), hasLength(1));
      expect(calls.toSet().length, calls.length);
    },
  );
}

const _projectWithSemantic = {
  'schema': inspectProjectSchema,
  'project_id': 'project:test',
  'framework': {'compatibility': 'mana-inspect/v1'},
  'mana': {'present': true},
  'operations': [
    {'name': 'project', 'schema': inspectProjectSchema},
    {'name': 'artifacts', 'schema': inspectArtifactsSchema},
    {'name': 'work-items', 'schema': inspectWorkItemsSchema},
    {'name': 'work-item', 'schema': inspectWorkItemSchema},
    {'name': 'project-context', 'schema': inspectProjectContextSchema},
    {'name': 'activity', 'schema': inspectActivitySchema},
  ],
};
