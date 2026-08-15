import 'package:mana_familiar/mana_inspect.dart';

/// Deterministic F10 fixture representing a long-lived mixed `.mana` history.
/// It remains generated rather than checked in as a multi-megabyte JSON blob.
const largeCatalogArtifactCount = 2400;

Map<String, dynamic> largeCatalogFixture({
  int count = largeCatalogArtifactCount,
}) {
  final artifacts = List<Map<String, dynamic>>.generate(count, (index) {
    final hex = index.toRadixString(16).padLeft(8, '0');
    final revision = hex.padLeft(64, '0');
    final mode = index % 23;
    final family = switch (mode) {
      0 || 1 => 'workspace',
      2 => 'learning',
      3 || 4 => 'knowledge',
      5 => 'unknown',
      _ => 'runtime',
    };
    final kind = switch (mode) {
      0 => 'verification-result',
      1 => 'review-findings',
      2 => 'file',
      3 => 'journey_record',
      4 => 'journey',
      5 => 'unknown',
      _ => 'runtime_events',
    };
    final status = switch (mode) {
      0 => 'failed',
      1 => 'blocked',
      2 => 'candidate',
      5 => 'malformed',
      6 => 'stale',
      7 => 'missing',
      _ => 'available',
    };
    final path = switch (mode) {
      2 => '.mana/learning/candidates/learning-$hex.json',
      3 =>
        '.mana/learning/journeys/jrn_000000000000000000000000/records/occ-$hex-concept_occurrence.yaml',
      4 => '.mana/learning/journeys/jrn_000000000000000000000000/journey.yaml',
      5 => '.mana/legacy/oversized-$hex.bin',
      _ => '.mana/$family/history/$hex.json',
    };
    return {
      'artifact_id': 'artifact:$hex',
      'path': path,
      'family': family,
      'kind': kind,
      'status': status,
      'revision_id': 'sha256:$revision',
      'updated_at': {
        'value':
            '2024-01-${(index % 28 + 1).toString().padLeft(2, '0')}T12:00:00Z',
        'provenance': 'fixture_history',
      },
      'byte_size': mode == 5 ? 262144 : 512 + index,
      if (mode == 2) 'candidateId': 'learning-$hex',
      if (mode == 5) 'diagnostic': 'fixture_malformed_or_oversized',
      if (mode == 6 || mode == 7) 'staleness': status,
      'relations': [
        if (index == 0) {'to': 'artifact:00000001'},
        if (index == 1) {'to': 'artifact:00000000'},
        if (index % 41 == 0)
          {
            'artifact_id':
                'artifact:${(index + 3).toRadixString(16).padLeft(8, '0')}',
            'source': {
              'path': index % 82 == 0
                  ? 'src/missing_$hex.dart'
                  : 'src/history_$hex.dart',
            },
            'staleness': index % 82 == 0 ? 'missing' : 'fresh',
          },
      ],
    };
  });
  return {
    'schema': inspectArtifactsSchema,
    'artifacts': artifacts,
    'guarantees': const {'model_calls': 0, 'writes': false},
    'diagnostics': const [],
  };
}
