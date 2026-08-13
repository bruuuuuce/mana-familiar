import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/artifact_renderer.dart';
import 'package:mana_familiar/application/observatory_model.dart';
import 'package:mana_familiar/application/operational_model.dart';
import 'package:mana_familiar/application/review_inbox_model.dart';
import 'package:mana_familiar/main.dart' show ExplorerConfig, JourneyStore;
import 'package:mana_familiar/mana_inspect.dart';

void main() {
  final projectRoot = Platform.environment['C01_PROJECT_ROOT'];
  final directArtifact = Platform.environment['C01_DIRECT_ARTIFACT'];

  test(
    'consumes the real zero-token Mana workspace contracts end to end',
    () async {
      expect(
        projectRoot,
        isNotNull,
        reason: 'C01 runner did not set a project',
      );
      expect(
        directArtifact,
        isNotNull,
        reason: 'C01 runner did not materialize a direct Journey artifact',
      );
      final client = ManaInspectClient(projectRoot: projectRoot!);
      final project = await client.project();
      final catalog = await client.catalog();

      expect(project.manaPresent, isTrue);
      expect(project.frameworkCompatibility, 'mana-inspect/v1');
      expect(
        catalog.artifacts.map((item) => item.kind),
        containsAll([
          'verification-result',
          'repair-attempt-result',
          'runtime_events',
          'journey',
          'journey_record',
        ]),
      );
      expect(catalog.artifacts.map((item) => item.status), contains('failed'));
      expect(
        catalog.artifacts.map((item) => item.status),
        contains('candidate'),
      );
      expect(
        catalog.artifacts.map((item) => item.status),
        contains('malformed'),
      );

      final overview = ObservatoryOverview.fromCatalog(catalog);
      expect(overview.failed, isNotEmpty);
      expect(overview.attention, isNotEmpty);
      final activity = const ActivityFilters().apply(catalog.artifacts);
      expect(activity, isNotEmpty);
      final timestamps = activity
          .map((entry) => entry.timestamp ?? '')
          .toList();
      final newestFirst = [...timestamps]..sort();
      expect(timestamps, orderedEquals(newestFirst.reversed));

      final inbox = ReviewInboxModel.fromCatalog(catalog);
      expect(
        inbox.items.map((item) => item.category),
        containsAll([
          ReviewInboxCategory.failedVerification,
          ReviewInboxCategory.learningCandidate,
          ReviewInboxCategory.incompatibleArtifact,
        ]),
      );

      final failed = catalog.artifacts.firstWhere(
        (artifact) => artifact.id == 'verification:run-failed',
      );
      final failedDetail = await client.artifact(failed.id);
      expect(
        ArtifactRendererRegistry.standard()
            .render(ArtifactRenderContext.fromDetail(failedDetail))
            .view,
        ArtifactPayloadView.verification,
      );
      final unknown = catalog.artifacts.firstWhere(
        (artifact) => artifact.path == '.mana/future.json',
      );
      final unknownDetail = await client.artifact(unknown.id);
      expect(
        ArtifactRendererRegistry.standard()
            .render(ArtifactRenderContext.fromDetail(unknownDetail))
            .view,
        ArtifactPayloadView.json,
      );

      final stale = await client.source('src/Stale.java');
      expect(stale.relations.single['staleness'], 'stale');
      final missing = await client.source('src/Missing.java');
      expect(missing.availability, 'missing');
      expect(missing.relations.single['staleness'], 'missing');

      final store = JourneyStore(
        ExplorerConfig(
          projectRoot: projectRoot,
          manaRoot: projectRoot,
          fixturePath: directArtifact,
        ),
      );
      final journeys = await store.list();
      expect(journeys, hasLength(1));
      expect((await store.load(journeys.single)).nodes, isNotEmpty);
    },
    skip: projectRoot == null || directArtifact == null
        ? 'Run through tests/run-c01-zero-token-harness.sh.'
        : false,
  );
}
