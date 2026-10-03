import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/m08_performance_probe.dart';
import 'package:mana_familiar/application/mana_inspect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('writes bounded payload-free Flutter performance evidence', () {
    final directory = Directory.systemTemp.createTempSync('m08-probe-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final probe = M08PerformanceProbe(directory.path);

    probe.mark('project_loading_shell');
    probe.recordProcess(
      const ManaInspectProcessTrace(
        operation: 'semantic-snapshot',
        elapsed: Duration(milliseconds: 8),
        responseBytes: 4096,
        exitCode: 0,
      ),
    );
    probe.recordDecode(
      const ManaInspectDecodeTrace(
        responseBytes: 4096,
        offloaded: false,
        elapsed: Duration(milliseconds: 1),
      ),
    );
    probe.recordProjection(
      const ManaInspectProjectionTrace(
        schema: inspectSemanticSnapshotSchema,
        elapsed: Duration(microseconds: 200),
      ),
    );
    probe.dispose();

    final raw = File(
      '${directory.path}${Platform.pathSeparator}flutter-performance.json',
    ).readAsStringSync();
    final report = jsonDecode(raw) as Map<String, dynamic>;
    expect(report['schema'], 'mana-familiar.c04.flutter-performance/v1');
    expect(
      (report['milestones_us'] as Map<String, dynamic>).keys,
      containsAll(['binding_ready', 'project_loading_shell', 'probe_disposed']),
    );
    final process =
        (report['processes'] as List).single as Map<String, dynamic>;
    expect(process['operation'], 'semantic-snapshot');
    expect(process['start_us'], isA<int>());
    expect(process['completed_us'], isA<int>());
    expect(process['elapsed_us'], 8000);
    expect(process['response_bytes'], 4096);
    expect(process['exit_code'], 0);
    expect((report['decode'] as List).single, {
      'response_bytes': 4096,
      'offloaded': false,
      'elapsed_us': 1000,
    });
    expect((report['typed_projection'] as List).single, {
      'schema': inspectSemanticSnapshotSchema,
      'elapsed_us': 200,
    });
    expect(raw, isNot(contains(directory.path)));
  });

  test('rejects a relative evidence destination', () {
    expect(() => M08PerformanceProbe('relative/path'), throwsArgumentError);
  });

  test('re-arms refresh milestones for the latest workspace event', () async {
    final directory = Directory.systemTemp.createTempSync('m08-probe-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final probe = M08PerformanceProbe(directory.path);

    probe.mark('workspace_event');
    probe.mark('refresh_model_replaced');
    probe.mark('refresh_visible_route');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    probe.mark('workspace_event');

    final raw = File(
      '${directory.path}${Platform.pathSeparator}flutter-performance.json',
    ).readAsStringSync();
    final report = jsonDecode(raw) as Map<String, dynamic>;
    final milestones = report['milestones_us'] as Map<String, dynamic>;
    expect(milestones, contains('workspace_event'));
    expect(milestones, isNot(contains('refresh_visible_route')));
    expect(milestones, isNot(contains('refresh_model_replaced')));
    probe.dispose();
  });
}
