import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/main.dart';

void main() {
  test('loads a valid nested direct-artifact diagram asset', () async {
    final root = await Directory.systemTemp.createTemp('mana-artifact-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = File('${root.path}/journey.json');
    await artifact.writeAsString(_artifact);
    final diagram = File('${root.path}/assets/nested/diagram.puml');
    await diagram.parent.create(recursive: true);
    await diagram.writeAsString('@startuml\n@enduml\n');
    final store = JourneyStore(
      ExplorerConfig(
        projectRoot: root.path,
        manaRoot: root.path,
        fixturePath: artifact.path,
      ),
    );

    expect(await store.list(), ['journey']);
    expect((await store.load('journey')).initialNodeId, 'root');
    expect(
      await store.loadDiagram('journey', {
        'asset_path': 'assets/nested/diagram.puml',
      }),
      contains('@startuml'),
    );
  });

  test(
    'blocks traversal, missing files, and symlink escapes for diagrams',
    () async {
      final root = await Directory.systemTemp.createTemp('mana-artifact-');
      final outside = await Directory.systemTemp.createTemp('mana-outside-');
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => outside.delete(recursive: true));
      final artifact = File('${root.path}/journey.json');
      await artifact.writeAsString(_artifact);
      final secret = File('${outside.path}/secret.puml');
      await secret.writeAsString('outside');
      await Directory('${root.path}/assets').create();
      await Link('${root.path}/assets/escape.puml').create(secret.path);
      final store = JourneyStore(
        ExplorerConfig(
          projectRoot: root.path,
          manaRoot: root.path,
          fixturePath: artifact.path,
        ),
      );

      expect(
        () => store.loadDiagram('journey', {
          'asset_path': 'assets/../secret.puml',
        }),
        throwsA(isA<StateError>()),
      );
      expect(
        () =>
            store.loadDiagram('journey', {'asset_path': 'assets/missing.puml'}),
        throwsA(isA<StateError>()),
      );
      expect(
        () =>
            store.loadDiagram('journey', {'asset_path': 'assets/escape.puml'}),
        throwsA(isA<StateError>()),
      );
    },
  );
}

const _artifact = '''
{"schema":"mana.learning.graph/v1","journey":{"id":"journey"},"nodes":[{"id":"root"}]}
''';
