import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release performance matrix preserves C04 evidence and budgets', () {
    final file = File(
      Platform.environment['M08_PERFORMANCE_REPORT'] ??
          'docs/roadmap/m08-familiar-performance-matrix.json',
    );
    final expectedClasses =
        Platform.environment['M08_PERFORMANCE_CLASSES']
            ?.split(',')
            .where((value) => value.isNotEmpty)
            .toList(growable: false) ??
        const ['small', 'medium', 'large', 'hostile-large'];
    final raw = file.readAsStringSync();
    final report = jsonDecode(raw) as Map<String, dynamic>;

    expect(report['schema'], 'mana-familiar.c04.performance-matrix/v1');
    expect(report['build_mode'], 'release');
    expect(report['runs_per_fixture'], {'cold': 5, 'warm': 5});
    final environment = report['environment'] as Map<String, dynamic>;
    expect(environment['machine'], isNotEmpty);
    expect(environment['flutter'], contains('stable'));
    expect(environment['mana_revision'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(
      environment['familiar_revision'],
      matches(RegExp(r'^[0-9a-f]{40}$')),
    );
    expect(environment['mana_dirty'], isA<bool>());
    expect(environment['familiar_dirty'], isA<bool>());
    expect(report['background_load_policy'], contains('route-minimal'));
    expect(raw, isNot(contains('/Users/')));
    expect(raw, isNot(contains('/private/')));

    final fixtures = (report['fixtures'] as List).cast<Map<String, dynamic>>();
    expect(fixtures.map((fixture) => fixture['class']), expectedClasses);
    for (final fixture in fixtures) {
      final cold = (fixture['cold'] as List).cast<Map<String, dynamic>>();
      final warm = (fixture['warm'] as List).cast<Map<String, dynamic>>();
      expect(cold, hasLength(5));
      expect(warm, hasLength(5));
      for (final run in [...cold, ...warm]) {
        expect(run['build_mode'], 'release');
        final meaningful =
            (run['milestones_us']
                    as Map<String, dynamic>)['first_meaningful_overview']
                as int;
        final processes = (run['processes'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          processes
              .where((process) => (process['start_us'] as int) < meaningful)
              .map((process) => process['operation']),
          ['project', 'semantic-snapshot'],
        );
        expect(run['typed_projection'], isNotEmpty);
      }
    }

    final budgetedFixtures = <Map<String, dynamic>>[];
    if (expectedClasses.contains('medium')) {
      final medium = fixtures.singleWhere(
        (fixture) => fixture['class'] == 'medium',
      );
      final mediumMedians = medium['median_us'] as Map<String, dynamic>;
      expect(
        mediumMedians['cold_first_meaningful_overview'],
        lessThanOrEqualTo(2000000),
      );
      expect(
        mediumMedians['warm_first_meaningful_overview'],
        lessThanOrEqualTo(1000000),
      );
      budgetedFixtures.add(medium);
    }
    if (expectedClasses.contains('large')) {
      final large = fixtures.singleWhere(
        (fixture) => fixture['class'] == 'large',
      );
      final largeMedians = large['median_us'] as Map<String, dynamic>;
      expect(
        largeMedians['cold_first_meaningful_overview'],
        lessThanOrEqualTo(3000000),
      );
      budgetedFixtures.add(large);
    }
    for (final fixture in budgetedFixtures) {
      for (final phase in ['cold', 'warm']) {
        for (final run
            in (fixture[phase] as List).cast<Map<String, dynamic>>()) {
          final decode = (run['decode'] as List).cast<Map<String, dynamic>>();
          expect(
            decode.map((trace) => trace['elapsed_us'] as int),
            everyElement(lessThanOrEqualTo(16000)),
          );
        }
      }
    }
  });

  test('native release matrix proves frame and memory budgets', () {
    final file = File(
      Platform.environment['M08_NATIVE_PERFORMANCE_REPORT'] ??
          'docs/roadmap/m08-macos-native-performance-matrix.json',
    );
    final raw = file.readAsStringSync();
    final report = jsonDecode(raw) as Map<String, dynamic>;
    expect(report['schema'], 'mana-familiar.c04.native-performance-matrix/v1');
    final environment = report['environment'] as Map<String, dynamic>;
    expect(environment['flutter'], contains('stable'));
    expect(environment['mana_revision'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(
      environment['familiar_revision'],
      matches(RegExp(r'^[0-9a-f]{40}$')),
    );
    expect(report['background_load_policy'], contains('route-minimal'));
    expect(report['cache_policy'], {
      'cold': 'isolated empty MANA_CACHE_HOME per run',
      'warm': 'one priming run followed by repeated shared-cache runs',
    });
    expect(raw, isNot(contains('/Users/')));
    expect(raw, isNot(contains('/private/')));
    final fixture = report['fixture'] as Map<String, dynamic>;
    expect(fixture['class'], 'large');
    expect(fixture['logical_counts'], {
      'artifacts': 10000,
      'knowledge_documents': 2000,
      'runtime_events': 50000,
      'work_items': 500,
    });
    final runs = report['runs'] as Map<String, dynamic>;
    var evaluatedCriticalFrames = 0;
    for (final phase in ['cold', 'warm']) {
      final samples = (runs[phase] as List).cast<Map<String, dynamic>>();
      expect(samples, hasLength(5));
      for (final sample in samples) {
        expect(sample['build_mode'], 'release');
        expect(sample['native_window_us'], inInclusiveRange(1, 2000000));
        expect(
          sample['project_to_loading_shell_us'],
          lessThanOrEqualTo(2000000),
        );
        expect(sample['max_ui_isolate_decode_us'], lessThanOrEqualTo(16000));
        expect(
          sample['maximum_observed_rss_bytes'],
          lessThanOrEqualTo(256 * 1024 * 1024),
        );
        final frames = sample['frames'] as Map<String, dynamic>;
        final critical = frames['critical_interval'] as Map<String, dynamic>;
        evaluatedCriticalFrames += critical['count'] as int;
        expect(critical['count'], greaterThanOrEqualTo(0));
        expect(critical['raw_count'], greaterThan(0));
        expect(critical['raw_count'], greaterThanOrEqualTo(critical['count']));
        expect(critical['producer_io_excluded_count'], greaterThan(0));
        expect(critical['raw_max_total_us'], greaterThan(0));
        expect(critical['over_50ms'], 0);
        expect(critical['max_total_us'], lessThanOrEqualTo(50000));
        final processes = (sample['processes'] as List)
            .cast<Map<String, dynamic>>();
        expect(processes.take(3).map((process) => process['operation']), [
          'project',
          'semantic-snapshot',
          'semantic-snapshot',
        ]);
        expect(
          processes,
          everyElement(
            allOf(
              containsPair('start_us', isA<int>()),
              containsPair('completed_us', isA<int>()),
            ),
          ),
        );
        final refreshProcesses = (sample['refresh_processes'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          refreshProcesses.map((process) => process['operation']),
          ['project', 'semantic-snapshot'],
          reason: 'five atomic publications must coalesce into one refresh',
        );
        expect(sample['workspace_refresh_us'], lessThanOrEqualTo(5000000));
        expect(
          sample['refresh_model_replaced'],
          isFalse,
          reason: 'same-byte atomic publications must retain the read model',
        );
      }
    }
    expect(evaluatedCriticalFrames, greaterThan(0));
    final medians = report['medians_us'] as Map<String, dynamic>;
    for (final phase in ['cold', 'warm']) {
      expect(
        (medians[phase]
            as Map<String, dynamic>)['loading_shell_to_meaningful_overview_us'],
        lessThanOrEqualTo(3000000),
      );
    }
  });
}
