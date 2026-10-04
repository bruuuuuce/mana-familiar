import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'mana_inspect.dart';
import 'm08_performance_writer.dart';

/// Opt-in, payload-free native timing evidence.
///
/// The UI isolate collects numeric observations only. A dedicated isolate owns
/// aggregation, JSON encoding, file publication and Windows replacement retries.
class M08PerformanceProbe {
  M08PerformanceProbe(String outputDirectory) : _clock = Stopwatch()..start() {
    if (outputDirectory.isEmpty || !Directory(outputDirectory).isAbsolute) {
      throw ArgumentError.value(
        outputDirectory,
        'outputDirectory',
        'must be an absolute path',
      );
    }
    _timelineOriginUs = developer.Timeline.now - _clock.elapsedMicroseconds;
    _messages.listen(_receive);
    unawaited(
      Isolate.spawn(
        runM08PerformanceWriter,
        [
          _messages.sendPort,
          outputDirectory,
          {
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
          },
        ],
        onError: _messages.sendPort,
        onExit: _messages.sendPort,
      ).then((isolate) {
        _isolate = isolate;
        if (_failed) isolate.kill(priority: Isolate.immediate);
      }, onError: (Object error, StackTrace stack) => _failWriter()),
    );
    SchedulerBinding.instance.addTimingsCallback(_recordFrames);
    mark('binding_ready');
  }

  final Stopwatch _clock;
  late final int _timelineOriginUs;
  final ReceivePort _messages = ReceivePort();
  final Set<String> _milestoneNames = {};
  final List<Map<String, Object?>> _pending = [];
  final Map<int, List<Completer<bool>>> _waiters = {};
  SendPort? _writer;
  Isolate? _isolate;
  Timer? _batchTimer;
  int _sequence = 0;
  int? _inFlight;
  bool _failed = false;
  bool _disposed = false;
  Future<void>? _disposal;

  @visibleForTesting
  int get timelineOriginUsForTesting => _timelineOriginUs;

  void mark(String milestone) {
    if (_disposed || _failed) return;
    if (milestone == 'workspace_event') {
      _milestoneNames.remove('refresh_visible_route');
      _milestoneNames.remove('refresh_model_replaced');
    } else if (_milestoneNames.contains(milestone) &&
        milestone != 'refresh_visible_route' &&
        milestone != 'refresh_model_replaced') {
      return;
    }
    _milestoneNames.add(milestone);
    _enqueue({
      'kind': 'mark',
      'name': milestone,
      'time_us': _clock.elapsedMicroseconds,
      'rss': ProcessInfo.currentRss,
    });
  }

  void recordProcess(ManaInspectProcessTrace trace) {
    if (_disposed || _failed) return;
    final completedAt = _clock.elapsedMicroseconds;
    final startedAt = completedAt - trace.elapsed.inMicroseconds;
    _enqueue({
      'kind': 'process',
      'value': {
        'operation': trace.operation,
        'start_us': startedAt < 0 ? 0 : startedAt,
        'completed_us': completedAt,
        'elapsed_us': trace.elapsed.inMicroseconds,
        'response_bytes': trace.responseBytes,
        'exit_code': trace.exitCode,
        if (trace.transportErrorCode != null)
          'transport_error_code': trace.transportErrorCode,
      },
    });
  }

  void recordDecode(ManaInspectDecodeTrace trace) {
    if (_disposed || _failed) return;
    _enqueue({
      'kind': 'decode',
      'value': {
        'response_bytes': trace.responseBytes,
        if (trace.pipelineElapsed != null)
          'pipeline_elapsed_us': trace.pipelineElapsed!.inMicroseconds,
        'offloaded': trace.offloaded,
        'elapsed_us': trace.elapsed.inMicroseconds,
      },
    });
  }

  void recordProjection(ManaInspectProjectionTrace trace) {
    if (_disposed || _failed) return;
    _enqueue({
      'kind': 'projection',
      'value': {
        'schema': trace.schema,
        if (trace.failureCode != null) 'failure_code': trace.failureCode,
        'offloaded': trace.offloaded,
        'elapsed_us': trace.elapsed.inMicroseconds,
      },
    });
  }

  @visibleForTesting
  void recordFramesForTesting(List<FrameTiming> timings) =>
      _recordFrames(timings);

  void _recordFrames(List<FrameTiming> timings) {
    if (_disposed || _failed) return;
    final observed = _clock.elapsedMicroseconds;
    int timestamp(FrameTiming timing, FramePhase phase) =>
        timing.timestampInMicroseconds(phase) - _timelineOriginUs;
    _enqueue({
      'kind': 'frames',
      'rss': ProcessInfo.currentRss,
      'values': [
        for (final timing in timings)
          {
            // totalSpan is vsyncStart -> rasterFinish, not buildStart -> finish.
            'started_at_us': timestamp(timing, FramePhase.vsyncStart),
            'vsync_start_us': timestamp(timing, FramePhase.vsyncStart),
            'build_start_us': timestamp(timing, FramePhase.buildStart),
            'build_finish_us': timestamp(timing, FramePhase.buildFinish),
            'raster_start_us': timestamp(timing, FramePhase.rasterStart),
            'raster_finish_us': timestamp(timing, FramePhase.rasterFinish),
            'observed_at_us': observed,
            'vsync_overhead_us': timing.vsyncOverhead.inMicroseconds,
            'build_us': timing.buildDuration.inMicroseconds,
            'raster_queue_us':
                timing.timestampInMicroseconds(FramePhase.rasterStart) -
                timing.timestampInMicroseconds(FramePhase.buildFinish),
            'raster_us': timing.rasterDuration.inMicroseconds,
            'total_us': timing.totalSpan.inMicroseconds,
            'frame_number': timing.frameNumber,
          },
      ],
    });
  }

  void _enqueue(Map<String, Object?> event) {
    _pending.add(event);
    _sequence++;
    _batchTimer ??= Timer(const Duration(milliseconds: 16), _sendBatch);
  }

  void _sendBatch() {
    _batchTimer?.cancel();
    _batchTimer = null;
    if (_failed || _writer == null || _inFlight != null || _pending.isEmpty) {
      return;
    }
    final events = List<Map<String, Object?>>.of(_pending);
    _pending.clear();
    _inFlight = _sequence;
    _writer!.send({'sequence': _sequence, 'events': events});
  }

  void _receive(dynamic message) {
    if (message is SendPort) {
      _writer = message;
      _sendBatch();
    } else if (message is Map && message['sequence'] is int) {
      final sequence = message['sequence'] as int;
      if (sequence != _inFlight) {
        _failWriter();
        return;
      }
      _inFlight = null;
      final completed = _waiters.keys.where((key) => key <= sequence).toList();
      for (final key in completed) {
        for (final waiter in _waiters.remove(key)!) {
          waiter.complete(message['published'] == true);
        }
      }
      if (_pending.isNotEmpty) {
        _batchTimer ??= Timer(const Duration(milliseconds: 16), _sendBatch);
      }
    } else {
      // Isolate startup/error/exit must not break product observations or leave
      // a flush waiting forever. Do not retain exception text in evidence.
      _failWriter();
    }
  }

  void _failWriter() {
    _failed = true;
    _batchTimer?.cancel();
    _batchTimer = null;
    _pending.clear();
    for (final waiters in _waiters.values) {
      for (final waiter in waiters) {
        waiter.complete(false);
      }
    }
    _waiters.clear();
    _messages.close();
    _isolate?.kill(priority: Isolate.immediate);
  }

  /// Wait for a durable report containing every preceding observation.
  /// A bounded publication failure is reported as false, never as model failure.
  Future<bool> flush() => _disposed ? Future.value(false) : _flush();

  Future<bool> _flush() {
    if (_failed) return Future.value(false);
    _enqueue({'kind': 'flush'});
    final waiter = Completer<bool>();
    (_waiters[_sequence] ??= []).add(waiter);
    _sendBatch();
    return waiter.future;
  }

  /// Stops collection immediately and releases the writer after its final report.
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    SchedulerBinding.instance.removeTimingsCallback(_recordFrames);
    mark('probe_disposed');
    _disposed = true;
    _clock.stop();
    await _flush();
    _batchTimer?.cancel();
    _messages.close();
    _isolate?.kill(priority: Isolate.immediate);
  }
}
