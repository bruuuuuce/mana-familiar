import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'mana_inspect.dart';

/// Opt-in, payload-free timing evidence for the M08 native performance gate.
///
/// Product launches do not create this probe. A performance harness must pass
/// an explicit output directory; the report contains durations, sizes, schema
/// names, frame timings, and RSS samples only.
class M08PerformanceProbe {
  M08PerformanceProbe(String outputDirectory)
    : _directory = Directory(outputDirectory),
      _clock = Stopwatch()..start() {
    if (outputDirectory.isEmpty || !Directory(outputDirectory).isAbsolute) {
      throw ArgumentError.value(
        outputDirectory,
        'outputDirectory',
        'must be an absolute path',
      );
    }
    _directory.createSync(recursive: true);
    _timelineOriginUs = developer.Timeline.now - _clock.elapsedMicroseconds;
    SchedulerBinding.instance.addTimingsCallback(_recordFrames);
    mark('binding_ready');
  }

  final Directory _directory;
  final Stopwatch _clock;
  late final int _timelineOriginUs;
  final Map<String, int> _milestones = {};
  final Map<String, int> _rssAtMilestone = {};
  final List<Map<String, Object?>> _processes = [];
  final List<Map<String, Object?>> _decodes = [];
  final List<Map<String, Object?>> _projections = [];
  final List<Map<String, int>> _frameSamples = [];
  var _frameCount = 0;
  var _framesOver50ms = 0;
  var _maxBuildUs = 0;
  var _maxRasterUs = 0;
  var _maxTotalUs = 0;
  var _maximumRss = 0;
  var _disposed = false;

  void mark(String milestone) {
    if (_disposed) return;
    if (milestone == 'workspace_event') {
      // Refresh evidence is a cycle, not a startup milestone. Re-arm it so a
      // root-level FSEvent observed while the app settles cannot contaminate
      // the later publication measured by the native harness.
      _milestones.remove('refresh_visible_route');
      _milestones.remove('refresh_model_replaced');
      _rssAtMilestone.remove('refresh_visible_route');
      _rssAtMilestone.remove('refresh_model_replaced');
    } else if (_milestones.containsKey(milestone) &&
        milestone != 'refresh_visible_route' &&
        milestone != 'refresh_model_replaced') {
      return;
    }
    _milestones[milestone] = _clock.elapsedMicroseconds;
    final rss = ProcessInfo.currentRss;
    _rssAtMilestone[milestone] = rss;
    if (rss > _maximumRss) _maximumRss = rss;
    _publish();
  }

  void recordProcess(ManaInspectProcessTrace trace) {
    if (_disposed) return;
    final completedAt = _clock.elapsedMicroseconds;
    final startedAt = completedAt - trace.elapsed.inMicroseconds;
    _processes.add({
      'operation': trace.operation,
      'start_us': startedAt < 0 ? 0 : startedAt,
      'completed_us': completedAt,
      'elapsed_us': trace.elapsed.inMicroseconds,
      'response_bytes': trace.responseBytes,
      'exit_code': trace.exitCode,
    });
    _publish();
  }

  void recordDecode(ManaInspectDecodeTrace trace) {
    if (_disposed) return;
    _decodes.add({
      'response_bytes': trace.responseBytes,
      if (trace.pipelineElapsed != null)
        'pipeline_elapsed_us': trace.pipelineElapsed!.inMicroseconds,
      'offloaded': trace.offloaded,
      'elapsed_us': trace.elapsed.inMicroseconds,
    });
    _publish();
  }

  void recordProjection(ManaInspectProjectionTrace trace) {
    if (_disposed) return;
    _projections.add({
      'schema': trace.schema,
      if (trace.failureCode != null) 'failure_code': trace.failureCode,
      'offloaded': trace.offloaded,
      'elapsed_us': trace.elapsed.inMicroseconds,
    });
    _publish();
  }

  void _recordFrames(List<FrameTiming> timings) {
    if (_disposed) return;
    for (final timing in timings) {
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      final total = timing.totalSpan.inMicroseconds;
      _frameCount++;
      if (total > 50000) _framesOver50ms++;
      if (build > _maxBuildUs) _maxBuildUs = build;
      if (raster > _maxRasterUs) _maxRasterUs = raster;
      if (total > _maxTotalUs) _maxTotalUs = total;
      if (_frameSamples.length < 10000) {
        _frameSamples.add({
          'started_at_us':
              timing.timestampInMicroseconds(FramePhase.buildStart) -
              _timelineOriginUs,
          'observed_at_us': _clock.elapsedMicroseconds,
          'build_us': build,
          'raster_us': raster,
          'total_us': total,
        });
      }
    }
    final rss = ProcessInfo.currentRss;
    if (rss > _maximumRss) _maximumRss = rss;
    _publish();
  }

  void dispose() {
    if (_disposed) return;
    SchedulerBinding.instance.removeTimingsCallback(_recordFrames);
    mark('probe_disposed');
    _disposed = true;
    _clock.stop();
    _publish();
  }

  void _publish() {
    final loadingShell = _milestones['project_loading_shell'];
    final meaningful = _milestones['first_meaningful_overview'];
    final criticalWindowFrames = loadingShell == null || meaningful == null
        ? const <Map<String, int>>[]
        : _frameSamples
              .where(
                (frame) =>
                    frame['started_at_us']! >= loadingShell &&
                    frame['started_at_us']! <= meaningful,
              )
              .toList(growable: false);
    bool overlapsProducerIo(Map<String, int> frame) {
      final frameStart = frame['started_at_us']!;
      final frameEnd = frameStart + frame['total_us']!;
      return _processes.any((process) {
        final processStart = process['start_us'];
        final processEnd = process['completed_us'];
        return processStart is int &&
            processEnd is int &&
            frameStart < processEnd &&
            frameEnd > processStart;
      });
    }

    // C04 excludes time awaiting the external producer from the Flutter frame
    // budget. Keep the raw interval beside the evaluated interval so the
    // exclusion is explicit and an anomalous producer-overlap frame is not
    // silently lost from the evidence.
    final criticalFrames = criticalWindowFrames
        .where((frame) => !overlapsProducerIo(frame))
        .toList(growable: false);
    final producerIoFrames =
        criticalWindowFrames.length - criticalFrames.length;
    final report = {
      'schema': 'mana-familiar.c04.flutter-performance/v1',
      'build_mode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'environment': {
        'os': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'dart': Platform.version.split(' ').first,
      },
      'milestones_us': _milestones,
      'rss_bytes': {
        'maximum_observed': _maximumRss,
        'at_milestone': _rssAtMilestone,
      },
      'frames': {
        'count': _frameCount,
        'over_50ms': _framesOver50ms,
        'max_build_us': _maxBuildUs,
        'max_raster_us': _maxRasterUs,
        'max_total_us': _maxTotalUs,
        'critical_interval': {
          'count': criticalFrames.length,
          'raw_count': criticalWindowFrames.length,
          'producer_io_excluded_count': producerIoFrames,
          'over_50ms': criticalFrames
              .where((frame) => frame['total_us']! > 50000)
              .length,
          'max_total_us': criticalFrames.fold<int>(
            0,
            (maximum, frame) =>
                frame['total_us']! > maximum ? frame['total_us']! : maximum,
          ),
          'raw_max_total_us': criticalWindowFrames.fold<int>(
            0,
            (maximum, frame) =>
                frame['total_us']! > maximum ? frame['total_us']! : maximum,
          ),
        },
        'samples': _frameSamples,
      },
      'processes': _processes,
      'decode': _decodes,
      'typed_projection': _projections,
      'privacy': {
        'source_content': false,
        'absolute_paths': false,
        'credentials': false,
        'responses': false,
      },
    };
    final target = File(
      '${_directory.path}${Platform.pathSeparator}flutter-performance.json',
    );
    final temporary = File('${target.path}.tmp');
    temporary.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      flush: true,
    );
    try {
      temporary.renameSync(target.path);
    } on FileSystemException {
      if (target.existsSync()) target.deleteSync();
      temporary.renameSync(target.path);
    }
  }
}
