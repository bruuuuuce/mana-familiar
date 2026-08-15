import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';

void main() {
  final projectRoot = Platform.environment['F16_PROJECT_ROOT'];
  final manaRoot = Platform.environment['F16_MANA_ROOT'];

  test(
    'consumes a real project through every advertised inspect operation',
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
      expect(model.workItems, isNotNull);
      expect(model.workItems!.workItems, isNotEmpty);
      expect(model.projectContext!.categories, hasLength(8));
      expect(model.activity, isNotNull);
      expect(model.refreshError, isNull);

      final selected = model.workItems!.workItems.first;
      final detail = await repository.workItem(selected.id, model.project);
      expect(detail.workItem.id, selected.id);
      expect(
        detail.sections.map((section) => section.id).toSet().length,
        detail.sections.length,
      );

      final catalogArtifact = model.catalog!.artifacts
          .where((artifact) => artifact.status == 'available')
          .firstOrNull;
      if (catalogArtifact != null &&
          model.project.supports('artifact', inspectArtifactSchema)) {
        expect(
          (await client.artifact(catalogArtifact.id)).artifact.id,
          catalogArtifact.id,
        );
      }
      if (model.project.supports('source', inspectSourceSchema)) {
        expect((await client.source('README.md')).path, 'README.md');
      }
    },
    skip: projectRoot == null || manaRoot == null
        ? 'Set F16_PROJECT_ROOT and F16_MANA_ROOT for the live smoke.'
        : false,
  );
}
