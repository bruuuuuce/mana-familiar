import 'package:flutter/material.dart';

import '../application/mana_inspect.dart';
import '../source_workspace.dart';

/// Shared, read-only source evidence surface. Reverse links are always from
/// Mana inspect source relations, never from a local `.mana` scan.
class SourceReferenceView extends StatefulWidget {
  const SourceReferenceView({
    super.key,
    required this.location,
    required this.sourceLoader,
    required this.onOpenArtifact,
    this.onOpenExternal,
  });
  final SourceLocation location;
  final Future<ManaInspectSourceRelations> Function(String path) sourceLoader;
  final ValueChanged<String> onOpenArtifact;
  final Future<void> Function(SourceLocation location)? onOpenExternal;
  @override
  State<SourceReferenceView> createState() => _SourceReferenceViewState();
}

class _SourceReferenceViewState extends State<SourceReferenceView> {
  late final Future<_SourceData> _data = _load();
  Future<_SourceData> _load() async {
    final resolved = await SourceResolver().resolve(widget.location);
    try {
      return _SourceData(
        resolved,
        await widget.sourceLoader(widget.location.path),
      );
    } catch (error) {
      return _SourceData(resolved, null, error);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_SourceData>(
    future: _data,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (data == null) {
        return const ListTile(title: Text('Loading source reference…'));
      }
      final relations =
          data.relations?.relations ?? const <Map<String, dynamic>>[];
      return Card(
        child: ExpansionTile(
          title: Text(widget.location.reference),
          subtitle: Text(
            '${data.resolved.status}${data.relations == null ? ' • reverse lookup unavailable' : ''}',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Recorded revision: ${widget.location.revision ?? 'unknown'}\n'
                'Comparability: ${data.resolved.drifted ? 'changed/drifted' : data.resolved.state.name}',
              ),
            ),
            if (widget.onOpenExternal != null)
              TextButton.icon(
                onPressed: () => widget.onOpenExternal!(widget.location),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in configured editor'),
              ),
            if (relations.isNotEmpty)
              const ListTile(title: Text('Related artifacts (Mana inspect)')),
            ...relations.take(20).map((relation) {
              final id = relation['artifact_id']?.toString();
              return ListTile(
                title: Text(id ?? 'Unknown related artifact'),
                subtitle: Text(
                  relation['relation_type']?.toString() ?? 'explicit relation',
                ),
                onTap: id == null ? null : () => widget.onOpenArtifact(id),
              );
            }),
          ],
        ),
      );
    },
  );
}

class _SourceData {
  const _SourceData(this.resolved, this.relations, [this.error]);
  final ResolvedSource resolved;
  final ManaInspectSourceRelations? relations;
  final Object? error;
}
