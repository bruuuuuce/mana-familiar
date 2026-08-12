import 'package:flutter/material.dart';

import '../application/mana_inspect.dart';
import '../application/operational_model.dart';

class ActivityView extends StatefulWidget {
  const ActivityView({
    super.key,
    required this.artifacts,
    required this.onOpenArtifact,
  });
  final List<ManaInspectArtifactSummary> artifacts;
  final ValueChanged<ManaInspectArtifactSummary> onOpenArtifact;

  @override
  State<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends State<ActivityView> {
  String? _status;
  String? _profileOrFamily;
  String? _workspace;
  var _recentOnly = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.artifacts.map(OperationalActivity.fromArtifact).toList();
    final statuses = all.map((entry) => entry.status).toSet().toList()..sort();
    final profiles = <String>{
      ...all.map((entry) => entry.profile).whereType<String>(),
      ...all.map((entry) => entry.artifact.family),
    }.toList()..sort();
    final workspaces =
        all.map((entry) => entry.workspace).whereType<String>().toSet().toList()
          ..sort();
    final entries = ActivityFilters(
      status: _status,
      profileOrFamily: _profileOrFamily,
      workspace: _workspace,
      recentOnly: _recentOnly,
    ).apply(widget.artifacts);
    final groups = <String, List<OperationalActivity>>{};
    for (final entry in entries) {
      groups.putIfAbsent(entry.runIdentity, () => []).add(entry);
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Activity', style: Theme.of(context).textTheme.headlineSmall),
        const Text('Mana-reported operational timeline; no synthetic events.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _choice(
              'Status',
              _status,
              statuses,
              (value) => setState(() => _status = value),
            ),
            _choice(
              'Profile or family',
              _profileOrFamily,
              profiles,
              (value) => setState(() => _profileOrFamily = value),
            ),
            _choice(
              'Workspace',
              _workspace,
              workspaces,
              (value) => setState(() => _workspace = value),
            ),
            FilterChip(
              label: const Text('Timestamp known'),
              selected: _recentOnly,
              onSelected: (value) => setState(() => _recentOnly = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (entries.isEmpty)
          const Card(
            child: ListTile(title: Text('No activity matches these filters.')),
          ),
        ...groups.entries.expand(
          (group) => [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                'Run/session: ${group.key}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...group.value.map(_entry),
          ],
        ),
      ],
    );
  }

  Widget _choice(
    String label,
    String? selected,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) => DropdownButton<String?>(
    value: selected,
    hint: Text(label),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('Any')),
      ...values.map(
        (value) => DropdownMenuItem<String?>(value: value, child: Text(value)),
      ),
    ],
    onChanged: onChanged,
  );

  Widget _entry(OperationalActivity entry) => Card(
    child: ListTile(
      leading: Icon(
        entry.partial ? Icons.warning_amber_outlined : Icons.bolt_outlined,
      ),
      title: Text(entry.artifact.id),
      subtitle: Text(
        '${entry.summary}\n'
        '${entry.timestamp ?? 'Timestamp unknown'} (${entry.timestampProvenance})\n'
        '${entry.profile ?? 'Producer/profile unknown'} • ${entry.status}'
        '${entry.workspace == null ? '' : ' • ${entry.workspace}'}'
        '${entry.partial ? '\nPartial or unknown metadata' : ''}',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => widget.onOpenArtifact(entry.artifact),
    ),
  );
}
