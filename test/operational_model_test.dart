import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/operational_model.dart';
import 'package:mana_familiar/mana_inspect.dart';

void main() {
  test('groups and filters only Mana-reported activity fields', () {
    final entries = ActivityFilters(status: 'failed', recentOnly: true).apply([
      _artifact(
        'failure',
        'failed',
        timestamp: '2026-08-12T12:00:00Z',
        run: 'run-1',
      ),
      _artifact('unknown', 'failed', run: 'run-1'),
      _artifact(
        'pass',
        'available',
        timestamp: '2026-08-13T12:00:00Z',
        run: 'run-2',
      ),
    ]);
    expect(entries.map((entry) => entry.artifact.id), ['failure']);
    expect(entries.single.timestampProvenance, 'Mana artifact metadata');
  });

  test(
    'preserves verification failure/stale context without approval claims',
    () {
      final model = VerificationViewModel.fromPayload(
        {
          'result': 'FAILED',
          'checks': [
            {'name': 'unit', 'status': 'FAILED'},
          ],
          'evidence_paths': ['evidence/test.log'],
          'rerun_context': 'rerun after repair',
        },
        {'staleness': 'stale'},
      );
      expect(model.result, 'FAILED');
      expect(model.checks.single['status'], 'FAILED');
      expect(model.evidencePaths, ['evidence/test.log']);
      expect(model.stale, isTrue);
    },
  );

  test('retains the exact bounded repair result vocabulary', () {
    for (final result in ['RESOLVED', 'UNCHANGED', 'REGRESSED', 'UNKNOWN']) {
      expect(
        RepairViewModel.fromPayload({'final_result': result}, {}).finalResult,
        result,
      );
    }
    expect(
      RepairViewModel.fromPayload({'final_result': 'PASSED'}, {}).finalResult,
      'UNKNOWN',
    );
  });
}

ManaInspectArtifactSummary _artifact(
  String id,
  String status, {
  String? timestamp,
  String? run,
}) {
  final json = <String, dynamic>{
    'artifact_id': id,
    'path': '.mana/$id.json',
    'family': 'runtime',
    'kind': 'run-event',
    'status': status,
  };
  if (timestamp != null) json['timestamp'] = timestamp;
  if (run != null) json['run_id'] = run;
  return ManaInspectArtifactSummary.fromJson(json);
}
