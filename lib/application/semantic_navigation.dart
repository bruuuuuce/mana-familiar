import 'mana_inspect.dart';

/// The complete semantic location in the Observatory. It contains no inferred
/// path/category information: every optional part comes from a Mana response
/// or an explicit user selection.
enum ObservatoryDestination {
  overview,
  work,
  reviews,
  knowledge,
  activity,
  advanced,
}

class ObservatoryRoute {
  const ObservatoryRoute({
    required this.destination,
    this.workItemId,
    this.section,
    this.category,
    this.artifactId,
  });
  final ObservatoryDestination destination;
  final String? workItemId, category, artifactId;
  final ManaSectionId? section;

  ObservatoryRoute copyWith({
    String? workItemId,
    ManaSectionId? section,
    String? category,
    String? artifactId,
    bool clearWorkItem = false,
    bool clearSection = false,
    bool clearCategory = false,
    bool clearArtifact = false,
  }) => ObservatoryRoute(
    destination: destination,
    workItemId: clearWorkItem ? null : workItemId ?? this.workItemId,
    section: clearSection ? null : section ?? this.section,
    category: clearCategory ? null : category ?? this.category,
    artifactId: clearArtifact ? null : artifactId ?? this.artifactId,
  );

  @override
  bool operator ==(Object other) =>
      other is ObservatoryRoute &&
      destination == other.destination &&
      workItemId == other.workItemId &&
      section == other.section &&
      category == other.category &&
      artifactId == other.artifactId;
  @override
  int get hashCode =>
      Object.hash(destination, workItemId, section, category, artifactId);
}

class ObservatoryNavigationState {
  ObservatoryNavigationState([
    this._current = const ObservatoryRoute(
      destination: ObservatoryDestination.overview,
    ),
  ]);
  ObservatoryRoute _current;
  final List<ObservatoryRoute> _back = [], _forward = [];
  ObservatoryRoute get current => _current;
  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;
  List<ObservatoryRoute> get backStack => List.unmodifiable(_back);
  List<ObservatoryRoute> get forwardStack => List.unmodifiable(_forward);
  bool navigate(ObservatoryRoute route) {
    if (route == _current) return false;
    _back.add(_current);
    _current = route;
    _forward.clear();
    return true;
  }

  ObservatoryRoute? back() {
    if (_back.isEmpty) return null;
    _forward.add(_current);
    return _current = _back.removeLast();
  }

  ObservatoryRoute? forward() {
    if (_forward.isEmpty) return null;
    _back.add(_current);
    return _current = _forward.removeLast();
  }

  void restore(ObservatoryRoute route) {
    _current = route;
    _back.clear();
    _forward.clear();
  }
}

List<String> observatoryBreadcrumbs(
  ObservatoryRoute route, {
  String projectLabel = 'Project',
  String? artifactLabel,
}) {
  final values = <String>[
    projectLabel,
    switch (route.destination) {
      ObservatoryDestination.overview => 'Overview',
      ObservatoryDestination.work => 'Work',
      ObservatoryDestination.reviews => 'Reviews',
      ObservatoryDestination.knowledge => 'Knowledge',
      ObservatoryDestination.activity => 'Activity',
      ObservatoryDestination.advanced => 'Advanced',
    },
  ];
  if (route.workItemId != null) values.add(route.workItemId!);
  if (route.section != null) values.add(_sectionLabel(route.section!));
  if (route.category != null) values.add(route.category!);
  if (route.artifactId != null) values.add(artifactLabel ?? route.artifactId!);
  return values;
}

String _sectionLabel(ManaSectionId section) => switch (section) {
  ManaSectionId.overview => 'Overview',
  ManaSectionId.requirements => 'Requirements',
  ManaSectionId.plan => 'Plan',
  ManaSectionId.decisions => 'Decisions',
  ManaSectionId.evidence => 'Evidence',
  ManaSectionId.review => 'Review',
  ManaSectionId.timeline => 'Timeline',
  ManaSectionId.artifacts => 'Artifacts',
};
