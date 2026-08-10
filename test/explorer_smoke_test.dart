import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_learning_explorer/main.dart';

void main() {
  testWidgets(
    'exercises source, no-editor, settings, graph, Back, and Forward',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late Directory root;
      late ExplorerConfig config;
      late ExplorerPreferences preferences;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('mana-smoke-');
        final artifact = File('${root.path}/journey.json');
        await artifact.writeAsString('''
        {
          "schema":"mana.learning.graph/v1",
          "journey":{"id":"smoke-journey","entry_node_id":"root","title":"Smoke Journey"},
          "nodes":[
            {"id":"root","label":"Root","state":"expanded"},
            {"id":"next","label":"Next","state":"discovered"}
          ],
          "edges":[
            {"id":"root-next","from":"root","to":"next","kind":"CALLS","disposition":"primary"}
          ],
          "anchors":[
            {"id":"root-source","node_id":"root","path":"lib/example.dart","range":{"start_line":1,"end_line":1}}
          ]
        }
      ''');
        config = ExplorerConfig(
          projectRoot: root.path,
          manaRoot: '${root.path}/missing-mana',
          preferencesRoot: '${root.path}/preferences',
          fixturePath: artifact.path,
        );
        preferences = await ExplorerPreferences.load(config);
      });
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      await tester.pumpWidget(
        ManaExplorerApp(config: config, preferences: preferences),
      );
      await _pumpFrames(tester);

      expect(find.text('SOURCE WORKSPACE'), findsOneWidget);
      expect(find.text('lib/example.dart:1-1'), findsOneWidget);
      expect(find.text('Source unavailable'), findsWidgets);

      await tester.tap(find.byTooltip('Open externally'));
      await tester.pump();
      expect(
        find.text('No external editor matches this source.'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Settings'));
      await _pumpFrames(tester);
      expect(find.text('Display settings'), findsOneWidget);
      expect(find.text('Theme mode'), findsOneWidget);
      await tester.tap(find.text('External editors'));
      await _pumpFrames(tester);
      expect(find.text('External editor profiles'), findsOneWidget);
      expect(find.text('Profiles'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Done'));
      await _pumpFrames(tester);

      await tester.tap(find.text('Graph'));
      await _pumpFrames(tester);
      expect(find.text('GRAPH OVERVIEW'), findsOneWidget);

      await tester.tap(find.text('Next').last);
      await _pumpFrames(tester);
      expect(find.text('Root  ›  Next'), findsOneWidget);

      final back = find.widgetWithText(TextButton, 'Back');
      final forward = find.widgetWithText(TextButton, 'Forward');
      expect(tester.widget<TextButton>(back).onPressed, isNotNull);
      await tester.tap(back);
      await _pumpFrames(tester);
      expect(tester.widget<TextButton>(forward).onPressed, isNotNull);
      await tester.tap(forward);
      await _pumpFrames(tester);
      expect(find.text('Root  ›  Next'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpFrames(tester);
    },
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}
