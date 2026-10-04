import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/mana_inspect.dart';
import 'package:mana_familiar/application/semantic_navigation.dart';
import 'package:mana_familiar/application/mana_workspace_watcher.dart';
import 'package:mana_familiar/presentation/project_observatory_page.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(
          File(
            '../mana/contracts/mana-inspect/v1/fixtures/$name',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  final revision = 'sha256:${'a' * 64}';
  Map<String, dynamic> page({String? cursor}) => {
    ...fixture('activity.json'),
    'schema': inspectActivityPageSchema,
    'view_revision': revision,
    'next_cursor': cursor,
    'total_events': 12050,
  };

  test('rejects activity cursors from another view and unbounded pages', () {
    expect(
      () => ManaActivityPage.fromJson(page(cursor: '${'b' * 64}:500')),
      throwsA(isA<ManaInspectException>()),
    );
    final oversized = page();
    oversized['events'] = List.filled(
      501,
      fixture('activity.json')['events'][0],
    );
    expect(
      () => ManaActivityPage.fromJson(oversized),
      throwsA(isA<ManaInspectException>()),
    );
  });

  testWidgets('refresh waits until the replacement activity page is rendered', (
    tester,
  ) async {
    final root = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'activity-refresh-',
      );
      await File('${directory.path}/mana').writeAsString('');
      return directory;
    }))!;
    addTearDown(() => root.delete(recursive: true));
    final rawProject = {
      ...fixture('semantic-snapshot.json')['project'] as Map<String, dynamic>,
    };
    rawProject['operations'] = [
      ...rawProject['operations'] as List,
      {'name': 'activity-page', 'schema': inspectActivityPageSchema},
    ];
    final replacement = Completer<ProcessResult>();
    final watcher = _ActivityWatcher();
    final milestones = <String>[];
    var pageReads = 0;
    final client = ManaInspectClient(
      projectRoot: root.path,
      run: (_, arguments, {workingDirectory}) async {
        if (arguments.contains('activity-page')) {
          if (++pageReads == 2) return replacement.future;
          return ProcessResult(1, 0, jsonEncode(page()), '');
        }
        if (arguments.contains('semantic-snapshot')) {
          return ProcessResult(
            1,
            0,
            jsonEncode({
              ...fixture('semantic-snapshot.json'),
              'project': rawProject,
            }),
            '',
          );
        }
        return ProcessResult(1, 0, jsonEncode(rawProject), '');
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectObservatoryPage(
          client: client,
          knowledge: const SizedBox(),
          watcher: watcher,
          performanceMilestone: milestones.add,
          initialReadModel: ManaSemanticReadModel(
            project: ManaInspectProject.fromJson(rawProject),
            mode: ManaSemanticMode.fullSemantic,
          ),
          initialRoute: const ObservatoryRoute(
            destination: ObservatoryDestination.activity,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(pageReads, 1);
    watcher.controller.add(ManaWorkspaceWatchEvent.changed);
    await tester.pump();
    await tester.pump();
    expect(pageReads, 2);
    expect(milestones, contains('refresh_model_replaced'));
    expect(milestones, isNot(contains('refresh_visible_route')));
    replacement.complete(ProcessResult(1, 0, jsonEncode(page()), ''));
    await tester.pumpAndSettle();
    expect(
      milestones.where((value) => value == 'refresh_visible_route'),
      hasLength(1),
    );
  });

  testWidgets('loads advertised pages and exposes restart after stale cursor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'activity-page-widget-',
      );
      await File('${directory.path}/mana').writeAsString('');
      return directory;
    }))!;
    addTearDown(() => root.delete(recursive: true));
    final project = ManaInspectProject.fromJson({
      ...fixture('minimal-project.json'),
      'operations': [
        ...fixture('minimal-project.json')['operations'] as List,
        {'name': 'activity-page', 'schema': inspectActivityPageSchema},
      ],
    });
    final requests = <List<String>>[];
    final client = ManaInspectClient(
      projectRoot: root.path,
      run: (_, arguments, {workingDirectory}) async {
        requests.add(arguments);
        if (arguments.contains('--cursor')) {
          return ProcessResult(1, 4, '', 'activity_view_changed');
        }
        return ProcessResult(
          1,
          0,
          jsonEncode(page(cursor: '${'a' * 64}:500')),
          '',
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectObservatoryPage(
          client: client,
          knowledge: const SizedBox(),
          initialReadModel: ManaSemanticReadModel(
            project: project,
            mode: ManaSemanticMode.fullSemantic,
          ),
          initialRoute: const ObservatoryRoute(
            destination: ObservatoryDestination.activity,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.single, contains('activity-page'));
    expect(find.textContaining('12050 events loaded'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Load more activity'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Load more activity'));
    await tester.pumpAndSettle();
    expect(requests.last, containsAll(['--cursor', '${'a' * 64}:500']));
    expect(find.text('Reload activity'), findsOneWidget);
    await tester.tap(find.text('Reload activity'));
    await tester.pumpAndSettle();
    expect(requests.last, isNot(contains('--cursor')));
    expect(find.text('Reload activity'), findsNothing);
  });
}

class _ActivityWatcher implements ManaWorkspaceWatcher {
  final controller = StreamController<ManaWorkspaceWatchEvent>.broadcast();
  @override
  Stream<ManaWorkspaceWatchEvent> get events => controller.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> dispose() => controller.close();
}
