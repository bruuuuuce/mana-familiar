// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';

import 'package:flutter/material.dart';

import '../application/mana_inspect.dart';
import '../application/semantic_navigation.dart';
import '../application/mana_workspace_watcher.dart';
import 'artifact_detail_view.dart';
import 'review_inbox_page.dart';

/// Semantic navigation shell for the project observatory. Routes retain typed
/// work, context, activity, and document ownership through the presentation.
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
    this.watcher,
    this.onRefresh,
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
  final ManaWorkspaceWatcher? watcher;
  final Future<void> Function()? onRefresh;
  @override
  State<ProjectObservatoryPage> createState() => _ProjectObservatoryPageState();
}

class _ProjectObservatoryPageState extends State<ProjectObservatoryPage> {
  late final ManaSemanticRepository _repository = ManaSemanticRepository(
    widget.client,
  );
  late final ObservatoryNavigationState _navigation =
      ObservatoryNavigationState(
        _normalizeDossierRoute(
          widget.initialRoute ??
              const ObservatoryRoute(
                destination: ObservatoryDestination.overview,
              ),
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
  String _workFilter = 'all';
  String _workSearch = '';
  ManaActivityKind? _activityKindFilter;
  String? _activityWorkItemFilter;
  ManaTimestampProvenance? _activityTimeFilter;
  String? _advancedFamilyFilter;
  String? _advancedKindFilter;
  String? _advancedStatusFilter;
  late final ManaWorkspaceWatcher _watcher =
      widget.watcher ??
      ManaDirectoryWatcher(projectRoot: widget.client.projectRoot);
  StreamSubscription<ManaWorkspaceWatchEvent>? _watchSubscription;
  var _refreshPending = false;
  var _watchUnavailable = false;

  @override
  void initState() {
    super.initState();
    _model = widget.initialReadModel ?? _legacyModel();
    _loading = _model == null;
    if (_loading) _load();
    _watchSubscription = _watcher.events.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event) {
          case ManaWorkspaceWatchEvent.changed:
            _refreshPending = true;
          case ManaWorkspaceWatchEvent.unavailable:
            _watchUnavailable = true;
        }
      });
    });
    _watcher.start();
  }

  @override
  void dispose() {
    _watchSubscription?.cancel();
    _watcher.dispose();
    super.dispose();
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

  Future<void> _refresh() async {
    setState(() => _refreshPending = false);
    if (widget.onRefresh != null) {
      await widget.onRefresh!();
      return;
    }
    await _load();
  }

  static ObservatoryRoute _normalizeDossierRoute(ObservatoryRoute route) {
    if (route.destination != ObservatoryDestination.work ||
        route.workItemId == null ||
        route.section != null) {
      return route;
    }
    return ObservatoryRoute(
      destination: route.destination,
      workItemId: route.workItemId,
      section: ManaSectionId.overview,
      artifactId: route.artifactId,
      category: route.category,
      advancedSection: route.advancedSection,
    );
  }

  void _navigate(ObservatoryRoute route) {
    route = _normalizeDossierRoute(route);
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
    for (final category
        in model.projectContext?.categories ??
            const <ManaProjectContextCategory>[]) {
      for (final ref in category.artifacts) {
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
        raw: ref.label == null ? const {} : {'label': ref.label},
      );

  ManaArtifactReference? _reference(ManaSemanticReadModel model, String id) {
    for (final work
        in model.workItems?.workItems ?? const <ManaWorkItemSummary>[]) {
      for (final reference in work.artifacts) {
        if (reference.id == id) return reference;
      }
    }
    for (final category
        in model.projectContext?.categories ??
            const <ManaProjectContextCategory>[]) {
      for (final reference in category.artifacts) {
        if (reference.id == id) return reference;
      }
    }
    return null;
  }

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
      advancedSection: _navigation.current.advancedSection,
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
        title: _projectTitle(model.project),
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
            key: const Key('refresh-button'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            selectedIcon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.refresh),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    key: const Key('refresh-pending-indicator'),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            isSelected: _refreshPending,
            tooltip: _refreshPending ? 'Refresh — changes detected' : 'Refresh',
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
                _breadcrumbs(model, route, artifact),
                if (_watchUnavailable) _watchUnavailableWarning(),
                if (model.refreshError != null) _refreshWarning(),
                Expanded(
                  child: artifact == null
                      ? _routeBody(model, route)
                      : route.destination == ObservatoryDestination.work &&
                            route.workItemId != null
                      ? Column(
                          children: [
                            _dossierHeader(model, route.workItemId!),
                            _dossierNavigation(
                              route.workItemId!,
                              route.section ?? ManaSectionId.overview,
                            ),
                            Expanded(
                              child: ArtifactDetailView(
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
                                documentPresentation: true,
                                contextualTitle:
                                    _reference(model, artifact.id)?.label ??
                                    'Untitled document',
                              ),
                            ),
                          ],
                        )
                      : route.destination == ObservatoryDestination.knowledge
                      ? ArtifactDetailView(
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
                          documentPresentation: true,
                          contextualTitle:
                              _reference(model, artifact.id)?.label ??
                              'Untitled document',
                        )
                      : route.destination == ObservatoryDestination.advanced
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
                              child: Text(
                                'Advanced artifact detail',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Expanded(
                              child: ArtifactDetailView(
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
                        )
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
    ManaSemanticReadModel model,
    ObservatoryRoute route,
    ManaInspectArtifactSummary? artifact,
  ) {
    final labels = observatoryBreadcrumbs(
      route,
      projectLabel: 'Project',
      artifactLabel: artifact == null
          ? null
          : _reference(model, artifact.id)?.label ?? _artifactLabel(artifact),
    );
    final workItem = route.workItemId == null
        ? null
        : model.workItems?.workItems
              .where((item) => item.id == route.workItemId)
              .firstOrNull;
    if (workItem != null) {
      final index = labels.indexOf(route.workItemId!);
      if (index >= 0) labels[index] = _workPrimaryLabel(workItem);
    }
    final entries = _breadcrumbEntries(route, labels);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          key: const Key('semantic-breadcrumbs'),
          children: [
            for (var index = 0; index < entries.length; index++) ...[
              if (index > 0)
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Theme.of(context).colorScheme.outline,
                ),
              if (entries[index].route case final target?)
                TextButton(
                  key: ValueKey('breadcrumb-${entries[index].role}'),
                  onPressed: () => _navigate(target),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                  ),
                  child: Text(entries[index].label),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text(
                    entries[index].label,
                    key: ValueKey('breadcrumb-${entries[index].role}'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<_SemanticBreadcrumb> _breadcrumbEntries(
    ObservatoryRoute route,
    List<String> labels,
  ) {
    final entries = <_SemanticBreadcrumb>[
      const _SemanticBreadcrumb(
        role: 'project',
        label: 'Project',
        route: ObservatoryRoute(destination: ObservatoryDestination.overview),
      ),
    ];
    var labelIndex = 1;
    final hasDestinationChild =
        route.workItemId != null ||
        route.category != null ||
        route.advancedSection != null ||
        route.artifactId != null;
    entries.add(
      _SemanticBreadcrumb(
        role: 'destination',
        label: labels[labelIndex++],
        route: hasDestinationChild
            ? ObservatoryRoute(destination: route.destination)
            : null,
      ),
    );
    if (route.workItemId != null) {
      final hasChild = route.section != null || route.artifactId != null;
      entries.add(
        _SemanticBreadcrumb(
          role: 'work-item',
          label: labels[labelIndex++],
          route: hasChild
              ? ObservatoryRoute(
                  destination: ObservatoryDestination.work,
                  workItemId: route.workItemId,
                  section: ManaSectionId.overview,
                )
              : null,
        ),
      );
    }
    if (route.section != null) {
      entries.add(
        _SemanticBreadcrumb(
          role: 'section',
          label: labels[labelIndex++],
          route: route.artifactId != null
              ? ObservatoryRoute(
                  destination: ObservatoryDestination.work,
                  workItemId: route.workItemId,
                  section: route.section,
                )
              : null,
        ),
      );
    }
    if (route.category != null) {
      entries.add(
        _SemanticBreadcrumb(
          role: 'category',
          label: labels[labelIndex++],
          route: route.artifactId != null
              ? ObservatoryRoute(
                  destination: ObservatoryDestination.knowledge,
                  category: route.category,
                )
              : null,
        ),
      );
    }
    if (route.advancedSection != null) {
      entries.add(
        _SemanticBreadcrumb(
          role: 'advanced-section',
          label: labels[labelIndex++],
          route: route.artifactId != null
              ? ObservatoryRoute(
                  destination: ObservatoryDestination.advanced,
                  advancedSection: route.advancedSection,
                )
              : null,
        ),
      );
    }
    if (route.artifactId != null) {
      entries.add(
        _SemanticBreadcrumb(role: 'document', label: labels[labelIndex]),
      );
    }
    return entries;
  }

  Widget _refreshWarning() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    color: Theme.of(context).colorScheme.errorContainer,
    child: Row(
      children: [
        Icon(
          Icons.sync_problem_outlined,
          size: 18,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Refresh incomplete. Showing the last successful data.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _watchUnavailableWarning() => MaterialBanner(
    content: const Text(
      'Changes to .mana cannot be observed. Refresh remains available manually.',
    ),
    actions: const [SizedBox.shrink()],
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
    if (model.mode == ManaSemanticMode.legacyCatalog)
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Project overview',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'Semantic cockpit is unavailable in legacy catalog mode. Use Advanced for the catalog.',
          ),
          const Text('Needs human attention'),
          if (model.catalog?.artifacts.isEmpty ?? true)
            const Text('Empty project catalog'),
          if (model.catalog?.partial ?? false) const Text('Partial catalog'),
        ],
      );
    final work = model.workItems?.workItems ?? const <ManaWorkItemSummary>[];
    final attention = [for (final item in work) ...item.attentionItems]
      ..sort((a, b) => b.severity.compareTo(a.severity));
    final categories =
        model.projectContext?.categories ??
        const <ManaProjectContextCategory>[];
    final activity = model.activity?.events ?? const <ManaActivityEvent>[];
    final populatedCategories = categories
        .where((category) => category.artifacts.isNotEmpty)
        .toList();
    final contextPreview = populatedCategories.take(4).toList();
    final missingCategoryCount = categories.length - populatedCategories.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
      children: [
        _cockpitIdentity(model.project, work: work, attention: attention),
        const SizedBox(height: 30),
        if (attention.isEmpty)
          _healthyAttentionState()
        else
          _emphasisSurface(
            title: 'Needs attention',
            icon: Icons.priority_high_rounded,
            children: attention
                .map(
                  (a) => _quietRow(
                    leading: Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: a.label ?? a.id,
                    subtitle: _humanize(a.category),
                    trailing: _statusPill(a.severity),
                    onTap: () => _navigate(
                      ObservatoryRoute(
                        destination: ObservatoryDestination.work,
                        workItemId: a.workItemId,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 28),
        _sectionHeading('Active / relevant work'),
        const SizedBox(height: 10),
        if (work.isEmpty)
          const _ObservatoryEmptyState(
            icon: Icons.work_outline,
            title: 'No work reported yet',
            message:
                'Mana has not reported semantic work items for this project.',
          )
        else
          ...work
              .where(
                (w) =>
                    w.lifecycle.state != ManaLifecycleState.unknown ||
                    w.attentionItems.isNotEmpty ||
                    w.title.value != null,
              )
              .take(6)
              .map(_cockpitWorkRow),
        if (work.any((w) => w.review.state != ManaReviewState.unknown)) ...[
          const SizedBox(height: 28),
          _sectionHeading('Review summary'),
          ...work
              .where((w) => w.review.state != ManaReviewState.unknown)
              .map(
                (w) => _quietRow(
                  title: _workPrimaryLabel(w),
                  trailing: _statusPill(_humanize(w.review.state.name)),
                ),
              ),
        ],
        const SizedBox(height: 28),
        _sectionHeading('Project context'),
        const SizedBox(height: 8),
        if (model.mode == ManaSemanticMode.fullSemantic) ...[
          if (populatedCategories.isEmpty)
            const Text('No reusable project context has been reported yet.')
          else
            ...contextPreview.map(
              (c) => _quietRow(
                leading: const Icon(Icons.menu_book_outlined),
                title: _humanize(c.category),
                subtitle:
                    '${c.artifacts.length} document${c.artifacts.length == 1 ? '' : 's'} available',
                trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                onTap: () => _navigate(
                  ObservatoryRoute(
                    destination: ObservatoryDestination.knowledge,
                    category: c.category,
                  ),
                ),
              ),
            ),
          if (populatedCategories.length > contextPreview.length ||
              missingCategoryCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _navigate(
                  const ObservatoryRoute(
                    destination: ObservatoryDestination.knowledge,
                  ),
                ),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('View all project knowledge'),
              ),
            ),
        ] else
          const Text('Project context is unavailable in WORK_SEMANTIC mode.'),
        const SizedBox(height: 28),
        _sectionHeading('Recent activity'),
        const SizedBox(height: 8),
        if (model.mode == ManaSemanticMode.fullSemantic)
          if (activity.isEmpty)
            const Text('No recent project activity was reported.')
          else
            ...activity
                .take(8)
                .map(
                  (e) => _quietRow(
                    leading: Icon(_activityIcon(e.kind), size: 20),
                    title: _activityLabel(e),
                    subtitle: _readableTimestamp(
                      e.timestamp,
                      e.timestampProvenance,
                    ),
                    onTap: () => _navigate(
                      ObservatoryRoute(
                        destination: ObservatoryDestination.activity,
                        workItemId: e.workItemId,
                      ),
                    ),
                  ),
                )
        else
          const Text('Semantic activity is unavailable in WORK_SEMANTIC mode.'),
      ],
    );
  }

  Widget _cockpitIdentity(
    ManaInspectProject project, {
    required List<ManaWorkItemSummary> work,
    required List<ManaAttentionItem> attention,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: 64,
        height: 64,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Image.asset(
          'assets/branding/mana-familiar-logo.png',
          key: const Key('cockpit-brand-logo'),
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Project observatory',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 2),
            Text(
              'Mana Familiar • ${work.length} ${work.length == 1 ? 'work item' : 'work items'}${attention.isEmpty ? '' : ' • ${attention.length} need attention'}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _shortProjectIdentity(project.projectId),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _sectionHeading(String title) =>
      Text(title, style: Theme.of(context).textTheme.titleLarge);

  Widget _healthyAttentionState() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeading('Needs attention'),
      const SizedBox(height: 8),
      Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nothing needs attention',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Mana has not reported any issues requiring action.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );

  Widget _emphasisSurface({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.errorContainer.withValues(alpha: .45),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );

  Widget _quietRow({
    Widget? leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing],
          ],
        ),
      ),
    ),
  );

  Widget _cockpitWorkRow(ManaWorkItemSummary item) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _navigate(
        ObservatoryRoute(
          destination: ObservatoryDestination.work,
          workItemId: item.id,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _workTypeIcon(item.type),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _workPrimaryLabel(item),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_workSecondaryLabel(item) != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _workSecondaryLabel(item)!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _workStatus(item),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ),
  );

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
    if (selected == null) {
      final visible = work.where((w) {
        final search = '${w.id} ${w.title.value ?? ''} ${w.branch.value ?? ''}'
            .toLowerCase()
            .contains(_workSearch.toLowerCase());
        final filter =
            _workFilter == 'all' ||
            (_workFilter == 'attention' && w.attentionItems.isNotEmpty) ||
            (_workFilter == 'active' &&
                w.lifecycle.state == ManaLifecycleState.inProgress) ||
            (_workFilter == 'feature' && w.type == ManaWorkItemType.feature) ||
            (_workFilter == 'session' && w.type == ManaWorkItemType.session);
        return search && filter;
      });
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
        children: [
          Text('Work', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'A semantic queue of the work Mana knows about.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search work',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _workSearch = value),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: ['all', 'attention', 'active', 'feature', 'session']
                .map(
                  (f) => ChoiceChip(
                    label: Text(f),
                    selected: _workFilter == f,
                    onSelected: (_) => setState(() => _workFilter = f),
                  ),
                )
                .toList(),
          ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No work items match these controls.'),
            ),
          const SizedBox(height: 12),
          ...visible.map((w) => _workQueueRow(w)),
        ],
      );
    }
    final section = route.section ?? ManaSectionId.overview;
    final detail = _workDetails[selected.id];
    final refs = detail == null
        ? selected.artifacts.where((a) => a.sectionId == section).toList()
        : detail.sections
              .where((s) => s.id == section)
              .expand((s) => s.artifacts)
              .toList();
    final activity = (model.activity?.events ?? const <ManaActivityEvent>[])
        .where((event) => event.workItemId == selected.id)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
      children: [
        _dossierHeader(model, selected.id),
        _dossierNavigation(selected.id, section),
        const SizedBox(height: 26),
        Text(
          _sectionLabel(section),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        if (section == ManaSectionId.review)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              selected.review.state == ManaReviewState.unknown
                  ? 'Mana has not reported a review state for this work item.'
                  : 'Review state: ${_humanize(selected.review.state.name)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (section == ManaSectionId.timeline && activity.isNotEmpty)
          ..._timelineRows(model, activity),
        if (refs.isEmpty &&
            !(section == ManaSectionId.timeline && activity.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: _sectionEmptyState(section),
          ),
        const SizedBox(height: 8),
        ..._prioritized(section, refs).map((a) {
          final summary = _summary(a);
          return _artifactRow(
            a,
            onTap: () => _openArtifact(
              summary,
              workItemId: selected.id,
              section: section,
            ),
          );
        }),
      ],
    );
  }

  Widget _workQueueRow(ManaWorkItemSummary item) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _navigate(
          ObservatoryRoute(
            destination: ObservatoryDestination.work,
            workItemId: item.id,
          ),
        ),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _workTypeIcon(item.type),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _workPrimaryLabel(item),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_workSecondaryLabel(item) != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        _workSecondaryLabel(item)!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _humanize(item.type.name),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _workStatus(item),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _artifactRow(
    ManaArtifactReference artifact, {
    required VoidCallback onTap,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(_artifactIcon(artifact.kind)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                artifact.label ?? 'Untitled document',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (artifact.status != 'available')
              _statusPill(_humanize(artifact.status)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );

  List<Widget> _timelineRows(
    ManaSemanticReadModel model,
    List<ManaActivityEvent> events,
  ) => events
      .map((event) {
        final target = _activityTarget(model, event);
        return _quietRow(
          leading: const Icon(Icons.schedule_outlined),
          title: _activityLabel(event),
          subtitle: [
            _readableTimestamp(event.timestamp, event.timestampProvenance),
            if (event.target?.sectionId case final section?)
              _sectionLabel(section),
            if (event.timestampProvenance ==
                ManaTimestampProvenance.filesystemMtimeEpoch)
              'filesystem time',
          ].join(' · '),
          trailing: target == null ? null : const Icon(Icons.chevron_right),
          onTap: target == null ? null : () => _navigate(target),
        );
      })
      .toList(growable: false);

  static const _dossierSections = [
    ManaSectionId.overview,
    ManaSectionId.requirements,
    ManaSectionId.plan,
    ManaSectionId.decisions,
    ManaSectionId.evidence,
    ManaSectionId.review,
    ManaSectionId.timeline,
  ];
  List<ManaArtifactReference> _prioritized(
    ManaSectionId? section,
    List<ManaArtifactReference> refs,
  ) {
    if (section != ManaSectionId.evidence) return refs;
    const urgent = {'failed': 0, 'blocked': 1, 'stale': 2};
    return [
      ...refs,
    ]..sort((a, b) => (urgent[a.status] ?? 3).compareTo(urgent[b.status] ?? 3));
  }

  Widget _dossierHeader(ManaSemanticReadModel model, String id) {
    final item = model.workItems?.workItems
        .where((w) => w.id == id)
        .firstOrNull;
    if (item == null) return const SizedBox.shrink();
    final facts = <Widget>[
      _statusPill(_humanize(item.type.name)),
      if (item.lifecycle.state != ManaLifecycleState.unknown)
        _statusPill(_humanize(item.lifecycle.state.name)),
      if (item.review.state != ManaReviewState.unknown)
        _statusPill('Review ${_humanize(item.review.state.name)}'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _workPrimaryLabel(item),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (item.title.value != null &&
              item.title.value != _workPrimaryLabel(item)) ...[
            const SizedBox(height: 3),
            Text(
              item.title.value!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 7, runSpacing: 7, children: facts),
          if (item.branch.value != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Tooltip(
                message: item.branch.value!,
                child: Text(
                  'Branch · ${_compactTechnicalLabel(item.branch.value!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dossierNavigation(String id, ManaSectionId selected) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 2),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _dossierSections
            .map(
              (section) => _dossierTab(
                id: id,
                section: section,
                selected: section == selected,
              ),
            )
            .toList(),
      ),
    ),
  );

  Widget _dossierTab({
    required String id,
    required ManaSectionId section,
    required bool selected,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      onTap: () => _navigate(
        ObservatoryRoute(
          destination: ObservatoryDestination.work,
          workItemId: id,
          section: section,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(
                  context,
                ).colorScheme.secondaryContainer.withValues(alpha: .55)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              width: selected ? 3 : 1,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
            ),
          ),
        ),
        child: Text(
          _sectionLabel(section),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );

  Widget _reviews(ManaSemanticReadModel model) {
    if (model.mode == ManaSemanticMode.legacyCatalog) {
      return ReviewInboxPage(
        artifacts: model.catalog?.artifacts ?? const [],
        onOpenArtifact: (artifact) => _openArtifact(artifact),
      );
    }
    final work = model.workItems?.workItems ?? const <ManaWorkItemSummary>[];
    final reviewable = work.where(_hasStructuredReviewMaterial).toList();
    final attention = reviewable.where(
      (item) => item.attentionItems.isNotEmpty,
    );
    final known = reviewable.where(
      (item) =>
          item.attentionItems.isEmpty &&
          item.review.state != ManaReviewState.unknown,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
      children: [
        Text('Reviews', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Review state and attention reported by Mana, organized by work item.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (reviewable.isEmpty)
          const _ObservatoryEmptyState(
            icon: Icons.rate_review_outlined,
            title: 'No structured review information reported',
            message:
                'Mana has not reported review state, review material, or attention for the current work items.',
          )
        else ...[
          if (attention.isNotEmpty) ...[
            _sectionHeading('Needs attention'),
            const SizedBox(height: 8),
            ...attention.map(_reviewWorkRow),
            if (known.isNotEmpty) const SizedBox(height: 24),
          ],
          if (known.isNotEmpty) ...[
            _sectionHeading('Review status'),
            const SizedBox(height: 8),
            ...known.map(_reviewWorkRow),
          ],
          if (attention.isEmpty && known.isEmpty)
            const _ObservatoryEmptyState(
              icon: Icons.rate_review_outlined,
              title: 'No structured review information reported',
              message:
                  'Mana has not reported a known review state for the current work items.',
            ),
        ],
      ],
    );
  }

  bool _hasStructuredReviewMaterial(ManaWorkItemSummary item) =>
      item.review.state != ManaReviewState.unknown ||
      item.attentionItems.isNotEmpty ||
      item.artifacts.any(
        (artifact) => artifact.sectionId == ManaSectionId.review,
      );

  ManaSectionId _reviewTarget(ManaWorkItemSummary item) {
    for (final attention in item.attentionItems) {
      for (final id in attention.relatedArtifactIds) {
        final reference = item.artifacts
            .where((artifact) => artifact.id == id)
            .firstOrNull;
        if (reference?.sectionId case final section?
            when section == ManaSectionId.review ||
                section == ManaSectionId.decisions ||
                section == ManaSectionId.evidence) {
          return section;
        }
      }
    }
    if (item.artifacts.any(
          (artifact) => artifact.sectionId == ManaSectionId.review,
        ) ||
        item.review.state != ManaReviewState.unknown) {
      return ManaSectionId.review;
    }
    return ManaSectionId.overview;
  }

  Widget _reviewWorkRow(ManaWorkItemSummary item) {
    final target = _reviewTarget(item);
    final attention = item.attentionItems;
    final detail = attention.isEmpty
        ? 'Review ${_humanize(item.review.state.name)}'
        : '${attention.length} item${attention.length == 1 ? '' : 's'} needs attention';
    return _quietRow(
      leading: Icon(
        attention.isEmpty ? Icons.rate_review_outlined : Icons.priority_high,
        color: attention.isEmpty ? null : Theme.of(context).colorScheme.error,
      ),
      title: _workPrimaryLabel(item),
      subtitle: detail,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _navigate(
        ObservatoryRoute(
          destination: ObservatoryDestination.work,
          workItemId: item.id,
          section: target,
        ),
      ),
    );
  }

  Widget _knowledge(ManaSemanticReadModel model) {
    if (model.mode == ManaSemanticMode.legacyCatalog) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Limited catalog mode',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Legacy journeys',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Semantic project context is unavailable. Legacy Journey navigation is retained separately for catalog compatibility.',
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
    final categories =
        model.projectContext?.categories ??
        const <ManaProjectContextCategory>[];
    final selected = _navigation.current.category == null
        ? null
        : categories
              .where(
                (category) => category.category == _navigation.current.category,
              )
              .firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
      children: [
        Text('Knowledge', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Reusable project context reported by Mana.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 28),
          Text(
            _humanize(selected.category),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          if (selected.artifacts.isEmpty)
            const _ObservatoryEmptyState(
              icon: Icons.menu_book_outlined,
              title: 'No material reported yet',
              message:
                  'Mana reports this context category, but no document is currently available.',
            )
          else if (selected.artifacts.length == 1)
            _contextDocumentRow(
              selected.artifacts.single,
              onTap: () => _openArtifact(
                _summary(selected.artifacts.single),
                category: selected.category,
              ),
            )
          else
            ...selected.artifacts.map(
              (artifact) => _contextDocumentRow(
                artifact,
                onTap: () => _openArtifact(
                  _summary(artifact),
                  category: selected.category,
                ),
              ),
            ),
          const SizedBox(height: 22),
          const Divider(),
        ],
        const SizedBox(height: 14),
        ...categories
            .where((category) => category.artifacts.isNotEmpty)
            .map(_knowledgeCategoryRow),
        if (categories.any((category) => category.artifacts.isEmpty)) ...[
          const SizedBox(height: 18),
          Text(
            'Other categories',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          ...categories
              .where((category) => category.artifacts.isEmpty)
              .map(_knowledgeCategoryRow),
        ],
      ],
    );
  }

  Widget _contextDocumentRow(
    ManaArtifactReference artifact, {
    required VoidCallback onTap,
  }) => _quietRow(
    leading: Icon(_artifactIcon(artifact.kind)),
    title: artifact.label ?? 'Untitled document',
    subtitle: 'Open document',
    trailing: const Icon(Icons.arrow_forward_ios, size: 15),
    onTap: onTap,
  );

  Widget _knowledgeCategoryRow(
    ManaProjectContextCategory category,
  ) => _quietRow(
    leading: Icon(
      category.artifacts.isEmpty
          ? Icons.menu_book_outlined
          : Icons.auto_stories_outlined,
    ),
    title: _humanize(category.category),
    subtitle: category.artifacts.isEmpty
        ? 'No material yet'
        : '${category.artifacts.length} document${category.artifacts.length == 1 ? '' : 's'}',
    trailing: const Icon(Icons.chevron_right),
    onTap: () => _navigate(
      ObservatoryRoute(
        destination: ObservatoryDestination.knowledge,
        category: category.category,
      ),
    ),
  );

  Widget _activity(ManaSemanticReadModel model) {
    if (model.mode == ManaSemanticMode.legacyCatalog)
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Activity', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const _ObservatoryEmptyState(
            icon: Icons.bolt_outlined,
            title: 'Semantic activity is unavailable',
            message:
                'This project is using legacy catalog compatibility. Open Advanced to inspect catalog artifacts.',
          ),
        ],
      );
    if (model.mode != ManaSemanticMode.fullSemantic)
      return _placeholder(
        'Activity',
        'Semantic activity is unavailable for this capability mode.',
      );
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
      children: [
        Text('Activity', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Mana-reported project activity, kept in producer order.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        _activityFilters(model),
        const SizedBox(height: 14),
        ..._activityTimeline(model),
      ],
    );
  }

  Widget _activityFilters(ManaSemanticReadModel model) {
    final events = model.activity?.events ?? const <ManaActivityEvent>[];
    final kinds = events.map((event) => event.kind).toSet().toList();
    final workIds = events
        .map((event) => event.workItemId)
        .whereType<String>()
        .toSet()
        .toList();
    final provenance = events
        .map((event) => event.timestampProvenance)
        .toSet()
        .toList();
    if (kinds.length < 2 && workIds.length < 2 && provenance.length < 2) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        if (kinds.length > 1)
          DropdownButton<ManaActivityKind?>(
            value: _activityKindFilter,
            hint: const Text('All activity'),
            onChanged: (value) => setState(() => _activityKindFilter = value),
            items: [
              const DropdownMenuItem<ManaActivityKind?>(
                value: null,
                child: Text('All activity'),
              ),
              ...kinds.map(
                (kind) => DropdownMenuItem<ManaActivityKind?>(
                  value: kind,
                  child: Text(_humanize(kind.name)),
                ),
              ),
            ],
          ),
        if (workIds.length > 1)
          DropdownButton<String?>(
            value: _activityWorkItemFilter,
            hint: const Text('All work'),
            onChanged: (value) =>
                setState(() => _activityWorkItemFilter = value),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All work'),
              ),
              ...workIds.map(
                (id) => DropdownMenuItem<String?>(
                  value: id,
                  child: Text(_workDisplayId(id)),
                ),
              ),
            ],
          ),
        if (provenance.length > 1)
          DropdownButton<ManaTimestampProvenance?>(
            value: _activityTimeFilter,
            hint: const Text('All time sources'),
            onChanged: (value) => setState(() => _activityTimeFilter = value),
            items: [
              const DropdownMenuItem<ManaTimestampProvenance?>(
                value: null,
                child: Text('All time sources'),
              ),
              ...provenance.map(
                (value) => DropdownMenuItem<ManaTimestampProvenance?>(
                  value: value,
                  child: Text(_humanize(value.name)),
                ),
              ),
            ],
          ),
      ],
    );
  }

  List<Widget> _activityTimeline(ManaSemanticReadModel model) {
    final events = (model.activity?.events ?? const <ManaActivityEvent>[])
        .where(
          (event) =>
              (_activityKindFilter == null ||
                  event.kind == _activityKindFilter) &&
              (_activityWorkItemFilter == null ||
                  event.workItemId == _activityWorkItemFilter) &&
              (_activityTimeFilter == null ||
                  event.timestampProvenance == _activityTimeFilter),
        )
        .toList();
    if (events.isEmpty) {
      return const [
        _ObservatoryEmptyState(
          icon: Icons.bolt_outlined,
          title: 'No matching activity',
          message: 'Mana has not reported activity matching these filters.',
        ),
      ];
    }
    String? previousDay;
    return [
      for (final event in events) ...[
        if (_activityDayLabel(event) != previousDay)
          _activityDayHeading(previousDay = _activityDayLabel(event)),
        _activityTimelineRow(model, event),
      ],
    ];
  }

  Widget _activityDayHeading(String day) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 6),
    child: Text(day, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _activityTimelineRow(
    ManaSemanticReadModel model,
    ManaActivityEvent event,
  ) {
    final target = _activityTarget(model, event);
    final time = _activityTime(event);
    final contextLabel = event.workItemId == null
        ? 'Project'
        : _workDisplayId(event.workItemId!);
    final provenance =
        event.timestampProvenance ==
            ManaTimestampProvenance.filesystemMtimeEpoch
        ? 'filesystem time'
        : null;
    final section = event.target?.sectionId;
    final detail = section == null
        ? provenance
        : provenance == null
        ? _sectionLabel(section)
        : '${_sectionLabel(section)} · $provenance';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: target == null ? null : () => _navigate(target),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  time,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Container(
                width: 2,
                height: 42,
                margin: const EdgeInsets.only(right: 12, top: 1),
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contextLabel,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _activityLabel(event),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (detail != null)
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (target != null) const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  ObservatoryRoute? _activityTarget(
    ManaSemanticReadModel model,
    ManaActivityEvent event,
  ) {
    final target = event.target;
    if (target == null || _artifact(model, target.artifactId) == null) {
      return null;
    }
    if (target.workItemId case final workItemId?) {
      return ObservatoryRoute(
        destination: ObservatoryDestination.work,
        workItemId: workItemId,
        section: target.sectionId ?? ManaSectionId.overview,
        artifactId: target.artifactId,
      );
    }
    if (target.projectContextCategory case final category?) {
      return ObservatoryRoute(
        destination: ObservatoryDestination.knowledge,
        category: category,
        artifactId: target.artifactId,
      );
    }
    return ObservatoryRoute(
      destination: ObservatoryDestination.advanced,
      advancedSection: AdvancedSection.artifacts,
      artifactId: target.artifactId,
    );
  }

  Widget _advanced(ManaSemanticReadModel model) {
    final section =
        _navigation.current.advancedSection ?? AdvancedSection.artifacts;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
      children: [
        Text('Advanced', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Technical inspect data, compatibility, and diagnostics.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _advancedNavigation(section),
        const SizedBox(height: 20),
        switch (section) {
          AdvancedSection.artifacts => _advancedArtifactCatalog(model),
          AdvancedSection.diagnostics => _advancedDiagnostics(model),
        },
      ],
    );
  }

  Widget _advancedNavigation(AdvancedSection selected) => Wrap(
    spacing: 8,
    children: AdvancedSection.values
        .map(
          (section) => ChoiceChip(
            label: Text(switch (section) {
              AdvancedSection.artifacts => 'Artifact catalog',
              AdvancedSection.diagnostics => 'Inspect diagnostics',
            }),
            selected: section == selected,
            onSelected: (_) => _navigate(
              ObservatoryRoute(
                destination: ObservatoryDestination.advanced,
                advancedSection: section,
              ),
            ),
          ),
        )
        .toList(),
  );

  Widget _advancedArtifactCatalog(ManaSemanticReadModel model) {
    final artifacts =
        model.catalog?.artifacts ?? const <ManaInspectArtifactSummary>[];
    if (artifacts.isEmpty) {
      return const _ObservatoryEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Artifact catalog unavailable',
        message:
            'Mana has not made a catalog available for this project capability mode.',
      );
    }
    final families = artifacts
        .map((artifact) => artifact.family)
        .toSet()
        .toList();
    final kinds = artifacts.map((artifact) => artifact.kind).toSet().toList();
    final statuses = artifacts
        .map((artifact) => artifact.status)
        .toSet()
        .toList();
    final visible = artifacts
        .where(
          (artifact) =>
              (_advancedFamilyFilter == null ||
                  artifact.family == _advancedFamilyFilter) &&
              (_advancedKindFilter == null ||
                  artifact.kind == _advancedKindFilter) &&
              (_advancedStatusFilter == null ||
                  artifact.status == _advancedStatusFilter),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Artifact catalog', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Raw catalog identity and paths are intentionally kept in Advanced.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _advancedFilter(
              value: _advancedFamilyFilter,
              label: 'All families',
              values: families,
              onChanged: (value) =>
                  setState(() => _advancedFamilyFilter = value),
            ),
            _advancedFilter(
              value: _advancedKindFilter,
              label: 'All kinds',
              values: kinds,
              onChanged: (value) => setState(() => _advancedKindFilter = value),
            ),
            _advancedFilter(
              value: _advancedStatusFilter,
              label: 'All states',
              values: statuses,
              onChanged: (value) =>
                  setState(() => _advancedStatusFilter = value),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          const Text('No catalog artifacts match these controls.')
        else
          ...visible.map(
            (artifact) => _quietRow(
              leading: Icon(_artifactIcon(artifact.kind)),
              title: artifact.id,
              subtitle:
                  '${artifact.kind} • ${artifact.status}\n${artifact.path}',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openArtifact(artifact),
            ),
          ),
      ],
    );
  }

  Widget _advancedFilter({
    required String? value,
    required String label,
    required List<String> values,
    required ValueChanged<String?> onChanged,
  }) => DropdownButton<String?>(
    value: value,
    hint: Text(label),
    onChanged: onChanged,
    items: [
      DropdownMenuItem<String?>(value: null, child: Text(label)),
      ...values.map(
        (item) => DropdownMenuItem<String?>(
          value: item,
          child: Text(_humanize(item)),
        ),
      ),
    ],
  );

  Widget _advancedDiagnostics(ManaSemanticReadModel model) {
    final diagnostics = <ManaDiagnostic>[
      ...?model.workItems?.diagnostics,
      ...?model.projectContext?.diagnostics,
      ...?model.activity?.diagnostics,
      for (final detail in _workDetails.values) ...detail.diagnostics,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Inspect diagnostics',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Producer-reported coverage and diagnostic metadata.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _diagnosticCoverage(model),
        const SizedBox(height: 12),
        if (diagnostics.isEmpty)
          const _ObservatoryEmptyState(
            icon: Icons.rule_folder_outlined,
            title: 'No inspect diagnostics reported',
            message:
                'Mana did not include diagnostics in the available responses.',
          )
        else
          ...diagnostics.map(
            (diagnostic) => _quietRow(
              leading: Icon(_diagnosticIcon(diagnostic.severity)),
              title: _humanize(diagnostic.kind),
              subtitle:
                  '${_humanize(diagnostic.severity)} • ${_humanize(diagnostic.provenance.name)}\n${diagnostic.id}',
            ),
          ),
      ],
    );
  }

  Widget _diagnosticCoverage(ManaSemanticReadModel model) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (model.workItems != null)
        _statusPill('Work: ${model.workItems!.coverage}'),
      if (model.projectContext != null)
        _statusPill('Context: ${model.projectContext!.coverage}'),
      if (model.activity != null)
        _statusPill('Activity: ${model.activity!.coverage}'),
      if (model.catalog?.partial ?? false) _statusPill('Catalog partial'),
    ],
  );

  IconData _diagnosticIcon(String severity) => switch (severity) {
    'error' || 'critical' => Icons.error_outline,
    'warning' => Icons.warning_amber_outlined,
    _ => Icons.info_outline,
  };
  Widget _errorState() => Scaffold(
    body: Center(
      child: FilledButton(onPressed: _load, child: const Text('Try again')),
    ),
  );

  Widget _projectTitle(ManaInspectProject project) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Mana Familiar'),
      Text(
        _shortProjectIdentity(project.projectId),
        style: const TextStyle(fontSize: 12),
      ),
    ],
  );

  String _shortProjectIdentity(String id) => id.length > 28
      ? '${id.substring(0, 12)}…${id.substring(id.length - 8)}'
      : id;

  String _compactTechnicalLabel(String value) => value.length > 54
      ? '${value.substring(0, 34)}…${value.substring(value.length - 14)}'
      : value;

  String _workPrimaryLabel(ManaWorkItemSummary item) =>
      item.externalTicketId.value ??
      item.title.value ??
      _workDisplayId(item.id);

  String _workDisplayId(String id) =>
      id.contains(':') ? id.split(':').last : id;

  String? _workSecondaryLabel(ManaWorkItemSummary item) =>
      item.title.value ?? item.purpose.value;

  Widget _workTypeIcon(ManaWorkItemType type) => CircleAvatar(
    radius: 18,
    child: Icon(
      type == ManaWorkItemType.session
          ? Icons.history_outlined
          : Icons.flag_outlined,
    ),
  );

  Widget _workStatus(ManaWorkItemSummary item) =>
      item.lifecycle.state == ManaLifecycleState.unknown
      ? const SizedBox.shrink()
      : _statusPill(_humanize(item.lifecycle.state.name));

  Widget _statusPill(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(value, style: Theme.of(context).textTheme.labelMedium),
  );

  Widget _sectionEmptyState(ManaSectionId section) => _ObservatoryEmptyState(
    icon: switch (section) {
      ManaSectionId.evidence => Icons.fact_check_outlined,
      ManaSectionId.review => Icons.rate_review_outlined,
      ManaSectionId.timeline => Icons.schedule_outlined,
      _ => Icons.article_outlined,
    },
    title: 'Nothing reported for ${_sectionLabel(section).toLowerCase()}',
    message: section == ManaSectionId.evidence
        ? 'Mana has not reported evidence for this work item.'
        : 'Mana has not reported documents or material for this semantic section.',
  );

  IconData _artifactIcon(String kind) => switch (kind) {
    'markdown' => Icons.article_outlined,
    'verification-result' => Icons.fact_check_outlined,
    _ => Icons.insert_drive_file_outlined,
  };

  String _artifactLabel(ManaInspectArtifactSummary artifact) =>
      artifact.raw['label'] is String
      ? artifact.raw['label'] as String
      : 'Untitled document';

  String _activityLabel(ManaActivityEvent event) {
    if (event.summary case final summary?) return summary;
    if (event.target?.label case final label?) {
      return switch (event.kind) {
        ManaActivityKind.artifactUpdated => '$label updated',
        ManaActivityKind.verificationCompleted =>
          '$label verification completed',
        ManaActivityKind.reviewRecorded => '$label review recorded',
        ManaActivityKind.decisionRecorded => '$label decision recorded',
        ManaActivityKind.workspaceCreated => '$label created',
        ManaActivityKind.unknown => label,
      };
    }
    return switch (event.kind) {
      ManaActivityKind.workspaceCreated => 'Workspace created',
      ManaActivityKind.verificationCompleted => 'Verification completed',
      ManaActivityKind.reviewRecorded => 'Review recorded',
      ManaActivityKind.decisionRecorded => 'Decision recorded',
      ManaActivityKind.artifactUpdated => 'Document updated',
      ManaActivityKind.unknown => 'Project activity recorded',
    };
  }

  IconData _activityIcon(ManaActivityKind kind) => switch (kind) {
    ManaActivityKind.workspaceCreated => Icons.add_circle_outline,
    ManaActivityKind.verificationCompleted => Icons.fact_check_outlined,
    ManaActivityKind.reviewRecorded => Icons.rate_review_outlined,
    ManaActivityKind.decisionRecorded => Icons.account_tree_outlined,
    ManaActivityKind.artifactUpdated => Icons.edit_note_outlined,
    ManaActivityKind.unknown => Icons.bolt_outlined,
  };

  String _readableTimestamp(String value, ManaTimestampProvenance provenance) {
    final time = _parseTimestamp(value, provenance);
    if (time == null) return 'Time unavailable';
    final local = time.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year} • ${local.hour}:$minute';
  }

  DateTime? _parseTimestamp(String value, ManaTimestampProvenance provenance) {
    if (provenance == ManaTimestampProvenance.explicitDomainTimestamp) {
      return DateTime.tryParse(value);
    }
    final epoch = int.tryParse(value);
    if (epoch == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      value.length > 10 ? epoch : epoch * 1000,
      isUtc: true,
    );
  }

  String _activityDayLabel(ManaActivityEvent event) {
    final time = _parseTimestamp(
      event.timestamp,
      event.timestampProvenance,
    )?.toLocal();
    if (time == null) return 'Date unavailable';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(time.year, time.month, time.day);
    if (date == today) return 'Today';
    if (date == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${time.day} ${months[time.month - 1]} ${time.year}';
  }

  String _activityTime(ManaActivityEvent event) {
    final time = _parseTimestamp(
      event.timestamp,
      event.timestampProvenance,
    )?.toLocal();
    if (time == null) return '—';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _humanize(String value) {
    final separated = value
        .replaceAll('_', ' ')
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        );
    if (separated.isEmpty) return separated;
    return '${separated[0].toUpperCase()}${separated.substring(1)}';
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
}

class _ObservatoryEmptyState extends StatelessWidget {
  const _ObservatoryEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 24,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _SemanticBreadcrumb {
  const _SemanticBreadcrumb({
    required this.role,
    required this.label,
    this.route,
  });

  final String role;
  final String label;
  final ObservatoryRoute? route;
}
