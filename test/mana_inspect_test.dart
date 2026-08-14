import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/main.dart' show ExplorerConfig;
import 'package:mana_familiar/mana_inspect.dart';

void main() {
  test('negotiates advertised capabilities and preserves additive fields', () {
    final project = ManaInspectProject.fromJson(_project);

    expect(project.supports('artifacts', inspectArtifactsSchema), isTrue);
    expect(project.supports('artifact', inspectArtifactSchema), isFalse);
    expect(project.raw['future_additive_field'], 'safe');
  });

  test('parses the canonical v1 project and source fixture shapes', () {
    final project = ManaInspectProject.fromJson(_canonicalProject);
    final source = ManaInspectSourceRelations.fromJson(_canonicalSource);

    expect(project.frameworkCompatibility, 'mana-inspect/v1');
    expect(project.supports('source', inspectSourceSchema), isTrue);
    expect(source.coverage, 'explicit_journey_anchors');
    expect(source.relations.single['staleness'], 'stale');
  });

  test('parses a partial catalog without rejecting recognized entries', () {
    final catalog = ManaInspectCatalog.fromJson({
      'schema': inspectArtifactsSchema,
      'artifacts': [_artifact, 'future-invalid-entry'],
      'guarantees': const {},
      'diagnostics': const [],
      'future': true,
    });
    expect(catalog.partial, isTrue);
    expect(catalog.artifacts.single.id, 'journey:jrn_test');
    expect(catalog.raw['future'], isTrue);
  });

  test('rejects unsafe producer artifact and source paths', () {
    final catalog = ManaInspectCatalog.fromJson({
      'schema': inspectArtifactsSchema,
      'artifacts': [
        _artifact,
        {..._artifact, 'artifact_id': 'unsafe', 'path': '.mana/../secret'},
      ],
      'guarantees': const {},
      'diagnostics': const [],
    });
    expect(catalog.partial, isTrue);
    expect(catalog.artifacts.single.id, 'journey:jrn_test');
    expect(
      () => ManaInspectSourceRelations.fromJson({
        ..._canonicalSource,
        'source': {'path': '../secret', 'availability': 'present'},
      }),
      throwsA(isA<ManaInspectException>()),
    );
  });

  test('rejects unsupported schema rather than guessing compatibility', () {
    expect(
      () => ManaInspectProject.fromJson({
        ..._project,
        'schema': 'mana.inspect.project/v2',
      }),
      throwsA(
        isA<ManaInspectException>().having(
          (error) => error.kind,
          'kind',
          ManaInspectFailure.unsupportedSchema,
        ),
      ),
    );
  });

  test(
    'uses structured project-wrapper arguments and negotiates before catalog',
    () async {
      final calls = <List<String>>[];
      final root = await Directory.systemTemp.createTemp(
        'mana-inspect-project-',
      );
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/mana').writeAsString('#!/bin/sh');
      final client = ManaInspectClient(
        projectRoot: root.path,
        run: (executable, arguments, {workingDirectory}) async {
          calls.add([executable, ...arguments]);
          final response = arguments.contains('project') ? _project : _catalog;
          return ProcessResult(1, 0, jsonEncode(response), '');
        },
      );

      final catalog = await client.catalog();
      expect(catalog.artifacts.single.kind, 'journey');
      expect(calls, hasLength(2));
      expect(calls[0].skip(1), ['inspect', 'project', '--json']);
      expect(calls[1].skip(1), ['inspect', 'artifacts', '--json']);
    },
  );

  test('reports command and malformed responses explicitly', () async {
    final client = ManaInspectClient(
      projectRoot: '/missing',
      manaRoot: '/missing',
      run: (executable, arguments, {workingDirectory}) async =>
          ProcessResult(1, 3, '', 'unsupported'),
    );
    expect(
      () => client.project(),
      throwsA(
        isA<ManaInspectException>().having(
          (error) => error.kind,
          'kind',
          ManaInspectFailure.transport,
        ),
      ),
    );

    final root = await Directory.systemTemp.createTemp('mana-inspect-wrapper-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/mana').writeAsString('');
    final malformed = ManaInspectClient(
      projectRoot: root.path,
      run: (executable, arguments, {workingDirectory}) async =>
          ProcessResult(1, 0, '{', ''),
    );
    expect(
      () => malformed.project(),
      throwsA(
        isA<ManaInspectException>().having(
          (error) => error.kind,
          'kind',
          ManaInspectFailure.malformedJson,
        ),
      ),
    );
  });

  test('opens a saved catalog snapshot without a Mana checkout', () async {
    final root = await Directory.systemTemp.createTemp(
      'mana-inspect-snapshot-',
    );
    addTearDown(() => root.delete(recursive: true));
    final snapshot = File('${root.path}/catalog.json');
    await snapshot.writeAsString(jsonEncode(_catalog));
    final catalog = await ManaInspectClient(
      projectRoot: root.path,
      snapshotPath: snapshot.path,
    ).catalog();
    expect(catalog.artifacts.single.path, '.mana/learning/journey.yaml');
  });

  test(
    'keeps explicit project roots and inspect snapshots distinct from Journey artifacts',
    () {
      final config = ExplorerConfig.parse(const [
        '--project-root',
        '/project',
        '--mana-root',
        '/mana',
        '--inspect-snapshot',
        '/snapshots/catalog.json',
        '--artifact',
        '/journeys/legacy.json',
      ]);
      expect(config.projectRoot, '/project');
      expect(config.manaRoot, '/mana');
      expect(config.inspectSnapshotPath, '/snapshots/catalog.json');
      expect(config.fixturePath, '/journeys/legacy.json');
    },
  );
}

const _project = <String, dynamic>{
  'schema': inspectProjectSchema,
  'project_id':
      'project:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'framework': {'compatibility': 'mana-inspect/v1'},
  'mana': {'present': true},
  'operations': [
    {'name': 'project', 'schema': inspectProjectSchema},
    {'name': 'artifacts', 'schema': inspectArtifactsSchema},
    {'name': 'source', 'schema': inspectSourceSchema},
  ],
  'capabilities': [],
  'git': {},
  'guarantees': {},
  'diagnostics': [],
  'future_additive_field': 'safe',
};
const _artifact = <String, dynamic>{
  'artifact_id': 'journey:jrn_test',
  'path': '.mana/learning/journey.yaml',
  'family': 'knowledge',
  'kind': 'journey',
  'status': 'available',
};
const _catalog = <String, dynamic>{
  'schema': inspectArtifactsSchema,
  'artifacts': [_artifact],
  'guarantees': {},
  'diagnostics': [],
};

// Derived verbatim in structure from Mana's canonical v1 fixture bundle.
const _canonicalProject = <String, dynamic>{
  'schema': 'mana.inspect.project/v1',
  'project_id':
      'project:1111111111111111111111111111111111111111111111111111111111111111',
  'framework': {'version': '0.4.1', 'compatibility': 'mana-inspect/v1'},
  'mana': {'present': true, 'active_workspace': '.mana/features/FEAT-1'},
  'git': {
    'branch': 'feature/inspect',
    'head': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'working_tree_dirty': false,
  },
  'capabilities': [
    'workspace',
    'artifact_catalog',
    'artifact_detail',
    'source_relations',
  ],
  'operations': [
    {'name': 'project', 'schema': 'mana.inspect.project/v1'},
    {'name': 'artifacts', 'schema': 'mana.inspect.artifacts/v1'},
    {'name': 'artifact', 'schema': 'mana.inspect.artifact/v1'},
    {'name': 'source', 'schema': 'mana.inspect.source/v1'},
  ],
  'guarantees': {
    'model_calls': 0,
    'writes': false,
    'paths': 'project_relative_only',
  },
  'diagnostics': [],
};

const _canonicalSource = <String, dynamic>{
  'schema': 'mana.inspect.source/v1',
  'source': {'path': 'src/PaymentService.java', 'availability': 'present'},
  'relations': [
    {
      'relation_type': 'references-source/v1',
      'artifact_id': 'journey-record:anc_000000000000000000000000',
      'journey_id': 'jrn_000000000000000000000000',
      'anchor_id': 'anc_000000000000000000000000',
      'source': {
        'path': 'src/PaymentService.java',
        'revision': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'range': {'start_line': 1, 'end_line': 2},
      },
      'staleness': 'stale',
    },
  ],
  'coverage': 'explicit_journey_anchors',
  'guarantees': {
    'model_calls': 0,
    'writes': false,
    'relation_coverage': 'explicit_structured_only',
  },
  'diagnostics': [],
};
