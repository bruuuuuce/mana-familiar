import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/m08_performance_probe.dart';
import 'package:mana_familiar/application/mana_inspect.dart';

Map<String, dynamic> readReport(Directory directory) =>
    jsonDecode(
          File('${directory.path}/flutter-performance.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'batches observations off the UI isolate and flushes the final report',
    () async {
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
      for (var i = 0; i < 100; i++) {
        probe.recordProjection(
          const ManaInspectProjectionTrace(
            schema: inspectSemanticSnapshotSchema,
            elapsed: Duration(microseconds: 200),
          ),
        );
      }
      expect(await probe.flush(), isTrue);
      final report = readReport(directory);
      expect(report['schema'], 'mana-familiar.c04.flutter-performance/v1');
      expect(
        report['milestones_us'].keys,
        containsAll(['binding_ready', 'project_loading_shell']),
      );
      final process = (report['processes'] as List).single as Map;
      expect(process['operation'], 'semantic-snapshot');
      expect(process['elapsed_us'], 8000);
      expect(process['start_us'], isA<int>());
      expect(process['completed_us'], isA<int>());
      expect(process['response_bytes'], 4096);
      expect((report['decode'] as List).single, {
        'response_bytes': 4096,
        'offloaded': false,
        'elapsed_us': 1000,
      });
      expect(report['typed_projection'], hasLength(100));
      expect(report['diagnostics']['publication_isolate'], 'dedicated');
      expect(
        report['diagnostics']['prior_publications_count'],
        lessThan(10),
        reason: 'a synchronous burst must not create one write per observation',
      );
      final disposal = probe.dispose();
      expect(identical(disposal, probe.dispose()), isTrue);
      await disposal;
      probe.mark('ignored_after_disposal');
      expect(await probe.flush(), isFalse);
      final finalReport = readReport(directory);
      expect(finalReport['milestones_us'], contains('probe_disposed'));
      expect(
        finalReport['milestones_us'],
        isNot(contains('ignored_after_disposal')),
      );
      expect(jsonEncode(finalReport), isNot(contains(directory.path)));
    },
  );

  test('rejects a relative evidence destination', () {
    expect(() => M08PerformanceProbe('relative/path'), throwsArgumentError);
  });

  test(
    'failed publication keeps observations and a later flush recovers',
    () async {
      final directory = Directory.systemTemp.createTempSync('m08-retry-');
      final probe = M08PerformanceProbe(directory.path);
      addTearDown(() async {
        await probe.dispose();
        await directory.delete(recursive: true);
      });
      expect(await probe.flush(), isTrue);
      final target = File('${directory.path}/flutter-performance.json');
      await target.delete();
      final obstacle = Directory(target.path)..createSync();
      probe.mark('project_loading_shell');
      final failed = probe.flush();
      // More observations arrive while the single writer is retrying the older
      // batch. They must not disappear or be overwritten by an older report.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      probe.recordProjection(
        const ManaInspectProjectionTrace(
          schema: inspectSemanticSnapshotSchema,
          elapsed: Duration(microseconds: 200),
        ),
      );
      probe.mark('workspace_event');
      probe.mark('refresh_visible_route');
      expect(await failed, isFalse);
      await obstacle.delete();
      probe.mark('optional_surfaces_settled');
      expect(await probe.flush(), isTrue);
      final report = readReport(directory);
      expect(
        report['milestones_us'].keys,
        containsAll([
          'project_loading_shell',
          'workspace_event',
          'refresh_visible_route',
          'optional_surfaces_settled',
        ]),
      );
      expect(report['typed_projection'], hasLength(1));
      expect(
        report['diagnostics']['publication_failures'],
        greaterThanOrEqualTo(9),
      );
    },
  );

  test('last observation retries without further input', () async {
    final directory = Directory.systemTemp.createTempSync('m08-last-retry-');
    final probe = M08PerformanceProbe(directory.path);
    addTearDown(() async {
      await probe.dispose();
      await directory.delete(recursive: true);
    });
    expect(await probe.flush(), isTrue);
    final target = File('${directory.path}/flutter-performance.json');
    await target.delete();
    final obstacle = Directory(target.path)..createSync();
    probe.mark('refresh_visible_route');
    final completed = probe.flush();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await obstacle.delete();
    expect(await completed, isTrue);
    final report = readReport(directory);
    expect(report['milestones_us'], contains('refresh_visible_route'));
    expect(report['diagnostics']['publication_failures'], greaterThan(0));
  });

  test('startup writer failure does not throw or leave flush waiting', () async {
    final obstacle = File(
      '${Directory.systemTemp.path}/m08-writer-file-${DateTime.now().microsecondsSinceEpoch}',
    );
    await obstacle.writeAsString('not a directory');
    addTearDown(() => obstacle.delete());
    final probe = M08PerformanceProbe('${obstacle.path}/trace');
    probe.mark('project_loading_shell');
    expect(await probe.flush().timeout(const Duration(seconds: 5)), isFalse);
    await probe.dispose();
  });

  test(
    'refresh milestones follow the latest event even across queued batches',
    () async {
      final directory = Directory.systemTemp.createTempSync('m08-refresh-');
      final probe = M08PerformanceProbe(directory.path);
      addTearDown(() async {
        await probe.dispose();
        await directory.delete(recursive: true);
      });
      probe.mark('workspace_event');
      probe.mark('refresh_model_replaced');
      probe.mark('refresh_visible_route');
      expect(await probe.flush(), isTrue);
      final firstSequence =
          readReport(directory)['diagnostics']['published_sequence'] as int;
      probe.mark('workspace_event');
      expect(await probe.flush(), isTrue);
      final report = readReport(directory);
      expect(report['milestones_us'], contains('workspace_event'));
      expect(report['milestones_us'], isNot(contains('refresh_visible_route')));
      expect(
        report['milestones_us'],
        isNot(contains('refresh_model_replaced')),
      );
      expect(
        report['diagnostics']['published_sequence'],
        greaterThan(firstSequence),
      );
    },
  );

  test(
    'uses complete vsync-to-raster intervals for selection and overlap',
    () async {
      final directory = Directory.systemTemp.createTempSync('m08-phases-');
      final probe = M08PerformanceProbe(directory.path);
      addTearDown(() async {
        await probe.dispose();
        await directory.delete(recursive: true);
      });
      probe.mark('project_loading_shell');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      probe.recordProcess(
        const ManaInspectProcessTrace(
          operation: 'project',
          elapsed: Duration(milliseconds: 10),
          responseBytes: 10,
          exitCode: 0,
        ),
      );
      probe.mark('first_meaningful_overview');
      expect(await probe.flush(), isTrue);
      final before = readReport(directory);
      final process = (before['processes'] as List).single as Map;
      final start = process['start_us'] as int;
      final end = process['completed_us'] as int;
      final meaningful =
          before['milestones_us']['first_meaningful_overview'] as int;
      final origin = probe.timelineOriginUsForTesting;
      FrameTiming frame(
        int vsync,
        int build,
        int finish,
        int raster,
        int rasterEnd,
        int number,
      ) => FrameTiming(
        vsyncStart: origin + vsync,
        buildStart: origin + build,
        buildFinish: origin + finish,
        rasterStart: origin + raster,
        rasterFinish: origin + rasterEnd,
        rasterFinishWallTime: 0,
        frameNumber: number,
      );
      probe.recordFramesForTesting([
        // The old buildStart + totalSpan falsely overlapped the producer.
        frame(
          start - 20000,
          start - 5000,
          start - 4000,
          start - 4000,
          start - 3000,
          1,
        ),
        // The vsync wait overlaps the producer even though buildStart does not.
        frame(start + 1, end + 1, end + 1001, end + 1001, end + 2001, 2),
        // A delayed build must remain in the critical window based on vsyncStart.
        frame(
          meaningful - 1,
          meaningful + 10000,
          meaningful + 11000,
          meaningful + 11000,
          meaningful + 61000,
          3,
        ),
      ]);
      expect(await probe.flush(), isTrue);
      final frames = readReport(directory)['frames'] as Map;
      expect(frames['interval_clock'], 'vsync_start_to_raster_finish');
      expect(frames['critical_interval'], {
        'count': 2,
        'raw_count': 3,
        'producer_io_excluded_count': 1,
        'over_50ms': 1,
        'max_total_us': 61001,
        'raw_max_total_us': 61001,
      });
      for (final sample in frames['samples'] as List) {
        expect(sample['started_at_us'], sample['vsync_start_us']);
        expect(
          sample['total_us'],
          sample['raster_finish_us'] - sample['vsync_start_us'],
        );
        expect(
          sample['total_us'],
          sample['vsync_overhead_us'] +
              sample['build_us'] +
              sample['raster_queue_us'] +
              sample['raster_us'],
        );
      }
      final slow = (frames['samples'] as List).last;
      expect(slow['build_us'], 1000);
      expect(slow['vsync_overhead_us'], 10001);
      expect(slow['raster_us'], 50000);
      expect(slow['frame_number'], 3);
      expect(frames['samples_dropped'], 0);
    },
  );

  test(
    'sample limit is explicit while all-frame maxima retain dropped spikes',
    () async {
      final directory = Directory.systemTemp.createTempSync('m08-bound-');
      final probe = M08PerformanceProbe(directory.path);
      addTearDown(() async {
        await probe.dispose();
        await directory.delete(recursive: true);
      });
      final origin = probe.timelineOriginUsForTesting;
      FrameTiming frame(int total) => FrameTiming(
        vsyncStart: origin,
        buildStart: origin,
        buildFinish: origin + 1,
        rasterStart: origin + 1,
        rasterFinish: origin + total,
        rasterFinishWallTime: 0,
      );
      probe.recordFramesForTesting([
        for (var i = 0; i < 10000; i++) frame(100),
        frame(90000),
      ]);
      expect(await probe.flush(), isTrue);
      final frames = readReport(directory)['frames'] as Map;
      expect(frames['samples'], hasLength(10000));
      expect(frames['count'], 10001);
      expect(frames['samples_dropped'], 1);
      expect(frames['max_total_us'], 90000);
      expect(frames['over_50ms'], 1);
    },
  );

  test(
    'Windows reader lock cannot block UI observations or lose newer batches',
    () async {
      final directory = Directory.systemTemp.createTempSync('m08-lock-');
      final probe = M08PerformanceProbe(directory.path);
      expect(await probe.flush(), isTrue);
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
        await probe.dispose();
        await directory.delete(recursive: true);
      });
      expect(
        await locker.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'ready',
      );
      probe.mark('first_meaningful_overview');
      var finished = false;
      final failed = probe.flush().then((result) {
        finished = true;
        return result;
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(finished, isFalse);
      probe.recordProjection(
        const ManaInspectProjectionTrace(
          schema: inspectSemanticSnapshotSchema,
          elapsed: Duration(microseconds: 200),
        ),
      );
      expect(await failed, isFalse);
      await release.writeAsString('release');
      await locker.stdin.close();
      expect(await locker.exitCode.timeout(const Duration(seconds: 5)), 0);
      probe.mark('optional_surfaces_settled');
      expect(await probe.flush(), isTrue);
      final report = readReport(directory);
      expect(report['milestones_us'], contains('first_meaningful_overview'));
      expect(report['typed_projection'], hasLength(1));
      expect(
        report['diagnostics']['publication_failures'],
        greaterThanOrEqualTo(9),
      );
    },
    skip: !Platform.isWindows,
  );
}
