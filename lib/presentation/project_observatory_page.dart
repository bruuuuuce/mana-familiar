// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';

import '../application/mana_inspect.dart';
import '../application/observatory_model.dart';
import '../application/semantic_navigation.dart';
import 'artifact_detail_view.dart';
import 'review_inbox_page.dart';

/// F11 semantic navigation shell. Content remains intentionally lightweight;
/// later phases own the cockpit, reader, and dossier presentations.
class ProjectObservatoryPage extends StatefulWidget {
  const ProjectObservatoryPage({
    super.key,
    required this.client,
    required this.knowledge,
    this.knowledgeBuilder,
    this.initialProject,
    this.initialCatalog,
    this.initialReadModel,
    this.initialRoute,
    this.recentProjectRoots = const [],
    this.onOpenProject,
    this.artifactDetailLoader,
  });
  final ManaInspectClient client;
  final Widget knowledge;
  final Widget Function(String? journeyId)? knowledgeBuilder;
  final ManaInspectProject? initialProject;
  final ManaInspectCatalog? initialCatalog;
  final ManaSemanticReadModel? initialReadModel;
  final ObservatoryRoute? initialRoute;
  final List<String> recentProjectRoots;
  final Future<void> Function(String projectRoot)? onOpenProject;
  final Future<ManaInspectArtifactDetail> Function(String artifactId)?
  artifactDetailLoader;
  @override
  State<ProjectObservatoryPage> createState() => _ProjectObservatoryPageState();
}

class _ProjectObservatoryPageState extends State<ProjectObservatoryPage> {
  late final ManaSemanticRepository _repository = ManaSemanticRepository(
    widget.client,
  );
  late final ObservatoryNavigationState _navigation =
      ObservatoryNavigationState(
        widget.initialRoute ??
            const ObservatoryRoute(
              destination: ObservatoryDestination.overview,
            ),
      );
  ManaSemanticReadModel? _model;
  Object? _error;
  var _loading = true;
  ManaInspectArtifactDetail? _detail;
  Object? _detailError;
  var _detailLoading = false;
  int _detailRequest = 0;
  final Map<String, ManaInspectArtifactDetail> _detailCache = {};
  final Map<String, ManaWorkItemResponse> _workDetails = {};

  @override
  void initState() {
    super.initState();
    _model = widget.initialReadModel ?? _legacyModel();
    _loading = _model == null;
    if (_loading) _load();
  }

  ManaSemanticReadModel? _legacyModel() => widget.initialCatalog == null
      ? null
      : ManaSemanticReadModel(
          project:
              widget.initialProject ??
              ManaInspectProject.fromJson({
                'schema': inspectProjectSchema,
                'project_id': 'Saved inspect snapshot',
                'framework': const {},
                'mana': const {'present': true},
                'operations': const [],
              }),
          mode:
              widget.initialProject?.semanticMode ??
              ManaSemanticMode.legacyCatalog,
          catalog: widget.initialCatalog,
        );
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final model = await _repository.refresh();
      if (mounted)
        setState(() {
          _model = model;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e;
          _loading = false;
        });
    }
  }

  void _navigate(ObservatoryRoute route) {
    if (_navigation.navigate(route))
      setState(() {
        _detail = null;
        _detailError = null;
      });
    _loadDetailIfNeeded();
    _loadWorkDetailIfNeeded();
  }

  void _back() {
    if (_navigation.back() != null)
      setState(() {
        _detail = null;
        _detailError = null;
      });
    _loadDetailIfNeeded();
    _loadWorkDetailIfNeeded();
  }

  void _forward() {
    if (_navigation.forward() != null)
      setState(() {
        _detail = null;
        _detailError = null;
      });
    _loadDetailIfNeeded();
    _loadWorkDetailIfNeeded();
  }

  void _loadWorkDetailIfNeeded() {
    final model = _model;
    final id = _navigation.current.workItemId;
    if (model == null ||
        id == null ||
        _workDetails.containsKey(id) ||
        model.mode == ManaSemanticMode.legacyCatalog)
      return;
    _repository
        .workItem(id, model.project)
        .then((detail) {
          if (mounted) setState(() => _workDetails[id] = detail);
        })
        .catchError((_) {});
  }

  ManaInspectArtifactSummary? _artifact(
    ManaSemanticReadModel model,
    String id,
  ) {
    for (final artifact
        in model.catalog?.artifacts ?? const <ManaInspectArtifactSummary>[]) {
      if (artifact.id == id) return artifact;
    }
    for (final work
        in model.workItems?.workItems ?? const <ManaWorkItemSummary>[]) {
      for (final ref in work.artifacts) {
        if (ref.id == id) return _summary(ref);
      }
    }
    return null;
  }

  ManaInspectArtifactSummary _summary(ManaArtifactReference ref) =>
      ManaInspectArtifactSummary(
        id: ref.id,
        path: ref.path,
        family: 'semantic',
        kind: ref.kind,
        status: ref.status,
        raw: const {},
      );
  void _openArtifact(
    ManaInspectArtifactSummary artifact, {
    String? workItemId,
    ManaSectionId? section,
    String? category,
  }) => _navigate(
    ObservatoryRoute(
      destination: _navigation.current.destination,
      workItemId: workItemId ?? _navigation.current.workItemId,
      section: section ?? _navigation.current.section,
      category: category ?? _navigation.current.category,
      artifactId: artifact.id,
    ),
  );
  void _loadDetailIfNeeded() {
    final model = _model;
    final id = _navigation.current.artifactId;
    if (model == null || id == null) return;
    final artifact = _artifact(model, id);
    if (artifact == null) return;
    final cached = _detailCache[id];
    if (cached != null) {
      setState(() {
        _detail = cached;
        _detailLoading = false;
      });
      return;
    }
    final request = ++_detailRequest;
    setState(() => _detailLoading = true);
    (widget.artifactDetailLoader ?? widget.client.artifact)(id)
        .then((value) {
          if (mounted && request == _detailRequest)
            setState(() {
              _detail = value;
              _detailLoading = false;
              _detailCache[id] = value;
            });
        })
        .catchError((Object e) {
          if (mounted && request == _detailRequest)
            setState(() {
              _detailError = e;
              _detailLoading = false;
            });
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null || _model == null) return _errorState();
    final model = _model!;
    final route = _navigation.current;
    final artifact = route.artifactId == null
        ? null
        : _artifact(model, route.artifactId!);
    return Scaffold(
      appBar: AppBar(
        title: Text(model.project.projectId),
        actions: [
          IconButton(
            onPressed: _navigation.canGoBack ? _back : null,
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
          ),
          IconButton(
            onPressed: _navigation.canGoForward ? _forward : null,
            icon: const Icon(Icons.arrow_forward),
            tooltip: 'Forward',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: route.destination.index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => _navigate(
              ObservatoryRoute(destination: ObservatoryDestination.values[i]),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                label: Text('Overview'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.work_outline),
                label: Text('Work'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.rate_review_outlined),
                label: Text('Reviews'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.school_outlined),
                label: Text('Knowledge'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.bolt_outlined),
                label: Text('Activity'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.tune_outlined),
                label: Text('Advanced'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _breadcrumbs(route, artifact),
                Expanded(
                  child: artifact == null
                      ? _routeBody(model, route)
                      : ArtifactDetailView(
                          artifact: artifact,
                          detail: _detail,
                          loading: _detailLoading,
                          error: _detailError,
                          onOpenRelatedArtifact: (id) {
                            final related = _artifact(model, id);
                            if (related != null) _openArtifact(related);
                          },
                          sourceLoader: widget.client.source,
                          projectRoot: widget.client.projectRoot,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumbs(
    ObservatoryRoute route,
    ManaInspectArtifactSummary? artifact,
  ) => Padding(
    padding: const EdgeInsets.all(12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        observatoryBreadcrumbs(
          route,
          projectLabel: 'Project',
          artifactLabel: artifact?.id,
        ).join(' > '),
        key: const Key('semantic-breadcrumbs'),
      ),
    ),
  );
  Widget _routeBody(ManaSemanticReadModel model, ObservatoryRoute route) =>
      switch (route.destination) {
        ObservatoryDestination.overview => _overview(model),
        ObservatoryDestination.work => _work(model, route),
        ObservatoryDestination.reviews => _reviews(model),
        ObservatoryDestination.knowledge => _knowledge(model),
        ObservatoryDestination.activity => _activity(model),
        ObservatoryDestination.advanced => _advanced(model),
      };
  Widget _placeholder(String title, String text) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(text),
    ],
  );
  Widget _overview(ManaSemanticReadModel model) {
    final catalog = model.catalog;
    if (catalog == null)
      return _placeholder('Project overview', 'Semantic project overview.');
    final legacy = ObservatoryOverview.fromCatalog(catalog);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Project overview',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (model.mode == ManaSemanticMode.legacyCatalog)
          const Text('Legacy catalog compatibility mode.'),
        if (catalog.partial)
          const Card(child: ListTile(title: Text('Partial catalog'))),
        if (catalog.artifacts.isEmpty)
          const Card(child: ListTile(title: Text('Empty project catalog'))),
        const SizedBox(height: 16),
        Text(
          'Needs human attention',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        ...legacy.attention.map(
          (item) => ListTile(
            title: Text(item.artifact.id),
            onTap: () => _openArtifact(item.artifact),
          ),
        ),
        if (legacy.lastMeaningfulActivity != null)
          ListTile(
            title: const Text('Latest catalog activity'),
            subtitle: Text(legacy.lastMeaningfulActivity!.id),
            onTap: () => _openArtifact(legacy.lastMeaningfulActivity!),
          ),
      ],
    );
  }

  Widget _work(ManaSemanticReadModel model, ObservatoryRoute route) {
    if (model.mode == ManaSemanticMode.legacyCatalog)
      return _placeholder(
        'Work',
        'Work semantics are unavailable in legacy catalog mode.',
      );
    final work = model.workItems?.workItems ?? const <ManaWorkItemSummary>[];
    final selected = route.workItemId == null
        ? null
        : work.where((w) => w.id == route.workItemId).firstOrNull;
    if (selected == null)
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Work', style: Theme.of(context).textTheme.headlineSmall),
          ...work.map(
            (w) => ListTile(
              title: Text(w.id),
              subtitle: Text(w.lifecycle.state.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _navigate(
                ObservatoryRoute(
                  destination: ObservatoryDestination.work,
                  workItemId: w.id,
                ),
              ),
            ),
          ),
        ],
      );
    if (route.section == null)
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(selected.id, style: Theme.of(context).textTheme.headlineSmall),
          ...ManaSectionId.values.map(
            (section) => ListTile(
              title: Text(section.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _navigate(
                ObservatoryRoute(
                  destination: ObservatoryDestination.work,
                  workItemId: selected.id,
                  section: section,
                ),
              ),
            ),
          ),
        ],
      );
    final detail = _workDetails[selected.id];
    final refs = detail == null
        ? selected.artifacts.where((a) => a.sectionId == route.section).toList()
        : detail.sections
              .where((s) => s.id == route.section)
              .expand((s) => s.artifacts)
              .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          route.section!.name,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        ...refs.map((a) {
          final summary = _summary(a);
          return ListTile(
            title: Text(a.label ?? a.id),
            onTap: () => _openArtifact(
              summary,
              workItemId: selected.id,
              section: route.section,
            ),
          );
        }),
      ],
    );
  }

  Widget _reviews(ManaSemanticReadModel model) =>
      model.mode == ManaSemanticMode.legacyCatalog
      ? ReviewInboxPage(
          artifacts: model.catalog?.artifacts ?? const [],
          onOpenArtifact: (a) => _openArtifact(a),
        )
      : ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Reviews', style: Theme.of(context).textTheme.headlineSmall),
            ...[
              for (final work
                  in model.workItems?.workItems ??
                      const <ManaWorkItemSummary>[])
                ...work.attentionItems,
            ].map(
              (item) => ListTile(
                title: Text(item.label ?? item.id),
                subtitle: Text(item.category),
                onTap: () => _navigate(
                  ObservatoryRoute(
                    destination: ObservatoryDestination.reviews,
                    workItemId: item.workItemId,
                  ),
                ),
              ),
            ),
          ],
        );
  Widget _knowledge(ManaSemanticReadModel model) {
    if (model.mode == ManaSemanticMode.legacyCatalog) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Knowledge', style: Theme.of(context).textTheme.headlineSmall),
          Text('Journeys', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Legacy Journey navigation is retained separately from semantic project context.',
          ),
          const SizedBox(height: 12),
          widget.knowledge,
        ],
      );
    }
    if (model.mode != ManaSemanticMode.fullSemantic)
      return _placeholder(
        'Knowledge',
        'Project context is unavailable for this capability mode.',
      );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Knowledge', style: Theme.of(context).textTheme.headlineSmall),
        ...(model.projectContext?.categories ??
                const <ManaProjectContextCategory>[])
            .map(
              (c) => ListTile(
                title: Text(c.category),
                onTap: () => _navigate(
                  ObservatoryRoute(
                    destination: ObservatoryDestination.knowledge,
                    category: c.category,
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _activity(ManaSemanticReadModel model) {
    if (model.mode == ManaSemanticMode.legacyCatalog)
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Activity', style: Theme.of(context).textTheme.headlineSmall),
          const Text('Legacy catalog inventory; it is not semantic activity.'),
          const Text(
            'Mana-reported operational timeline; no synthetic events.',
          ),
          ...(model.catalog?.artifacts ?? const <ManaInspectArtifactSummary>[])
              .map(
                (a) =>
                    ListTile(title: Text(a.id), onTap: () => _openArtifact(a)),
              ),
        ],
      );
    if (model.mode != ManaSemanticMode.fullSemantic)
      return _placeholder(
        'Activity',
        'Semantic activity is unavailable for this capability mode.',
      );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Activity', style: Theme.of(context).textTheme.headlineSmall),
        ...(model.activity?.events ?? const <ManaActivityEvent>[]).map(
          (e) => ListTile(
            title: Text(e.summary ?? e.id),
            subtitle: Text(e.timestamp),
            onTap: () {
              final a = e.relatedArtifactIds.isEmpty
                  ? null
                  : _artifact(model, e.relatedArtifactIds.first);
              if (a != null) _openArtifact(a, workItemId: e.workItemId);
            },
          ),
        ),
      ],
    );
  }

  Widget _advanced(ManaSemanticReadModel model) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Advanced', style: Theme.of(context).textTheme.headlineSmall),
      const Text('Artifacts and diagnostics'),
      ...(model.catalog?.artifacts ?? const <ManaInspectArtifactSummary>[]).map(
        (a) => ListTile(title: Text(a.id), onTap: () => _openArtifact(a)),
      ),
    ],
  );
  Widget _errorState() => Scaffold(
    body: Center(
      child: FilledButton(onPressed: _load, child: const Text('Try again')),
    ),
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
