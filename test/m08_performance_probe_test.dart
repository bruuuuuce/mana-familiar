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
      'offloaded': false,
      'elapsed_us': 200,
    });
    expect(raw, isNot(contains(directory.path)));
  });

  test('rejects a relative evidence destination', () {
    expect(() => M08PerformanceProbe('relative/path'), throwsArgumentError);
  });

  test('publication failure preserves measurements for the next write', () {
    final directory = Directory.systemTemp.createTempSync('m08-retry-');
    final probe = M08PerformanceProbe(directory.path);
    directory.deleteSync(recursive: true);
    expect(() => probe.mark('project_loading_shell'), returnsNormally);
    expect(
      () => probe.recordProjection(
        const ManaInspectProjectionTrace(
          schema: inspectSemanticSnapshotSchema,
          elapsed: Duration(microseconds: 200),
        ),
      ),
      returnsNormally,
    );
    directory.createSync();
    probe.mark('first_meaningful_overview');
    probe.dispose();
    final report =
        jsonDecode(
              File(
                '${directory.path}/flutter-performance.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(
      (report['milestones_us'] as Map).keys,
      containsAll(['project_loading_shell', 'first_meaningful_overview']),
    );
    expect((report['typed_projection'] as List).single['elapsed_us'], 200);
    expect((report['diagnostics'] as Map)['publication_failures'], 2);
    directory.deleteSync(recursive: true);
  });

  test(
    'Windows report reader cannot interrupt model observations',
    () async {
      final directory = Directory.systemTemp.createTempSync('m08-lock-');
      final probe = M08PerformanceProbe(directory.path);
      final target = File('${directory.path}/flutter-performance.json');
      final release = File('${directory.path}/release-lock');
      final locker = await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"$file=[IO.File]::Open($env:M08_LOCK_FILE,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read); [Console]::WriteLine('ready'); while (![IO.File]::Exists($env:M08_RELEASE_FILE)) { Start-Sleep -Milliseconds 20 }; $file.Dispose()",
        ],
        environment: {
          'M08_LOCK_FILE': target.path,
          'M08_RELEASE_FILE': release.path,
        },
      );
      addTearDown(() async {
        locker.kill();
        probe.dispose();
        await directory.delete(recursive: true);
      });
      expect(
        await locker.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'ready',
      );
      expect(() => probe.mark('first_meaningful_overview'), returnsNormally);
      expect(
        () => probe.recordProjection(
          const ManaInspectProjectionTrace(
            schema: inspectSemanticSnapshotSchema,
            elapsed: Duration(microseconds: 200),
          ),
        ),
        returnsNormally,
      );
      await release.writeAsString('release');
      await locker.stdin.close();
      expect(await locker.exitCode.timeout(const Duration(seconds: 2)), 0);
      probe.mark('optional_surfaces_settled');
      final report =
          jsonDecode(target.readAsStringSync()) as Map<String, dynamic>;
      expect(
        (report['milestones_us'] as Map).keys,
        contains('first_meaningful_overview'),
      );
      expect((report['typed_projection'] as List), hasLength(1));
      expect((report['diagnostics'] as Map)['publication_failures'], 2);
    },
    skip: !Platform.isWindows,
  );

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
