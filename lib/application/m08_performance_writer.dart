import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

// The worker uses dart:io only: no scheduler, platform channel or UI callbacks.
void runM08PerformanceWriter(List<Object?> configuration) {
  final replies = configuration[0] as SendPort;
  final inbox = ReceivePort();
  final writer = _PerformanceReportWriter(
    configuration[1] as String,
    Map<String, Object?>.from(configuration[2] as Map),
  );
  replies.send(inbox.sendPort);
  inbox.listen((dynamic message) async {
    final batch = message as Map;
    final sequence = batch['sequence'] as int;
    writer.record((batch['events'] as List).cast<Map<String, Object?>>());
    final published = await writer.publish(sequence);
    replies.send({'sequence': sequence, 'published': published});
  });
}

class _PerformanceReportWriter {
  _PerformanceReportWriter(String directory, this._metadata)
    : _directory = Directory(directory) {
    _directory.createSync(recursive: true);
  }

  final Directory _directory;
  final Map<String, Object?> _metadata;
  final Map<String, int> _milestones = {};
  final Map<String, int> _rssAtMilestone = {};
  final List<Map<String, Object?>> _processes = [];
  final List<Map<String, Object?>> _decodes = [];
  final List<Map<String, Object?>> _projections = [];
  final List<Map<String, int>> _frames = [];
  int _frameCount = 0,
      _framesOver50ms = 0,
      _maxBuildUs = 0,
      _maxRasterUs = 0,
      _maxTotalUs = 0,
      _maximumRss = 0;
  int _lastFrameObservedUs = 0;
  int _publicationFailures = 0,
      _publicationCount = 0,
      _lastPublicationUs = 0,
      _maxPublicationUs = 0;

  void _rss(int rss) {
    if (rss > _maximumRss) _maximumRss = rss;
  }

  void record(List<Map<String, Object?>> events) {
    for (final event in events) {
      switch (event['kind']) {
        case 'mark':
          final name = event['name'] as String;
          if (name == 'workspace_event') {
            for (final key in [
              'refresh_visible_route',
              'refresh_model_replaced',
            ]) {
              _milestones.remove(key);
              _rssAtMilestone.remove(key);
            }
          }
          _milestones[name] = event['time_us'] as int;
          final rss = event['rss'] as int;
          _rssAtMilestone[name] = rss;
          _rss(rss);
        case 'process':
          _processes.add(Map<String, Object?>.from(event['value'] as Map));
        case 'decode':
          _decodes.add(Map<String, Object?>.from(event['value'] as Map));
        case 'projection':
          _projections.add(Map<String, Object?>.from(event['value'] as Map));
        case 'frames':
          _rss(event['rss'] as int);
          for (final value in event['values'] as List) {
            final frame = Map<String, int>.from(value as Map);
            _lastFrameObservedUs = frame['observed_at_us']!;
            _frameCount++;
            if (frame['total_us']! > 50000) _framesOver50ms++;
            if (frame['build_us']! > _maxBuildUs) {
              _maxBuildUs = frame['build_us']!;
            }
            if (frame['raster_us']! > _maxRasterUs) {
              _maxRasterUs = frame['raster_us']!;
            }
            if (frame['total_us']! > _maxTotalUs) {
              _maxTotalUs = frame['total_us']!;
            }
            if (_frames.length < 10000) _frames.add(frame);
          }
      }
    }
  }

  Map<String, Object?> _report(int sequence) {
    final loading = _milestones['project_loading_shell'];
    final meaningful = _milestones['first_meaningful_overview'];
    final raw = loading == null || meaningful == null
        ? <Map<String, int>>[]
        : _frames
              .where(
                (f) =>
                    f['vsync_start_us']! >= loading &&
                    f['vsync_start_us']! <= meaningful,
              )
              .toList(growable: false);
    bool producerOverlap(Map<String, int> frame) => _processes.any(
      (p) =>
          frame['vsync_start_us']! < (p['completed_us'] as int) &&
          frame['raster_finish_us']! > (p['start_us'] as int),
    );
    final evaluated = raw
        .where((frame) => !producerOverlap(frame))
        .toList(growable: false);
    int maxTotal(List<Map<String, int>> frames) => frames.fold(
      0,
      (maximum, frame) =>
          frame['total_us']! > maximum ? frame['total_us']! : maximum,
    );
    return {
      'schema': 'mana-familiar.c04.flutter-performance/v1',
      ..._metadata,
      'milestones_us': _milestones,
      'rss_bytes': {
        'maximum_observed': _maximumRss,
        'at_milestone': _rssAtMilestone,
      },
      'frames': {
        'interval_clock': 'vsync_start_to_raster_finish',
        'count': _frameCount,
        'over_50ms': _framesOver50ms,
        'max_build_us': _maxBuildUs,
        'max_raster_us': _maxRasterUs,
        'max_total_us': _maxTotalUs,
        'samples_dropped': _frameCount - _frames.length,
        'last_observed_at_us': _lastFrameObservedUs,
        'critical_interval': {
          'count': evaluated.length,
          'raw_count': raw.length,
          'producer_io_excluded_count': raw.length - evaluated.length,
          'over_50ms': evaluated
              .where((frame) => frame['total_us']! > 50000)
              .length,
          'max_total_us': maxTotal(evaluated),
          'raw_max_total_us': maxTotal(raw),
        },
        'samples': _frames,
      },
      'processes': _processes,
      'decode': _decodes,
      'typed_projection': _projections,
      'diagnostics': {
        'publication_failures': _publicationFailures,
        'publication_isolate': 'dedicated', 'published_sequence': sequence,
        // These durations describe completed earlier attempts, avoiding a
        // second write just to insert the duration of the current write.
        'prior_publications_count': _publicationCount,
        'prior_publication_last_elapsed_us': _lastPublicationUs,
        'prior_publication_max_elapsed_us': _maxPublicationUs,
      },
      'privacy': {
        'source_content': false,
        'absolute_paths': false,
        'credentials': false,
        'responses': false,
      },
    };
  }

  Future<bool> publish(int sequence) async {
    final target = File(
      '${_directory.path}${Platform.pathSeparator}flutter-performance.json',
    );
    final temporary = File('${target.path}.tmp');
    for (var attempt = 0; attempt <= 8; attempt++) {
      final clock = Stopwatch()..start();
      try {
        temporary.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(_report(sequence))}\n',
          flush: true,
        );
        try {
          temporary.renameSync(target.path);
        } on FileSystemException {
          if (target.existsSync()) target.deleteSync();
          temporary.renameSync(target.path);
        }
        return true;
      } on FileSystemException {
        _publicationFailures++;
      } finally {
        _lastPublicationUs = clock.elapsedMicroseconds;
        if (_lastPublicationUs > _maxPublicationUs) {
          _maxPublicationUs = _lastPublicationUs;
        }
        _publicationCount++;
      }
      if (attempt < 8) {
        await Future<void>.delayed(const Duration(milliseconds: 33));
      }
    }
    return false;
  }
}
