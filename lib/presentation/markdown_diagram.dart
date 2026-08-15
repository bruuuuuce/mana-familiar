import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum MarkdownDiagramLanguage { mermaid, plantUml }

/// A bounded native renderer for the small flowchart and sequence subsets used
/// by Mana documents. It never executes source, opens links, reads files, or
/// delegates rendering to a browser or network service.
class MarkdownDiagramView extends StatefulWidget {
  const MarkdownDiagramView({
    super.key,
    required this.language,
    required this.source,
  });

  final MarkdownDiagramLanguage language;
  final String source;

  @override
  State<MarkdownDiagramView> createState() => _MarkdownDiagramViewState();
}

class _MarkdownDiagramViewState extends State<MarkdownDiagramView> {
  static final LinkedHashMap<String, _DiagramParseResult> _cache =
      LinkedHashMap();
  static const _cacheLimit = 32;
  var _showSource = false;

  _DiagramParseResult _parse() {
    final cacheKey = '${widget.language.name}\u0000${widget.source}';
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }
    final result = _DiagramParser.parse(widget.language, widget.source);
    _cache[cacheKey] = result;
    if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final result = _parse();
    final model = result.model;
    if (model == null) {
      return Container(
        key: ValueKey('diagram-error-${widget.language.name}'),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagram could not be rendered',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 3),
            Text(result.error ?? 'Unsupported diagram source.'),
            TextButton(
              key: ValueKey('diagram-show-source-${widget.language.name}'),
              onPressed: () => setState(() => _showSource = !_showSource),
              child: Text(_showSource ? 'Hide source' : 'Show source'),
            ),
            if (_showSource)
              SelectableText(
                widget.source,
                key: ValueKey('diagram-source-${widget.language.name}'),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
          ],
        ),
      );
    }
    return Semantics(
      label: '${widget.language.name} diagram',
      child: _DiagramCanvas(
        key: ValueKey('markdown-diagram-${widget.language.name}'),
        model: model,
      ),
    );
  }
}

class _DiagramParser {
  static const _maxSourceCharacters = 64 * 1024;
  static const _maxLines = 300;
  static const _maxNodes = 80;
  static const _maxRelations = 160;
  static const _maxLabelCharacters = 160;

  static _DiagramParseResult parse(
    MarkdownDiagramLanguage language,
    String source,
  ) {
    if (source.length > _maxSourceCharacters) {
      return const _DiagramParseResult.error('Diagram source is too large.');
    }
    final lines = source.split('\n');
    if (lines.length > _maxLines) {
      return const _DiagramParseResult.error('Diagram has too many lines.');
    }
    final unsafe = _unsafeReason(source);
    if (unsafe != null) return _DiagramParseResult.error(unsafe);
    return switch (language) {
      MarkdownDiagramLanguage.mermaid => _mermaid(lines),
      MarkdownDiagramLanguage.plantUml => _plantUml(lines),
    };
  }

  static String? _unsafeReason(String source) {
    final normalized = source.toLowerCase();
    const rejectedFragments = [
      '!include',
      '!import',
      '!pragma',
      'javascript:',
      'file:',
      'http://',
      'https://',
      '../',
      '..\\',
      '%2e%2e',
      '<script',
      '<iframe',
      '<object',
      '<embed',
    ];
    for (final fragment in rejectedFragments) {
      if (normalized.contains(fragment)) {
        return 'Unsafe external or executable diagram directive was blocked.';
      }
    }
    if (RegExp(
      r'^\s*(click|href|link)\b',
      multiLine: true,
    ).hasMatch(normalized)) {
      return 'Interactive diagram links are not supported.';
    }
    if (normalized.contains('%%{')) {
      return 'Mermaid initialization directives are not supported.';
    }
    return null;
  }

  static _DiagramParseResult _mermaid(List<String> lines) {
    final content = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('%%'))
        .toList();
    if (content.isEmpty) {
      return const _DiagramParseResult.error('Diagram source is empty.');
    }
    final header = content.first.toLowerCase();
    if (header.startsWith('flowchart ') || header.startsWith('graph ')) {
      final direction = header.split(RegExp(r'\s+')).last.toUpperCase();
      return _flow(content.skip(1), direction: direction);
    }
    if (header == 'sequencediagram') {
      return _sequence(content.skip(1));
    }
    return const _DiagramParseResult.error(
      'Only Mermaid flowchart and sequenceDiagram are supported locally.',
    );
  }

  static _DiagramParseResult _plantUml(List<String> lines) {
    final content = lines.map((line) => line.trim()).toList();
    final start = content.indexWhere(
      (line) => line.toLowerCase().startsWith('@startuml'),
    );
    final end = content.lastIndexWhere(
      (line) => line.toLowerCase() == '@enduml',
    );
    if (start < 0 || end <= start) {
      return const _DiagramParseResult.error(
        'PlantUML must contain @startuml and @enduml.',
      );
    }
    final body = content
        .sublist(start + 1, end)
        .where((line) => line.isNotEmpty && !line.startsWith("'"))
        .toList();
    if (body.any(
      (line) => RegExp(
        r'^(participant|actor|boundary|control|entity|database)\b',
        caseSensitive: false,
      ).hasMatch(line),
    )) {
      return _sequence(body);
    }
    return _flow(body, direction: 'TD', plantUml: true);
  }

  static _DiagramParseResult _flow(
    Iterable<String> lines, {
    required String direction,
    bool plantUml = false,
  }) {
    final nodes = <String, String>{};
    final edges = <_DiagramEdge>[];
    final arrow = plantUml
        ? RegExp(r'\s*(?:-+>|\.\.+>|==+>)\s*')
        : RegExp(r'\s*(?:--+>|-\.->|==+>|--+>>)\s*');
    for (final raw in lines) {
      final line = raw.split("'").first.trim();
      if (line.isEmpty || !arrow.hasMatch(line)) continue;
      final parts = line.split(arrow);
      if (parts.length < 2) continue;
      final parsed = parts.map(_node).toList();
      if (parsed.any((node) => node == null)) continue;
      for (final node in parsed.cast<_DiagramNodeToken>()) {
        nodes[node.id] = node.label;
      }
      for (var index = 0; index < parsed.length - 1; index++) {
        edges.add(_DiagramEdge(parsed[index]!.id, parsed[index + 1]!.id, ''));
      }
      if (nodes.length > _maxNodes || edges.length > _maxRelations) {
        return const _DiagramParseResult.error(
          'Diagram exceeds the local rendering limits.',
        );
      }
    }
    if (nodes.isEmpty || edges.isEmpty) {
      return const _DiagramParseResult.error(
        'No supported flowchart relationships were found.',
      );
    }
    return _DiagramParseResult.success(
      _DiagramModel.flow(
        nodes.entries
            .map((entry) => _DiagramNode(entry.key, entry.value))
            .toList(growable: false),
        edges,
        horizontal: direction == 'LR' || direction == 'RL',
      ),
    );
  }

  static _DiagramNodeToken? _node(String raw) {
    var value = raw.trim().replaceAll(RegExp(r'^\|[^|]*\|'), '').trim();
    final match = RegExp(r'^([A-Za-z_][A-Za-z0-9_.-]*)').firstMatch(value);
    if (match == null) return null;
    final id = match.group(1)!;
    value = value.substring(match.end).trim();
    var label = id;
    if (value.isNotEmpty) {
      label = value
          .replaceAll(RegExp(r'^[\[({]+'), '')
          .replaceAll(RegExp(r'[\])}]+$'), '')
          .trim();
      if (label.isEmpty) label = id;
    }
    if (label.length > _maxLabelCharacters) {
      label = '${label.substring(0, _maxLabelCharacters)}…';
    }
    return _DiagramNodeToken(id, label);
  }

  static _DiagramParseResult _sequence(Iterable<String> lines) {
    final participants = <String, String>{};
    final messages = <_DiagramEdge>[];
    final declaration = RegExp(
      r'^(?:participant|actor|boundary|control|entity|database)\s+([A-Za-z_][A-Za-z0-9_.-]*)(?:\s+as\s+(.+))?$',
      caseSensitive: false,
    );
    final message = RegExp(
      r'^([A-Za-z_][A-Za-z0-9_.-]*)\s*(?:--?>>?|<<?--?)\s*([A-Za-z_][A-Za-z0-9_.-]*)\s*:\s*(.+)$',
    );
    for (final raw in lines) {
      final line = raw.trim();
      final declared = declaration.firstMatch(line);
      if (declared != null) {
        participants[declared.group(1)!] =
            declared.group(2)?.trim() ?? declared.group(1)!;
        continue;
      }
      final sent = message.firstMatch(line);
      if (sent == null) continue;
      final from = sent.group(1)!;
      final to = sent.group(2)!;
      var label = sent.group(3)!.trim();
      if (label.length > _maxLabelCharacters) {
        label = '${label.substring(0, _maxLabelCharacters)}…';
      }
      participants.putIfAbsent(from, () => from);
      participants.putIfAbsent(to, () => to);
      messages.add(_DiagramEdge(from, to, label));
      if (participants.length > _maxNodes || messages.length > _maxRelations) {
        return const _DiagramParseResult.error(
          'Diagram exceeds the local rendering limits.',
        );
      }
    }
    if (participants.length < 2 || messages.isEmpty) {
      return const _DiagramParseResult.error(
        'No supported sequence messages were found.',
      );
    }
    return _DiagramParseResult.success(
      _DiagramModel.sequence(
        participants.entries
            .map((entry) => _DiagramNode(entry.key, entry.value))
            .toList(growable: false),
        messages,
      ),
    );
  }
}

class _DiagramCanvas extends StatelessWidget {
  const _DiagramCanvas({super.key, required this.model});
  final _DiagramModel model;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 900.0;
      final width = model.sequence || model.horizontal
          ? math.max(available, model.nodes.length * 180.0)
          : available;
      final height = model.sequence
          ? math.max(250.0, 120 + model.edges.length * 62.0)
          : model.horizontal
          ? 230.0
          : math.max(250.0, model.nodes.length * 84.0);
      final scheme = Theme.of(context).colorScheme;
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              painter: _DiagramPainter(
                model,
                background: scheme.surfaceContainerLow,
                foreground: scheme.onSurface,
                accent: scheme.primary,
                nodeFill: scheme.secondaryContainer,
                outline: scheme.outline,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _DiagramPainter extends CustomPainter {
  _DiagramPainter(
    this.model, {
    required this.background,
    required this.foreground,
    required this.accent,
    required this.nodeFill,
    required this.outline,
  });

  final _DiagramModel model;
  final Color background, foreground, accent, nodeFill, outline;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(background, BlendMode.src);
    if (model.sequence) {
      _paintSequence(canvas, size);
    } else {
      _paintFlow(canvas, size);
    }
  }

  void _paintFlow(Canvas canvas, Size size) {
    const nodeWidth = 148.0;
    const nodeHeight = 52.0;
    final positions = <String, Offset>{};
    for (var index = 0; index < model.nodes.length; index++) {
      final center = model.horizontal
          ? Offset(90 + index * 180, size.height / 2)
          : Offset(size.width / 2, 48 + index * 84);
      positions[model.nodes[index].id] = center;
    }
    final line = Paint()
      ..color = accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final edge in model.edges) {
      final from = positions[edge.from];
      final to = positions[edge.to];
      if (from == null || to == null) continue;
      final start = model.horizontal
          ? Offset(from.dx + nodeWidth / 2, from.dy)
          : Offset(from.dx, from.dy + nodeHeight / 2);
      final end = model.horizontal
          ? Offset(to.dx - nodeWidth / 2, to.dy)
          : Offset(to.dx, to.dy - nodeHeight / 2);
      canvas.drawLine(start, end, line);
      _arrow(canvas, start, end, line);
    }
    for (final node in model.nodes) {
      final center = positions[node.id]!;
      final rect = Rect.fromCenter(
        center: center,
        width: nodeWidth,
        height: nodeHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(9)),
        Paint()..color = nodeFill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(9)),
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke,
      );
      _text(canvas, node.label, rect.deflate(7), bold: true);
    }
  }

  void _paintSequence(Canvas canvas, Size size) {
    final centers = <String, double>{};
    for (var index = 0; index < model.nodes.length; index++) {
      centers[model.nodes[index].id] = 90 + index * 180;
    }
    final lifeline = Paint()
      ..color = outline
      ..strokeWidth = 1;
    for (final node in model.nodes) {
      final x = centers[node.id]!;
      final rect = Rect.fromCenter(
        center: Offset(x, 34),
        width: 148,
        height: 42,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = nodeFill,
      );
      canvas.drawLine(Offset(x, 56), Offset(x, size.height - 18), lifeline);
      _text(canvas, node.label, rect.deflate(5), bold: true);
    }
    final arrow = Paint()
      ..color = accent
      ..strokeWidth = 2;
    for (var index = 0; index < model.edges.length; index++) {
      final edge = model.edges[index];
      final start = Offset(centers[edge.from]!, 94 + index * 62);
      final end = Offset(centers[edge.to]!, start.dy);
      canvas.drawLine(start, end, arrow);
      _arrow(canvas, start, end, arrow);
      final left = math.min(start.dx, end.dx) + 5;
      final right = math.max(start.dx, end.dx) - 5;
      _text(
        canvas,
        edge.label,
        Rect.fromLTRB(
          left,
          start.dy - 28,
          math.max(left + 60, right),
          start.dy,
        ),
      );
    }
  }

  void _text(Canvas canvas, String value, Rect bounds, {bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: math.max(1, bounds.width));
    painter.paint(
      canvas,
      Offset(
        bounds.left + (bounds.width - painter.width) / 2,
        bounds.top + (bounds.height - painter.height) / 2,
      ),
    );
  }

  void _arrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    const length = 9.0;
    canvas.drawLine(
      end,
      Offset(
        end.dx - length * math.cos(angle - math.pi / 6),
        end.dy - length * math.sin(angle - math.pi / 6),
      ),
      paint,
    );
    canvas.drawLine(
      end,
      Offset(
        end.dx - length * math.cos(angle + math.pi / 6),
        end.dy - length * math.sin(angle + math.pi / 6),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DiagramPainter oldDelegate) =>
      oldDelegate.model != model ||
      oldDelegate.foreground != foreground ||
      oldDelegate.accent != accent ||
      oldDelegate.nodeFill != nodeFill;
}

class _DiagramParseResult {
  const _DiagramParseResult.success(this.model) : error = null;
  const _DiagramParseResult.error(this.error) : model = null;
  final _DiagramModel? model;
  final String? error;
}

class _DiagramModel {
  const _DiagramModel._(
    this.nodes,
    this.edges, {
    required this.horizontal,
    required this.sequence,
  });
  factory _DiagramModel.flow(
    List<_DiagramNode> nodes,
    List<_DiagramEdge> edges, {
    required bool horizontal,
  }) => _DiagramModel._(nodes, edges, horizontal: horizontal, sequence: false);
  factory _DiagramModel.sequence(
    List<_DiagramNode> nodes,
    List<_DiagramEdge> edges,
  ) => _DiagramModel._(nodes, edges, horizontal: true, sequence: true);
  final List<_DiagramNode> nodes;
  final List<_DiagramEdge> edges;
  final bool horizontal, sequence;
}

class _DiagramNode {
  const _DiagramNode(this.id, this.label);
  final String id, label;
}

class _DiagramNodeToken {
  const _DiagramNodeToken(this.id, this.label);
  final String id, label;
}

class _DiagramEdge {
  const _DiagramEdge(this.from, this.to, this.label);
  final String from, to, label;
}
