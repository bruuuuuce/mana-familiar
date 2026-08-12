import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/artifact_renderer.dart';
import 'package:mana_familiar/mana_inspect.dart';

void main() {
  final registry = ArtifactRendererRegistry.standard();

  test('prefers an exact supported schema over kind and content type', () {
    final plan = registry.render(
      _context(
        payload: {
          'schema': 'mana.learning.graph/v1',
          'content_type': 'text/markdown',
        },
        family: 'unknown',
        kind: 'unknown',
      ),
    );
    expect(plan.rendererId, 'journey');
  });

  test('uses the Journey kind fallback deterministically', () {
    final plan = registry.render(
      _context(family: 'knowledge', kind: 'journey'),
    );
    expect(plan.rendererId, 'journey');
  });

  test('uses content type and unknown fallback safely', () {
    final markdown = registry.render(
      _context(
        payload: {'content_type': 'text/markdown', 'content': '# Heading'},
      ),
    );
    expect(markdown.view, ArtifactPayloadView.markdown);

    final unknown = registry.render(_context(payload: Object()));
    expect(unknown.view, ArtifactPayloadView.metadata);
  });

  test('rejects malformed, oversized, and deeply nested JSON payloads', () {
    const limits = ArtifactRenderLimits(
      maxPayloadCharacters: 5,
      maxJsonDepth: 2,
    );
    final malformed = registry.render(
      _context(payload: {'value': Object()}),
      limits: limits,
    );
    expect(malformed.view, ArtifactPayloadView.metadata);

    final oversized = registry.render(
      _context(payload: {'content_type': 'text/plain', 'content': '123456'}),
      limits: limits,
    );
    expect(oversized.view, ArtifactPayloadView.metadata);

    final oversizedJson = registry.render(
      _context(payload: {'large': '123456'}),
      limits: limits,
    );
    expect(oversizedJson.view, ArtifactPayloadView.metadata);

    final deep = registry.render(
      _context(
        payload: {
          'a': {
            'b': {'c': true},
          },
        },
      ),
      limits: limits,
    );
    expect(deep.view, ArtifactPayloadView.metadata);
    expect(deep.reason, contains('nesting'));
  });

  test(
    'Markdown is inert text with no HTML or executable link destination',
    () {
      final plan = registry.render(
        _context(
          payload: {
            'content_type': 'text/markdown',
            'content': '<script>alert(1)</script>[safe](javascript:alert(1))',
          },
        ),
      );
      expect(plan.text, contains('safe'));
      expect(plan.text, isNot(contains('script')));
      expect(plan.text, isNot(contains('javascript:')));
    },
  );

  test('relation previews remain bounded and identify cycles', () {
    final previews = boundedRelationPreviews(
      [
        {'to': 'b', 'kind': 'depends-on'},
        {'to': 'a', 'kind': 'returns-to-root'},
        {'to': 'b', 'kind': 'duplicate'},
        {'to': 'c', 'kind': 'related'},
      ],
      rootArtifactId: 'a',
      limits: const ArtifactRenderLimits(maxRelationPreviews: 3),
    );
    expect(previews, hasLength(3));
    expect(previews[1].cycle, isTrue);
    expect(previews[2].cycle, isTrue);
  });
}

ArtifactRenderContext _context({
  Object? payload = const {'value': true},
  String family = 'workspace',
  String kind = 'generic',
}) {
  final artifact = ManaInspectArtifactSummary.fromJson({
    'artifact_id': 'artifact:test',
    'path': '.mana/test',
    'family': family,
    'kind': kind,
    'status': 'available',
  });
  return ArtifactRenderContext(
    artifact: artifact,
    payload: payload,
    raw: const {},
    relations: const [],
  );
}
