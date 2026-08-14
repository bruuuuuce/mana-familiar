import 'package:flutter/material.dart';

import '../application/mana_inspect.dart';

enum KnowledgeSection {
  journeys,
  concepts,
  architecture,
  rationale,
  history,
  candidates,
}

/// Hosts the established Journey explorer as one Knowledge subsection. Other
/// sections expose only catalogued Mana artifacts and never synthesize a KB.
/// Legacy catalog compatibility explorer. Semantic project context is rendered
/// by ProjectObservatoryPage and never calls this path/family classifier.
class KnowledgeModulePage extends StatefulWidget {
  const KnowledgeModulePage({
    super.key,
    required this.journeys,
    required this.artifacts,
    required this.onOpenArtifact,
    this.journeysBuilder,
  });
  final Widget journeys;
  final Widget Function(String? journeyId)? journeysBuilder;
  final List<ManaInspectArtifactSummary> artifacts;
  final ValueChanged<ManaInspectArtifactSummary> onOpenArtifact;

  @override
  State<KnowledgeModulePage> createState() => _KnowledgeModulePageState();
}

class _KnowledgeModulePageState extends State<KnowledgeModulePage> {
  var _section = KnowledgeSection.journeys;
  String? _requestedJourneyId;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      NavigationRail(
        selectedIndex: _section.index,
        labelType: NavigationRailLabelType.all,
        onDestinationSelected: (index) =>
            setState(() => _section = KnowledgeSection.values[index]),
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.route_outlined),
            label: Text('Journeys'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.lightbulb_outline),
            label: Text('Concepts'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.account_tree_outlined),
            label: Text('Architecture'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: Text('Rationale'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.history_outlined),
            label: Text('History'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.school_outlined),
            label: Text('Candidates'),
          ),
        ],
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: _section == KnowledgeSection.journeys
            ? (widget.journeysBuilder?.call(_requestedJourneyId) ??
                  widget.journeys)
            : _catalogSection(context),
      ),
    ],
  );

  Widget _catalogSection(BuildContext context) {
    final selected = widget.artifacts
        .where((artifact) => _matches(artifact))
        .toList();
    final title = _section.name[0].toUpperCase() + _section.name.substring(1);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const Text(
          'Only producer-reported Mana artifacts are shown. Open an item to '
          'inspect its declared relations and source references.',
        ),
        const SizedBox(height: 12),
        if (selected.isEmpty)
          const Card(
            child: ListTile(
              title: Text(
                'No matching Knowledge artifacts were reported by Mana.',
              ),
            ),
          ),
        ...selected.map((artifact) {
          final journeyId = _journeyIdFor(artifact);
          return Card(
            child: ListTile(
              title: Text(artifact.id),
              subtitle: Text(
                '${artifact.family} • ${artifact.kind} • ${artifact.status}',
              ),
              trailing: journeyId == null
                  ? const Icon(Icons.chevron_right)
                  : TextButton.icon(
                      onPressed: () => _openJourney(journeyId),
                      icon: const Icon(Icons.route_outlined),
                      label: const Text('Journey'),
                    ),
              onTap: () => widget.onOpenArtifact(artifact),
            ),
          );
        }),
      ],
    );
  }

  bool _matches(ManaInspectArtifactSummary artifact) {
    final value = '${artifact.path} ${artifact.family} ${artifact.kind}'
        .toLowerCase();
    return switch (_section) {
      KnowledgeSection.concepts => value.contains('concept'),
      KnowledgeSection.architecture =>
        value.contains('diagram') || value.contains('architecture'),
      KnowledgeSection.rationale =>
        value.contains('rationale') ||
            value.contains('decision') ||
            value.contains('hypothesis') ||
            value.contains('explanation'),
      KnowledgeSection.history =>
        artifact.kind == 'journey_record' ||
            value.contains('history') ||
            value.contains('traversal'),
      KnowledgeSection.candidates =>
        artifact.family == 'learning' &&
            (artifact.status == 'candidate' || value.contains('candidate')),
      KnowledgeSection.journeys => artifact.kind == 'journey',
    };
  }

  String? _journeyIdFor(ManaInspectArtifactSummary artifact) {
    final match = RegExp(
      r'\.mana/learning/journeys/(jrn_[a-f0-9]{24})(?:/|$)',
    ).firstMatch(artifact.path);
    return match?.group(1);
  }

  void _openJourney(String journeyId) {
    setState(() {
      _requestedJourneyId = journeyId;
      _section = KnowledgeSection.journeys;
    });
  }
}
