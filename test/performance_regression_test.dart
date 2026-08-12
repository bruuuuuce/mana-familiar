import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/review_inbox_model.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/review_inbox_page.dart';

import 'support/large_catalog_fixture.dart';

void main() {
  test(
    'parses and derives the large mixed catalog within a bounded local time',
    () {
      final stopwatch = Stopwatch()..start();
      final catalog = ManaInspectCatalog.fromJson(largeCatalogFixture());
      final inbox = ReviewInboxModel.fromCatalog(catalog);
      stopwatch.stop();

      expect(catalog.artifacts, hasLength(largeCatalogArtifactCount));
      expect(inbox.items, isNotEmpty);
      expect(
        catalog.artifacts.where((artifact) => artifact.status == 'malformed'),
        isNotEmpty,
      );
      expect(
        catalog.artifacts.first.raw['relations'],
        contains(
          isA<Map>().having(
            (relation) => relation['to'],
            'cycle target',
            'artifact:00000001',
          ),
        ),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      // This makes the local measurement visible in CI logs without turning it
      // into a hardware-independent product-performance claim.
      // ignore: avoid_print
      print(
        'F10 large catalog: ${catalog.artifacts.length} artifacts, '
        '${inbox.items.length} inbox items in ${stopwatch.elapsedMilliseconds}ms',
      );
    },
  );

  testWidgets('uses a lazy list delegate for the large review inbox', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final catalog = ManaInspectCatalog.fromJson(largeCatalogFixture());
    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewInboxPage(
            artifacts: catalog.artifacts,
            onOpenArtifact: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    stopwatch.stop();

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
    expect(find.text('Review Inbox'), findsOneWidget);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    // ignore: avoid_print
    print(
      'F10 lazy review layout: ${catalog.artifacts.length} artifacts in '
      '${stopwatch.elapsedMilliseconds}ms',
    );
  });
}
