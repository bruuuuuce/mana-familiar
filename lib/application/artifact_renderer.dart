import 'dart:convert';

import 'mana_inspect.dart';

/// Conservative limits applied before a producer-owned payload reaches UI.
class ArtifactRenderLimits {
  const ArtifactRenderLimits({
    this.maxPayloadCharacters = 128 * 1024,
    this.maxJsonDepth = 16,
    this.maxJsonNodes = 1000,
    this.maxRelationPreviews = 20,
    this.maxRelationDepth = 2,
  });

  final int maxPayloadCharacters;
  final int maxJsonDepth;
  final int maxJsonNodes;
  final int maxRelationPreviews;
  final int maxRelationDepth;
}

enum ArtifactPayloadView { journey, json, markdown, text, metadata }

class ArtifactRenderContext {
  const ArtifactRenderContext({
    required this.artifact,
    required this.payload,
    required this.raw,
    required this.relations,
  });

  factory ArtifactRenderContext.fromDetail(ManaInspectArtifactDetail detail) =>
      ArtifactRenderContext(
        artifact: detail.artifact,
        payload: detail.payload,
        raw: detail.raw,
        relations: detail.relations,
      );

  final ManaInspectArtifactSummary artifact;
  final Object? payload;
  final Map<String, dynamic> raw;
  final List<Map<String, dynamic>> relations;

  String? get payloadSchema => _metadataString('schema');
  String? get contentType =>
      _metadataString('content_type') ??
      _metadataString('contentType') ??
      _metadataString('media_type');

  String? _metadataString(String key) {
    final direct = raw[key];
    if (direct is String && direct.isNotEmpty) return direct;
    if (payload case final Map map) {
      final value = map[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }
}

class ArtifactRenderPlan {
  const ArtifactRenderPlan({
    required this.rendererId,
    required this.view,
    required this.reason,
    this.text,
  });

  final String rendererId;
  final ArtifactPayloadView view;
  final String reason;
  final String? text;
}

abstract class ArtifactRenderer {
  const ArtifactRenderer(this.id);

  final String id;
  bool supportsExactSchema(ArtifactRenderContext context) => false;
  bool supportsKind(ArtifactRenderContext context) => false;
  bool supportsContentType(ArtifactRenderContext context) => false;
  ArtifactRenderPlan render(
    ArtifactRenderContext context,
    ArtifactRenderLimits limits,
  );
}

/// Explicit, ordered registry. It intentionally is not a plugin mechanism.
class ArtifactRendererRegistry {
  const ArtifactRendererRegistry(this.renderers);

  final List<ArtifactRenderer> renderers;

  factory ArtifactRendererRegistry.standard() => ArtifactRendererRegistry([
    const JourneyArtifactRenderer(),
    const JsonArtifactRenderer(),
    const MarkdownArtifactRenderer(),
    const PlainTextArtifactRenderer(),
    const MetadataArtifactRenderer(),
  ]);

  ArtifactRenderPlan render(
    ArtifactRenderContext context, {
    ArtifactRenderLimits limits = const ArtifactRenderLimits(),
  }) {
    for (final renderer in renderers) {
      if (renderer.supportsExactSchema(context)) {
        return renderer.render(context, limits);
      }
    }
    for (final renderer in renderers) {
      if (renderer.supportsKind(context)) {
        return renderer.render(context, limits);
      }
    }
    for (final renderer in renderers) {
      if (renderer.supportsContentType(context)) {
        return renderer.render(context, limits);
      }
    }
    return renderers.last.render(context, limits);
  }
}

class JourneyArtifactRenderer extends ArtifactRenderer {
  const JourneyArtifactRenderer() : super('journey');

  @override
  bool supportsExactSchema(ArtifactRenderContext context) =>
      context.payloadSchema == 'mana.learning.graph/v1';

  @override
  bool supportsKind(ArtifactRenderContext context) =>
      context.artifact.family == 'knowledge' &&
      context.artifact.kind == 'journey';

  @override
  ArtifactRenderPlan render(
    ArtifactRenderContext context,
    ArtifactRenderLimits limits,
  ) => const ArtifactRenderPlan(
    rendererId: 'journey',
    view: ArtifactPayloadView.journey,
    reason: 'Known Journey artifact',
  );
}

class JsonArtifactRenderer extends ArtifactRenderer {
  const JsonArtifactRenderer() : super('json');

  @override
  bool supportsExactSchema(ArtifactRenderContext context) =>
      context.payloadSchema == 'mana.inspect.artifact/v1';

  @override
  bool supportsContentType(ArtifactRenderContext context) =>
      context.contentType == 'application/json' ||
      (context.contentType == null &&
          (context.payload is Map || context.payload is List));

  @override
  ArtifactRenderPlan render(
    ArtifactRenderContext context,
    ArtifactRenderLimits limits,
  ) {
    final inspection = _inspectJson(context.payload, limits);
    if (!inspection.safe) {
      return ArtifactRenderPlan(
        rendererId: 'metadata',
        view: ArtifactPayloadView.metadata,
        reason: inspection.reason!,
      );
    }
    return ArtifactRenderPlan(
      rendererId: id,
      view: ArtifactPayloadView.json,
      reason: 'Validated JSON payload',
      text: const JsonEncoder.withIndent('  ').convert(context.payload),
    );
  }
}

class MarkdownArtifactRenderer extends ArtifactRenderer {
  const MarkdownArtifactRenderer() : super('markdown');

  @override
  bool supportsContentType(ArtifactRenderContext context) =>
      context.contentType == 'text/markdown' ||
      context.contentType == 'text/x-markdown';

  @override
  ArtifactRenderPlan render(
    ArtifactRenderContext context,
    ArtifactRenderLimits limits,
  ) {
    final text = _payloadText(context.payload);
    if (text == null) {
      return const ArtifactRenderPlan(
        rendererId: 'metadata',
        view: ArtifactPayloadView.metadata,
        reason: 'Markdown payload has no text body',
      );
    }
    if (text.length > limits.maxPayloadCharacters) {
      return const ArtifactRenderPlan(
        rendererId: 'metadata',
        view: ArtifactPayloadView.metadata,
        reason: 'Payload exceeds the safe display limit',
      );
    }
    return ArtifactRenderPlan(
      rendererId: id,
      view: ArtifactPayloadView.markdown,
      reason: 'Safely rendered Markdown',
      text: safeMarkdownText(text),
    );
  }
}

class PlainTextArtifactRenderer extends ArtifactRenderer {
  const PlainTextArtifactRenderer() : super('text');

  @override
  bool supportsContentType(ArtifactRenderContext context) =>
      context.contentType?.startsWith('text/') ?? context.payload is String;

  @override
  ArtifactRenderPlan render(
    ArtifactRenderContext context,
    ArtifactRenderLimits limits,
  ) {
    final text = _payloadText(context.payload);
    if (text == null) {
      return const ArtifactRenderPlan(
        rendererId: 'metadata',
        view: ArtifactPayloadView.metadata,
        reason: 'Text payload has no text body',
      );
    }
    if (text.length > limits.maxPayloadCharacters) {
      return const ArtifactRenderPlan(
        rendererId: 'metadata',
        view: ArtifactPayloadView.metadata,
        reason: 'Payload exceeds the safe display limit',
      );
    }
    return ArtifactRenderPlan(
      rendererId: id,
      view: ArtifactPayloadView.text,
      reason: 'Plain text payload',
      text: text,
    );
  }
}

class MetadataArtifactRenderer extends ArtifactRenderer {
  const MetadataArtifactRenderer() : super('metadata');

  @override
  ArtifactRenderPlan render(
    ArtifactRenderContext context,
    ArtifactRenderLimits limits,
  ) {
    final contentType = context.contentType;
    final reason =
        contentType != null &&
            !contentType.startsWith('text/') &&
            contentType != 'application/json'
        ? 'Unsupported or binary content: $contentType'
        : context.payload == null
        ? 'No payload was provided'
        : 'Unknown payload schema or kind';
    return ArtifactRenderPlan(
      rendererId: id,
      view: ArtifactPayloadView.metadata,
      reason: reason,
    );
  }
}

class RelationPreview {
  const RelationPreview({
    required this.id,
    required this.kind,
    this.cycle = false,
  });
  final String id;
  final String kind;
  final bool cycle;
}

List<RelationPreview> boundedRelationPreviews(
  List<Map<String, dynamic>> relations, {
  required String rootArtifactId,
  ArtifactRenderLimits limits = const ArtifactRenderLimits(),
}) {
  final visited = <String>{rootArtifactId};
  final result = <RelationPreview>[];
  for (final relation in relations.take(limits.maxRelationPreviews)) {
    final target =
        (relation['artifact_id'] ??
                relation['target_artifact_id'] ??
                relation['to'])
            ?.toString();
    if (target == null || target.isEmpty) continue;
    final cycle = !visited.add(target);
    result.add(
      RelationPreview(
        id: target,
        kind: relation['kind']?.toString() ?? 'related',
        cycle: cycle,
      ),
    );
  }
  return result;
}

String safeMarkdownText(String text) {
  var safe = text.replaceAll(RegExp(r'<[^>]*>', multiLine: true), '');
  safe = safe.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  safe = safe.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  return safe;
}

String? _payloadText(Object? payload) {
  if (payload is String) return payload;
  if (payload is Map) {
    final content = payload['content'] ?? payload['text'] ?? payload['body'];
    return content is String ? content : null;
  }
  return null;
}

_JsonInspection _inspectJson(Object? value, ArtifactRenderLimits limits) {
  var nodes = 0;
  var characters = 0;
  String? inspect(Object? current, int depth) {
    if (++nodes > limits.maxJsonNodes) {
      return 'JSON exceeds the safe node limit';
    }
    if (current is String) {
      characters += current.length;
      if (characters > limits.maxPayloadCharacters) {
        return 'JSON exceeds the safe display limit';
      }
    }
    if (depth > limits.maxJsonDepth) {
      return 'JSON exceeds the safe nesting depth';
    }
    if (current == null ||
        current is String ||
        current is num ||
        current is bool) {
      return null;
    }
    if (current is List) {
      for (final item in current) {
        final error = inspect(item, depth + 1);
        if (error != null) return error;
      }
      return null;
    }
    if (current is Map) {
      for (final entry in current.entries) {
        if (entry.key is! String) return 'Malformed JSON object key';
        characters += (entry.key as String).length;
        if (characters > limits.maxPayloadCharacters) {
          return 'JSON exceeds the safe display limit';
        }
        final error = inspect(entry.value, depth + 1);
        if (error != null) return error;
      }
      return null;
    }
    return 'Malformed JSON payload';
  }

  return _JsonInspection(inspect(value, 0));
}

class _JsonInspection {
  const _JsonInspection(this.reason);
  final String? reason;
  bool get safe => reason == null;
}
