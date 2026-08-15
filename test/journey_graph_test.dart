import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/journey_graph.dart';
import 'package:mana_familiar/main.dart';

import 'support/journey_graph_fixture.dart';

void main() {
  test('keeps graph navigation and enrichments scoped to a stable node', () {
    final graph = decodeTestGraph(
      '''{"journey":{"title":"Payment"},"nodes":[{"id":"jn_a","label":"Service"},{"id":"jn_b","label":"Repository"}],"edges":[{"id":"je_a","from":"jn_a","to":"jn_b","kind":"CALLS"}],"anchors":[{"id":"anc_a","node_id":"jn_a","path":"src/Service.java","range":{"start_line":2,"end_line":4}}],"explanations":[{"id":"exp_a","subject_node_id":"jn_a"}],"concept_occurrences":[{"id":"occ_a","subject_node_id":"jn_a","concept_id":"cpt_001"}],"timeline_events":[{"id":"tle_a","subject_node_id":"jn_a","occurred_at":"2026-01-02T00:00:00Z"},{"id":"tle_b","subject_node_id":"jn_a","occurred_at":"2026-01-03T00:00:00Z"}],"diagrams":[{"id":"dia_a","kind":"sequence","asset_path":"assets/sequence.puml","node_ids":["jn_a","jn_b"]}]}''',
    );
    expect(graph.title, 'Payment');
    expect(graph.anchorsFor('jn_a'), hasLength(1));
    expect(graph.related('jn_a'), hasLength(1));
    expect(graph.explanationsFor('jn_a'), hasLength(1));
    expect(graph.conceptsFor('jn_a').single['concept_id'], 'cpt_001');
    expect(graph.timelineFor('jn_a').first['id'], 'tle_b');
    expect(graph.diagramsFor('jn_a').single['id'], 'dia_a');
    expect(graph.node('jn_b')?['label'], 'Repository');
  });

  test('builds a finite logical breadcrumb from primary graph relations', () {
    final graph = decodeTestGraph(
      '''{"nodes":[{"id":"a"},{"id":"b"},{"id":"c"}],"edges":[{"from":"a","to":"b","disposition":"primary"},{"from":"b","to":"c","disposition":"primary"},{"from":"c","to":"a","disposition":"primary"}]}''',
    );

    expect(graph.logicalPathFor('c'), ['a', 'b', 'c']);
  });

  test('prefers the declared traversal entry over serialized node order', () {
    final graph = decodeTestGraph('''
      {"nodes":[{"id":"later"},{"id":"entry"},{"id":"other"}],
       "traversals":[{"entry_node_id":"entry","node_ids":["entry","later"]}],
       "edges":[{"from":"entry","to":"later","disposition":"primary"}]}
    ''');

    expect(graph.initialNodeId, 'entry');
  });

  test('watches append-only Journey record changes', () async {
    final root = await Directory.systemTemp.createTemp('mana-explorer-watch-');
    addTearDown(() => root.delete(recursive: true));
    const journey = 'jrn_0123456789abcdef01234567';
    final records = Directory(
      '${root.path}/project/.mana/learning/journeys/$journey/records',
    );
    await records.create(recursive: true);
    final store = JourneyStore(
      ExplorerConfig(projectRoot: '${root.path}/project', manaRoot: root.path),
    );
    final event = store.watch(journey).first;
    await File(
      '${records.path}/jn_0123456789abcdef01234567-node.yaml',
    ).writeAsString('{}');
    await event.timeout(const Duration(seconds: 2));
  });

  test('accepts independent project and Mana roots', () {
    final config = ExplorerConfig.parse(const [
      '--project-root',
      '/workspace/project',
      '--mana-root',
      '/tools/mana',
    ]);
    expect(config.projectRoot, '/workspace/project');
    expect(config.manaRoot, '/tools/mana');
  });

  test('accepts an arbitrary materialized artifact path', () {
    final config = ExplorerConfig.parse(const [
      '--artifact',
      '/artifacts/journey.json',
    ]);
    expect(config.fixturePath, '/artifacts/journey.json');
  });

  test('uses the project Mana wrapper to materialize a Journey', () async {
    final root = await Directory.systemTemp.createTemp('mana-wrapper-');
    addTearDown(() => root.delete(recursive: true));
    final project = Directory('${root.path}/project');
    await project.create();
    final wrapper = File(
      Platform.isWindows ? '${project.path}/mana.bat' : '${project.path}/mana',
    );
    await wrapper.writeAsString(
      Platform.isWindows
          ? r'''@echo off
if "%1"=="journey" if "%2"=="materialize" (
  <nul set /p ={"schema":"mana.learning.graph/v1","journey":{"id":"jrn_0123456789abcdef01234567","title":"Wrapper Journey"},"nodes":[{"id":"node"}]}
  exit /b 0
)
exit /b 1
'''
          : r'''#!/bin/sh
if [ "$1" = journey ] && [ "$2" = materialize ]; then
  printf '%s' '{"schema":"mana.learning.graph/v1","journey":{"id":"jrn_0123456789abcdef01234567","title":"Wrapper Journey"},"nodes":[{"id":"node"}]}'
  exit 0
fi
exit 1
''',
    );
    if (!Platform.isWindows) await Process.run('chmod', ['+x', wrapper.path]);
    final store = JourneyStore(
      ExplorerConfig(
        projectRoot: project.path,
        manaRoot: '${root.path}/missing',
      ),
    );

    final graph = await store.load('jrn_0123456789abcdef01234567');

    expect(graph.title, 'Wrapper Journey');
  });

  group('materialized artifact compatibility', () {
    test('accepts the pinned graph schema', () {
      final graph = JourneyGraph.decode('''
        {
          "schema":"mana.learning.graph/v1",
          "journey":{"id":"journey"},
          "nodes":[{"id":"node"}]
        }
      ''');

      expect(graph.initialNodeId, 'node');
    });

    test('rejects a missing schema with a compatibility error', () {
      expect(
        () => JourneyGraph.decode(
          '{"journey":{"id":"journey"},"nodes":[{"id":"node"}]}',
        ),
        throwsA(
          isA<JourneyGraphCompatibilityException>().having(
            (error) => error.toString(),
            'message',
            contains('missing required "schema"'),
          ),
        ),
      );
    });

    test('rejects unsupported schema versions clearly', () {
      expect(
        () => JourneyGraph.decode('''
          {
            "schema":"mana.learning.graph/v2",
            "journey":{"id":"journey"},
            "nodes":[{"id":"node"}]
          }
        '''),
        throwsA(
          isA<JourneyGraphCompatibilityException>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('unsupported schema'), contains('/v2')),
          ),
        ),
      );
    });

    test('rejects malformed JSON and malformed record collections', () {
      expect(
        () => JourneyGraph.decode('{'),
        throwsA(isA<JourneyGraphFormatException>()),
      );
      expect(
        () => JourneyGraph.decode('''
          {
            "schema":"mana.learning.graph/v1",
            "journey":{"id":"journey"},
            "nodes":"not-an-array"
          }
        '''),
        throwsA(
          isA<JourneyGraphFormatException>().having(
            (error) => error.toString(),
            'message',
            contains('"nodes" must be an array'),
          ),
        ),
      );
    });
  });

  test(
    'persists the selected theme mode in project-local explorer settings',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mana-explorer-theme-',
      );
      addTearDown(() => root.delete(recursive: true));
      final config = ExplorerConfig(
        projectRoot: root.path,
        manaRoot: root.path,
        preferencesRoot: '${root.path}/preferences',
      );

      final preferences = await ExplorerPreferences.load(config);
      expect(preferences.themeMode.value, ThemeMode.system);
      await preferences.saveThemeMode(ThemeMode.dark);
      await preferences.saveDisplay(fontSize: 18, tabSize: 4, wordWrap: true);
      await preferences.rememberProjectRoot('/another-project');
      await preferences.rememberProjectRoot(root.path);

      final reloaded = await ExplorerPreferences.load(config);
      expect(reloaded.themeMode.value, ThemeMode.dark);
      expect(reloaded.fontSize, 18);
      expect(reloaded.tabSize, 4);
      expect(reloaded.wordWrap, isTrue);
      expect(reloaded.recentProjectRoots, [root.path, '/another-project']);
    },
  );
}
