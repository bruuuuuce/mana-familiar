import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/mana_inspect.dart';
import 'package:mana_familiar/application/mana_workspace_watcher.dart';
import 'package:mana_familiar/presentation/project_observatory_page.dart';

void main() {
  testWidgets(
    'renders stable chrome before Inspect completes and defers supporting work',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = Directory.systemTemp.createTempSync('m08-startup-shell-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}${Platform.pathSeparator}mana').writeAsStringSync('');
      final initial = Completer<Map<String, dynamic>>();
      final supporting = Completer<Map<String, dynamic>>();
      final calls = <List<String>>[];
      final milestones = <String>[];
      final watcher = _ControlledWatcher();
      final client = ManaInspectClient(
        projectRoot: root.path,
        run: (_, arguments, {workingDirectory}) async {
          calls.add(arguments);
          final operation = arguments[arguments.indexOf('inspect') + 1];
          final response = operation == 'project'
              ? _project
              : arguments.contains('--include-supporting')
              ? await supporting.future
              : await initial.future;
          return ProcessResult(1, 0, jsonEncode(response), '');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProjectObservatoryPage(
            client: client,
            knowledge: const SizedBox.shrink(),
            watcher: watcher,
            performanceMilestone: milestones.add,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('project-loading-shell')), findsOneWidget);
      expect(find.text('Mana Familiar'), findsOneWidget);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Loading project overview…'), findsOneWidget);
      expect(
        calls.where((call) => call.contains('--include-supporting')),
        isEmpty,
      );
      expect(milestones, contains('project_loading_shell'));

      initial.complete(_snapshot(includeSupporting: false));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('project-loading-shell')), findsNothing);
      expect(find.text('Project observatory'), findsOneWidget);
      expect(
        calls.where((call) => call.contains('--include-supporting')),
        hasLength(1),
        reason: 'supporting work starts only after the first meaningful frame',
      );
      expect(
        milestones,
        containsAll(['first_meaningful_overview', 'visible_route_populated']),
      );

      supporting.complete(_snapshot(includeSupporting: true));
      await tester.pump();
      await tester.pump();
      expect(milestones, contains('optional_surfaces_settled'));

      watcher.add(ManaWorkspaceWatchEvent.changed);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(milestones, contains('refresh_visible_route'));
      expect(milestones, isNot(contains('refresh_model_replaced')));
      expect(calls.skip(3).map((call) => call[call.indexOf('inspect') + 1]), [
        'project',
        'semantic-snapshot',
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('does not reload an unsupported supporting projection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('m08-work-semantic-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}${Platform.pathSeparator}mana').writeAsStringSync('');
    final initial = Completer<Map<String, dynamic>>();
    final supporting = Completer<Map<String, dynamic>>();
    final calls = <List<String>>[];
    final client = ManaInspectClient(
      projectRoot: root.path,
      run: (_, arguments, {workingDirectory}) async {
        calls.add(arguments);
        final operation = arguments[arguments.indexOf('inspect') + 1];
        final response = operation == 'project'
            ? _workSemanticProject
            : arguments.contains('--include-supporting')
            ? await supporting.future
            : await initial.future;
        return ProcessResult(1, 0, jsonEncode(response), '');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectObservatoryPage(
          client: client,
          knowledge: const SizedBox.shrink(),
          watcher: _SilentWatcher(),
        ),
      ),
    );
    initial.complete(
      _snapshot(includeSupporting: false, project: _workSemanticProject),
    );
    await tester.pump();
    await tester.pump();
    supporting.complete(
      _snapshot(includeSupporting: true, project: _workSemanticProject),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(
      calls.where((call) => call.contains('--include-supporting')),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _SilentWatcher implements ManaWorkspaceWatcher {
  @override
  Stream<ManaWorkspaceWatchEvent> get events => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {}
}

class _ControlledWatcher implements ManaWorkspaceWatcher {
  final _events = StreamController<ManaWorkspaceWatchEvent>.broadcast();

  void add(ManaWorkspaceWatchEvent event) => _events.add(event);

  @override
  Stream<ManaWorkspaceWatchEvent> get events => _events.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() => _events.close();
}

const _project = <String, dynamic>{
  'schema': inspectProjectSchema,
  'project_id': 'project:startup-shell',
  'framework': {'compatibility': 'mana-inspect/v1'},
  'mana': {'present': true},
  'operations': [
    {'name': 'project', 'schema': inspectProjectSchema},
    {'name': 'work-items', 'schema': inspectWorkItemsSchema},
    {'name': 'work-item', 'schema': inspectWorkItemSchema},
    {'name': 'project-context', 'schema': inspectProjectContextSchema},
    {'name': 'activity', 'schema': inspectActivitySchema},
    {'name': 'semantic-snapshot', 'schema': inspectSemanticSnapshotSchema},
  ],
};

const _workSemanticProject = <String, dynamic>{
  'schema': inspectProjectSchema,
  'project_id': 'project:startup-shell-work-semantic',
  'framework': {'compatibility': 'mana-inspect/v1'},
  'mana': {'present': true},
  'operations': [
    {'name': 'project', 'schema': inspectProjectSchema},
    {'name': 'work-items', 'schema': inspectWorkItemsSchema},
    {'name': 'work-item', 'schema': inspectWorkItemSchema},
    {'name': 'project-context', 'schema': inspectProjectContextSchema},
    {'name': 'semantic-snapshot', 'schema': inspectSemanticSnapshotSchema},
  ],
};

Map<String, dynamic> _snapshot({
  required bool includeSupporting,
  Map<String, dynamic> project = _project,
}) => {
  'schema': inspectSemanticSnapshotSchema,
  'snapshot_revision':
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'inventory': {
    'catalog_build_count': 1,
    'file_count': 10,
    'admitted_bytes': 100,
  },
  'project': project,
  'projections': {
    'work_items': {
      'status': 'available',
      'value': {
        'schema': inspectWorkItemsSchema,
        'work_items': <Object>[],
        'coverage': 'complete',
        'diagnostics': <Object>[],
      },
      'diagnostic': null,
    },
    'project_context': includeSupporting
        ? {
            'status': 'available',
            'value': _fixture('project-context.json'),
            'diagnostic': null,
          }
        : {'status': 'not_requested', 'value': null, 'diagnostic': null},
    'activity': includeSupporting && _advertises(project, 'activity')
        ? {
            'status': 'available',
            'value': _fixture('activity.json'),
            'diagnostic': null,
          }
        : {'status': 'not_requested', 'value': null, 'diagnostic': null},
    'artifacts': {'status': 'not_requested', 'value': null, 'diagnostic': null},
  },
  'guarantees': {
    'model_calls': 0,
    'network_calls': 0,
    'writes': false,
    'paths': 'project_relative_only',
  },
  'diagnostics': <Object>[],
};

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(
          File(
            '../mana/contracts/mana-inspect/v1/fixtures/$name',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

bool _advertises(Map<String, dynamic> project, String operation) =>
    (project['operations'] as List).whereType<Map>().any(
      (candidate) => candidate['name'] == operation,
    );
