import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/observatory_model.dart';

import 'package:mana_familiar/mana_inspect.dart';

void main() {
  test('prioritizes failed, blocked, stale, and malformed catalog items', () {
    final catalog = ManaInspectCatalog.fromJson({
      'schema': inspectArtifactsSchema,
      'artifacts': [
        _artifact('failed', 'failed'),
        _artifact('blocked', 'blocked'),
        {..._artifact('stale', 'available'), 'staleness': 'stale'},
        _artifact('bad', 'malformed'),
      ],
      'guarantees': const {},
      'diagnostics': const [],
    });
    final overview = ObservatoryOverview.fromCatalog(catalog);
    expect(overview.failed.single.id, 'failed');
    expect(overview.blocking.single.id, 'blocked');
    expect(overview.staleOrMissing.single.id, 'stale');
    expect(
      overview.attention.map((item) => item.artifact.id),
      containsAll(['failed', 'blocked', 'stale', 'bad']),
    );
  });
}

Map<String, dynamic> _artifact(String id, String status) => {
  'artifact_id': id,
  'path': '.mana/$id.json',
  'family': 'workspace',
  'kind': 'file',
  'status': status,
};
