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

  test('preserves M13 Activity target metadata without reconstruction', () {
    final json = fixture('activity.json');
    final event = (json['events'] as List).first as Map<String, dynamic>;
    event['target'] = const {
      'artifact_id': 'file:.mana/features/PROJ-24342/plan.md',
      'work_item_id': 'feature:PROJ-24342',
      'section_id': 'plan',
      'project_context_category': null,
      'label': 'Technical Task Breakdown',
    };

    final target = ManaActivityResponse.fromJson(json).events.first.target!;
    expect(target.artifactId, 'file:.mana/features/PROJ-24342/plan.md');
    expect(target.workItemId, 'feature:PROJ-24342');
    expect(target.sectionId, ManaSectionId.plan);
    expect(target.projectContextCategory, isNull);
    expect(target.label, 'Technical Task Breakdown');
  });

  test('rejects malformed M13 Activity target ownership and categories', () {
    Map<String, dynamic> activityWithTarget(Map<String, dynamic> target) {
      final json = fixture('activity.json');
      (json['events'] as List).first['target'] = target;
      return json;
    }

    const base = <String, dynamic>{
      'artifact_id': 'file:.mana/global/architecture.md',
      'work_item_id': null,
      'section_id': null,
      'project_context_category': 'architecture',
      'label': 'Architecture',
    };
    expect(
      () => ManaActivityResponse.fromJson(
        activityWithTarget({...base, 'work_item_id': 'PROJ-24342'}),
      ),
      throwsA(isA<ManaInspectException>()),
    );
    expect(
      () => ManaActivityResponse.fromJson(
        activityWithTarget({...base, 'project_context_category': 'roadmap'}),
      ),
      throwsA(isA<ManaInspectException>()),
    );
    expect(
      () => ManaActivityResponse.fromJson(
        activityWithTarget({...base, 'section_id': 'made-up'}),
      ),
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

  test('defers the raw catalog until Advanced requests it', () async {
    final root = await Directory.systemTemp.createTemp('semantic-catalog-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/mana').writeAsString('');
    final calls = <String>[];
    final client = ManaInspectClient(
      projectRoot: root.path,
      run: (_, args, {workingDirectory}) async {
        final operation = args[args.indexOf('inspect') + 1];
        calls.add(operation);
        final response = switch (operation) {
          'project' => _projectWithSemantic,
          'artifacts' => fixture('mixed-artifacts.json'),
          'work-items' => fixture('work-items.json'),
          'project-context' => fixture('project-context.json'),
          'activity' => fixture('activity.json'),
          _ => throw StateError('Unexpected operation: $operation'),
        };
        return ProcessResult(0, 0, jsonEncode(response), '');
      },
    );
    final repository = ManaSemanticRepository(client);

    final initial = await repository.initialLoad();
    expect(initial.catalog, isNull);
    expect(calls, isNot(contains('artifacts')));
    expect(initial.workItems, isNotNull);
    expect(initial.projectContext, isNull);
    expect(initial.activity, isNull);

    final withCatalog = await repository.loadCatalog();
    expect(withCatalog.catalog, isNotNull);
    expect(calls.where((operation) => operation == 'artifacts'), hasLength(1));

    final completed = await repository.loadSupportingSurfaces();
    expect(completed.projectContext, isNotNull);
    expect(completed.activity, isNotNull);
  });

  test(
    'later refresh failures retain prior data without leaking across modes',
    () async {
      final root = await Directory.systemTemp.createTemp('semantic-retain-');
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/mana').writeAsString('');
      var generation = 0;
      final client = ManaInspectClient(
        projectRoot: root.path,
        run: (_, args, {workingDirectory}) async {
          final operation = args[args.indexOf('inspect') + 1];
          if (operation == 'project') generation++;
          if (generation == 2 && operation == 'activity') {
            return ProcessResult(0, 5, '', 'temporarily unavailable');
          }
          if (generation == 3 && operation == 'project') {
            return ProcessResult(
              0,
              0,
              jsonEncode({
                ..._projectWithSemantic,
                'operations': const [
                  {'name': 'project', 'schema': inspectProjectSchema},
                  {'name': 'artifacts', 'schema': inspectArtifactsSchema},
                ],
              }),
              '',
            );
          }
          final response = switch (operation) {
            'project' => _projectWithSemantic,
            'artifacts' => fixture('mixed-artifacts.json'),
            'work-items' => fixture('work-items.json'),
            'project-context' => fixture('project-context.json'),
            'activity' => fixture('activity.json'),
            _ => throw StateError(operation),
          };
          return ProcessResult(0, 0, jsonEncode(response), '');
        },
      );
      final repository = ManaSemanticRepository(client);

      final first = await repository.refresh();
      final second = await repository.refresh();
      final legacy = await repository.refresh();

      expect(first.activity, isNotNull);
      expect(second.activity, same(first.activity));
      expect(second.refreshError, isNotNull);
      expect(legacy.mode, ManaSemanticMode.legacyCatalog);
      expect(legacy.workItems, isNull);
      expect(legacy.projectContext, isNull);
      expect(legacy.activity, isNull);
    },
  );

  test(
    'rejects invalid identity, ownership, paths, sections, and duplicates',
    () {
      final duplicateWork = fixture('work-items.json');
      (duplicateWork['work_items'] as List).add(
        jsonDecode(jsonEncode((duplicateWork['work_items'] as List).first)),
      );
      expect(
        () => ManaWorkItemsResponse.fromJson(duplicateWork),
        throwsA(isA<ManaInspectException>()),
      );

      final unsafe = fixture('work-items.json');
      (((unsafe['work_items'] as List).first as Map)['artifacts'] as List)
              .first['path'] =
          '.mana/features/PROJ-24342/../secret';
      expect(
        () => ManaWorkItemsResponse.fromJson(unsafe),
        throwsA(isA<ManaInspectException>()),
      );

      final wrongOwner = fixture('feature-work-item.json');
      ((((wrongOwner['sections'] as List).first as Map)['artifacts'] as List)
                  .first
              as Map)['work_item_id'] =
          'feature:OTHER';
      expect(
        () => ManaWorkItemResponse.fromJson(wrongOwner),
        throwsA(isA<ManaInspectException>()),
      );

      final duplicateSection = fixture('feature-work-item.json');
      (duplicateSection['sections'] as List).add(
        jsonDecode(jsonEncode((duplicateSection['sections'] as List).first)),
      );
      expect(
        () => ManaWorkItemResponse.fromJson(duplicateSection),
        throwsA(isA<ManaInspectException>()),
      );

      final globalOwner = fixture('project-context.json');
      final category = (globalOwner['categories'] as List).first as Map;
      ((category['artifacts'] as List).first as Map)['work_item_id'] =
          'feature:PROJ-24342';
      expect(
        () => ManaProjectContextResponse.fromJson(globalOwner),
        throwsA(isA<ManaInspectException>()),
      );

      final duplicateEvent = fixture('activity.json');
      (duplicateEvent['events'] as List).add(
        jsonDecode(jsonEncode((duplicateEvent['events'] as List).first)),
      );
      expect(
        () => ManaActivityResponse.fromJson(duplicateEvent),
        throwsA(isA<ManaInspectException>()),
      );
    },
  );

  test('bounds and redacts process diagnostics', () async {
    final root = await Directory.systemTemp.createTemp('semantic-stderr-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/mana').writeAsString('');
    final client = ManaInspectClient(
      projectRoot: root.path,
      run: (_, _, {workingDirectory}) async => ProcessResult(
        0,
        5,
        '',
        '${root.path}/private.json ${'/host-secret' * 200}',
      ),
    );

    try {
      await client.project();
      fail('Expected a command failure.');
    } on ManaInspectException catch (error) {
      expect(error.kind, ManaInspectFailure.command);
      expect(error.message, isNot(contains(root.path)));
      expect(error.message, isNot(contains('/host-secret')));
      expect(error.message, contains('<project>'));
      expect(error.message.length, lessThan(560));
    }
  });

  test('times out and terminates an unresponsive inspect process', () async {
    final root = await Directory.systemTemp.createTemp('semantic-timeout-');
    addTearDown(() => root.delete(recursive: true));
    final wrapper = File('${root.path}/mana');
    await wrapper.writeAsString(
      "#!/bin/sh\ntrap 'exit 0' TERM\nwhile :; do :; done\n",
    );
    expect((await Process.run('chmod', ['+x', wrapper.path])).exitCode, 0);
    final stopwatch = Stopwatch()..start();
    final client = ManaInspectClient(
      projectRoot: root.path,
      processTimeout: const Duration(milliseconds: 100),
    );

    await expectLater(
      client.project(),
      throwsA(
        isA<ManaInspectException>().having(
          (error) => error.kind,
          'kind',
          ManaInspectFailure.transport,
        ),
      ),
    );
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
  });
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
