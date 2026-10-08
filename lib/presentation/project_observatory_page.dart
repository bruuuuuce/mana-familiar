// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';

import 'package:flutter/material.dart';

import '../application/mana_inspect.dart';
import '../application/mana_knowledge.dart';
import '../application/mana_review_scheduler.dart';
import '../application/human_feedback.dart';
import '../application/semantic_navigation.dart';
import '../application/mana_workspace_watcher.dart';
import '../native_e2e_bridge.dart';
import 'artifact_detail_view.dart';
import 'knowledge_center_page.dart';
import 'review_inbox_page.dart';
import 'scheduled_review_inbox_page.dart';

/// Semantic navigation shell for the project observatory. Routes retain typed
/// work, context, activity, and document ownership through the presentation.
class ProjectObservatoryPage extends StatefulWidget {
  const ProjectObservatoryPage({
    super.key,
    required this.client,
    required this.knowledge,
    this.knowledgeBuilder,
    this.learningJourneysBuilder,
    this.initialProject,
    this.initialCatalog,
    this.initialReadModel,
    this.initialRoute,
    this.recentProjectRoots = const [],
    this.onOpenProject,
    this.artifactDetailLoader,
    this.watcher,
    this.onRefresh,
    this.feedback,
    this.feedbackDrafts,
    this.nativeE2E,
    this.knowledgeClient,
    this.recentKnowledgeDocuments = const [],
    this.onKnowledgeDocumentOpened,
    this.reviewSchedulerClient,
    this.performanceMilestone,
  });
  final ManaInspectClient client;
  final Widget knowledge;
  final Widget Function(String? journeyId)? knowledgeBuilder;
  final Widget Function(ValueChanged<String> onOpenJourney)?
  learningJourneysBuilder;
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
  final HumanFeedbackRepository? feedback;
  final HumanFeedbackDraftStore? feedbackDrafts;
  final NativeE2EBridge? nativeE2E;
  final ManaKnowledgeClient? knowledgeClient;
  final List<ManaKnowledgeDocumentSummary> recentKnowledgeDocuments;
  final Future<void> Function(ManaKnowledgeDocumentSummary document)?
  onKnowledgeDocumentOpened;
  final ManaReviewSchedulerClient? reviewSchedulerClient;
  final void Function(String milestone)? performanceMilestone;
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
  final Map<String, Object> _workDetailErrors = {};
  var _workDetailRequest = 0;
  String _workFilter = 'all';
  String _workSearch = '';
  ManaActivityKind? _activityKindFilter;
  String? _activityWorkItemFilter;
  ManaTimestampProvenance? _activityTimeFilter;
  ManaActivityPage? _activityPage;
  List<ManaActivityEvent> _pagedEvents = [];
  var _activityPageLoading = false;
  Object? _activityPageError;
  String? _advancedFamilyFilter;
  String? _advancedKindFilter;
  String? _advancedStatusFilter;
  late final ManaWorkspaceWatcher _watcher =
      widget.watcher ??
      ManaDirectoryWatcher(projectRoot: widget.client.projectRoot);
  StreamSubscription<ManaWorkspaceWatchEvent>? _watchSubscription;
  var _refreshPending = false;
  var _refreshInFlight = false;
  var _semanticRequest = 0;
  final ValueNotifier<int> _feedbackRefresh = ValueNotifier(0);
  var _watchUnavailable = false;
  var _catalogLoading = false;
  var _knowledgeRefreshPending = false;
  var _activityRefreshPending = false;
  var _supportingLoading = false;
  var _knowledgeContextLoading = false;
  Object? _knowledgeContextError;
  var _producerInitialLoadComplete = false;
  var _scheduledReviews = false;
  Object? _catalogError;
  NativeE2EObservatoryBindings? _nativeE2EObservatory;

  @override
  void initState() {
    super.initState();
    _model = widget.initialReadModel ?? _legacyModel();
    _loading = _model == null;
    if (_loading) _recordAfterFrame('project_loading_shell');
    _registerNativeE2EObservatory();
    if (_loading) _load();
    _watchSubscription = _watcher.events.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event) {
          case ManaWorkspaceWatchEvent.changed:
            _refreshPending = true;
            widget.performanceMilestone?.call('workspace_event');
          case ManaWorkspaceWatchEvent.unavailable:
            _watchUnavailable = true;
        }
      });
      if (event == ManaWorkspaceWatchEvent.changed) {
        _scheduleWorkspaceRefresh();
      }
    });
    _watcher.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadWorkDetailIfNeeded();
      _loadDetailIfNeeded();
      _loadSupportingIfNeeded();
    });
  }

  void _recordAfterFrame(String milestone) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.performanceMilestone?.call(milestone);
    });
    // An async refresh can complete while the current frame is finishing.
    // A post-frame callback alone does not request the next frame.
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    final bindings = _nativeE2EObservatory;
    if (bindings != null) widget.nativeE2E?.unregisterObservatory(bindings);
    _watchSubscription?.cancel();
    _watcher.dispose();
    _feedbackRefresh.dispose();
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
      final model = await _repository.initialLoad();
      _producerInitialLoadComplete = true;
      if (mounted)
        setState(() {
          _model = model;
          _loading = false;
        });
      _recordAfterFrame('first_meaningful_overview');
      _recordAfterFrame('visible_route_populated');
      // The post-frame request may have run before the initial inspect model
      // arrived. Re-evaluate an explicit startup artifact route now that its
      // producer-backed summary is available.
      _loadDetailIfNeeded();
      _loadWorkDetailIfNeeded();
      _loadCatalogIfNeeded();
      _loadSupportingIfNeeded();
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e;
          _loading = false;
        });
    }
  }

  void _loadSupportingIfNeeded() {
    final model = _model;
    final destination = _navigation.current.destination;
    if (model != null && destination == ObservatoryDestination.knowledge) {
      if (_producerInitialLoadComplete &&
          model.project.supportsProjectContext &&
          model.projectContext == null &&
          !_knowledgeContextLoading &&
          _knowledgeContextError == null) {
        _knowledgeContextLoading = true;
        unawaited(_loadKnowledgeContext());
      }
      return;
    }
    if (model != null &&
        destination == ObservatoryDestination.activity &&
        model.project.supportsActivityPages) {
      if (_activityPage == null &&
          !_activityPageLoading &&
          _activityPageError == null) {
        unawaited(_loadActivityPage());
      }
      return;
    }
    final supportingComplete =
        model != null &&
        (!model.project.supportsProjectContext ||
            model.projectContext != null) &&
        (!model.project.supportsActivity || model.activity != null);
    if (model == null ||
        !_producerInitialLoadComplete ||
        _supportingLoading ||
        (destination != ObservatoryDestination.overview &&
            destination != ObservatoryDestination.activity) ||
        model.refreshError != null ||
        supportingComplete) {
      return;
    }
    final request = _semanticRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          request != _semanticRequest ||
          _supportingLoading ||
          (destination != _navigation.current.destination)) {
        return;
      }
      _supportingLoading = true;
      unawaited(_loadSupportingSurfaces());
    });
  }

  Future<void> _loadKnowledgeContext() async {
    final request = _semanticRequest;
    try {
      final model = await _repository.loadProjectContext();
      if (mounted && request == _semanticRequest)
        setState(() => _model = model);
    } catch (error) {
      if (mounted && request == _semanticRequest)
        setState(() => _knowledgeContextError = error);
    } finally {
      _knowledgeContextLoading = false;
      if (mounted && request != _semanticRequest) _loadSupportingIfNeeded();
    }
  }

  Future<void> _loadSupportingSurfaces() async {
    final request = _semanticRequest;
    try {
      final model = await _repository.loadSupportingSurfaces();
      if (mounted && request == _semanticRequest && !identical(_model, model)) {
        setState(() => _model = model);
      }
      if (mounted && request == _semanticRequest) {
        _recordAfterFrame('optional_surfaces_settled');
      }
    } finally {
      _supportingLoading = false;
      if (mounted) _loadSupportingIfNeeded();
    }
  }

  Future<void> _loadActivityPage({bool restart = false}) async {
    final model = _model;
    if (model == null || _activityPageLoading) return;
    final request = _semanticRequest;
    setState(() {
      _activityPageLoading = true;
      _activityPageError = null;
      if (restart) {
        _activityPage = null;
        _pagedEvents = [];
      }
    });
    try {
      final page = await widget.client.activityPage(
        capabilities: model.project,
        cursor: _activityPage?.nextCursor,
      );
      if (!mounted || request != _semanticRequest) return;
      if (_activityPage != null && page.revision != _activityPage!.revision) {
        throw const ManaInspectException(
          ManaInspectFailure.partialCatalog,
          'Activity changed during pagination. Reload the activity view.',
        );
      }
      final combined = [..._pagedEvents, ...page.activity.events];
      if (combined.map((event) => event.id).toSet().length != combined.length ||
          combined.length > page.total) {
        throw const ManaInspectException(
          ManaInspectFailure.malformedJson,
          'Activity pages overlap or exceed the producer total.',
        );
      }
      setState(() {
        _activityPage = page;
        _pagedEvents = combined;
      });
      _recordAfterFrame('activity_page_visible');
    } catch (error) {
      if (mounted && request == _semanticRequest) {
        setState(() => _activityPageError = error);
      }
    } finally {
      if (mounted) {
        setState(() => _activityPageLoading = false);
        if (request == _semanticRequest && _activityRefreshPending) {
          if (_activityPageError != null) {
            _recordAfterFrame('activity_refresh_unavailable');
          }
          _activityRefreshPending = false;
          _recordAfterFrame('refresh_visible_route');
        }
        _loadSupportingIfNeeded();
      }
    }
  }

  void _scheduleWorkspaceRefresh() {
    if (_refreshInFlight || !mounted) return;
    unawaited(_refresh(fromWorkspaceWatch: true));
  }

  Future<void> _refresh({bool fromWorkspaceWatch = false}) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    final request = ++_semanticRequest;
    setState(() {
      _refreshPending = false;
      _knowledgeContextError = null;
      _detailCache.clear();
      _workDetails.clear();
      _workDetailErrors.clear();
      _workDetailRequest++;
      _repository.invalidateWorkItemDetails();
      // Keep the last readable document mounted until its replacement arrives.
      // Clearing it here disposes the reader (and its selection/scroll state)
      // on every feedback or atomic-publication filesystem event.
      _detailRequest++;
      _detailError = null;
      // A refresh error belongs to the previous attempt.  Keep rendering the
      // last good model while the next attempt is in flight.
      _error = null;
    });
    try {
      if (widget.onRefresh != null) {
        await widget.onRefresh!();
        _feedbackRefresh.value++;
        _loadDetailIfNeeded();
        return;
      }
      // Unlike initial load, a refresh reloads supporting semantic surfaces.
      // The raw catalog remains route-driven and is requested only while its
      // Advanced surface is visible.
      final route = _navigation.current;
      final includeCatalog =
          route.destination == ObservatoryDestination.advanced &&
          (route.advancedSection ?? AdvancedSection.artifacts) ==
              AdvancedSection.artifacts;
      final model = await _repository.refresh(includeCatalog: includeCatalog);
      if (!mounted || request != _semanticRequest) {
        _refreshPending = mounted;
        return;
      }
      final modelReplaced = !identical(_model, model);
      if (modelReplaced) {
        setState(() => _model = model);
        widget.performanceMilestone?.call('refresh_model_replaced');
      }
      final refreshingKnowledge =
          route.destination == ObservatoryDestination.knowledge &&
          widget.knowledgeClient != null;
      final refreshingPagedActivity =
          route.destination == ObservatoryDestination.activity &&
          model.project.supportsActivityPages;
      _knowledgeRefreshPending = fromWorkspaceWatch && refreshingKnowledge;
      _activityRefreshPending = fromWorkspaceWatch && refreshingPagedActivity;
      if (fromWorkspaceWatch &&
          !refreshingKnowledge &&
          !refreshingPagedActivity) {
        if (modelReplaced) {
          _recordAfterFrame('refresh_visible_route');
        } else {
          // The visible route never became stale, and no state change requests
          // another frame. Waiting on a post-frame callback here would measure
          // an unrelated future frame rather than refresh completion.
          widget.performanceMilestone?.call('refresh_visible_route');
        }
      }
      setState(() {
        _activityPage = null;
        _pagedEvents = [];
        _activityPageError = null;
      });
      _feedbackRefresh.value++;
      _loadDetailIfNeeded();
    } catch (error) {
      // Do not replace useful, potentially stale evidence with a dead-end
      // error page. Initial load still has no model and is handled by _load.
      if (mounted && _model == null) setState(() => _error = error);
    } finally {
      _refreshInFlight = false;
      // An atomic Story Start publication may emit more than one filesystem
      // event. One extra pass consumes a change observed during the current
      // read without starting a recursive refresh loop.
      if (mounted && _refreshPending) _scheduleWorkspaceRefresh();
      if (mounted) _loadSupportingIfNeeded();
    }
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
        _semanticRequest++;
        if (_refreshInFlight) _refreshPending = true;
        _detail = null;
        _detailError = null;
      });
    _loadDetailIfNeeded();
    _loadWorkDetailIfNeeded();
    _loadCatalogIfNeeded();
    _loadSupportingIfNeeded();
  }

  void _loadCatalogIfNeeded() {
    final model = _model;
    if (model == null ||
        model.catalog != null ||
        _catalogLoading ||
        _navigation.current.destination != ObservatoryDestination.advanced ||
        (_navigation.current.advancedSection ?? AdvancedSection.artifacts) !=
            AdvancedSection.artifacts ||
        !model.project.supports('artifacts', inspectArtifactsSchema)) {
      return;
    }
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    _repository
        .loadCatalog()
        .then((updated) {
          if (mounted) {
            setState(() => _model = updated);
            // An initial deep link can name a catalog-only artifact. Its
            // detail cannot load until this asynchronous catalog lookup makes
            // the producer-owned summary available.
            _recordAfterFrame('advanced_catalog_visible');
            _loadDetailIfNeeded();
          }
        })
        .catchError((Object error) {
          if (mounted) setState(() => _catalogError = error);
        })
        .whenComplete(() {
          if (mounted) setState(() => _catalogLoading = false);
        });
  }

  void _back() {
    if (_navigation.back() != null)
      setState(() {
        _detail = null;
        _detailError = null;
      });
    _loadDetailIfNeeded();
    _loadWorkDetailIfNeeded();
    _loadCatalogIfNeeded();
  }

  void _forward() {
    if (_navigation.forward() != null)
      setState(() {
        _detail = null;
        _detailError = null;
      });
    _loadDetailIfNeeded();
    _loadWorkDetailIfNeeded();
    _loadCatalogIfNeeded();
  }

  void _loadWorkDetailIfNeeded() {
    final model = _model;
    final id = _navigation.current.workItemId;
    if (model == null ||
        id == null ||
        _workDetails.containsKey(id) ||
        _workDetailErrors.containsKey(id) ||
        model.mode == ManaSemanticMode.legacyCatalog)
      return;
    final request = ++_workDetailRequest;
    _repository
        .workItem(id, model.project)
        .then((detail) {
          if (mounted && request == _workDetailRequest)
            setState(() => _workDetails[id] = detail);
        })
        .catchError((Object error) {
          if (mounted && request == _workDetailRequest)
            setState(() => _workDetailErrors[id] = error);
        });
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
    for (final detail in _workDetails.values) {
      for (final section in detail.sections) {
        for (final ref in section.artifacts) {
          if (ref.id == id) return _summary(ref);
        }
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

  void _registerNativeE2EObservatory() {
    final bridge = widget.nativeE2E;
    if (bridge == null) return;
    final bindings = NativeE2EObservatoryBindings(
      status: () {
        final model = _model;
        final route = _navigation.current;
        return {
          'loading': _loading,
          'error': _error?.toString(),
          'route': {
            'destination': route.destination.name,
            'artifactId': route.artifactId,
          },
          'catalogArtifactCount': model?.catalog?.artifacts.length ?? 0,
          'routedArtifactFound': model == null || route.artifactId == null
              ? null
              : _artifact(model, route.artifactId!) != null,
          'detailLoading': _detailLoading,
          'detailError': _detailError?.toString(),
          'detailArtifactId': _detail?.artifact.id,
          'detailArtifactRevision': _detail?.artifact.raw['revision_id'],
          'detailArtifactKind': _detail?.artifact.kind,
          'detailContentType': _detail?.artifact.raw['content_type'],
          'detailPayloadType': _detail?.payload.runtimeType.toString(),
          'feedbackProjectId': _model?.project.projectId,
        };
      },
    );
    _nativeE2EObservatory = bindings;
    bridge.registerObservatory(bindings);
  }

  ManaArtifactReference? _reference(ManaSemanticReadModel model, String id) {
    for (final work
        in model.workItems?.workItems ?? const <ManaWorkItemSummary>[]) {
      for (final reference in work.artifacts) {
        if (reference.id == id) return reference;
      }
    }
    for (final detail in _workDetails.values) {
      for (final section in detail.sections) {
        for (final reference in section.artifacts) {
          if (reference.id == id) return reference;
        }
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
    if (_loading) return _loadingState();
    if (_error != null || _model == null) return _errorState();
    final model = _model!;
    final route = _navigation.current;
    final artifact = route.artifactId == null
        ? null
        : _artifact(model, route.artifactId!);
    final feedback = model.project.supportsCapability('human_feedback')
        ? widget.feedback
        : null;
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
                                feedback: feedback,
                                feedbackDrafts: widget.feedbackDrafts,
                                feedbackProjectId: model.project.projectId,
                                feedbackRefresh: _feedbackRefresh,
                                nativeE2E: widget.nativeE2E,
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
                          feedback: feedback,
                          feedbackDrafts: widget.feedbackDrafts,
                          feedbackProjectId: model.project.projectId,
                          feedbackRefresh: _feedbackRefresh,
                          nativeE2E: widget.nativeE2E,
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
                                feedback: feedback,
                                feedbackDrafts: widget.feedbackDrafts,
                                feedbackProjectId: model.project.projectId,
                                feedbackRefresh: _feedbackRefresh,
                                nativeE2E: widget.nativeE2E,
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
                          feedback: feedback,
                          feedbackDrafts: widget.feedbackDrafts,
                          feedbackProjectId: model.project.projectId,
                          feedbackRefresh: _feedbackRefresh,
                          nativeE2E: widget.nativeE2E,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingState() => Scaffold(
    key: const Key('project-loading-shell'),
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mana Familiar'),
          Text('Opening project', style: TextStyle(fontSize: 12)),
        ],
      ),
    ),
    body: Row(
      children: [
        NavigationRail(
          selectedIndex: 0,
          labelType: NavigationRailLabelType.all,
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
              const LinearProgressIndicator(),
              Expanded(
                child: Center(
                  child: Semantics(
                    liveRegion: true,
                    label: 'Loading project overview',
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading project overview…'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

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
        route.journeyId != null ||
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
          route: route.artifactId != null || route.journeyId != null
              ? ObservatoryRoute(
                  destination: ObservatoryDestination.knowledge,
                  category: route.category,
                )
              : null,
        ),
      );
    }
    if (route.journeyId != null) {
      entries.add(
        _SemanticBreadcrumb(
          role: 'journey',
          label: labels[labelIndex++],
          route: route.artifactId != null
              ? ObservatoryRoute(
                  destination: ObservatoryDestination.knowledge,
                  category: route.category,
                  journeyId: route.journeyId,
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
          _attentionEmptyState(model)
        else
          _emphasisSurface(
            title: model.refreshError == null
                ? 'Needs attention'
                : 'Needs attention (last data may be stale)',
            icon: Icons.priority_high_rounded,
            children: attention
                .map(
                  (a) => _quietRow(
                    leading: Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: a.label ?? a.id,
                    subtitle: _attentionWorkDescription(a, work),
                    trailing: _statusPill(a.severity),
                    onTap: _attentionWorkItem(a, work) == null
                        ? null
                        : () => _navigate(
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

  ManaWorkItemSummary? _attentionWorkItem(
    ManaAttentionItem attention,
    List<ManaWorkItemSummary> work,
  ) => work.where((item) => item.id == attention.workItemId).firstOrNull;

  String _attentionWorkDescription(
    ManaAttentionItem attention,
    List<ManaWorkItemSummary> work,
  ) {
    final item = _attentionWorkItem(attention, work);
    if (item == null) {
      return '${_humanize(attention.category)} · Work association unavailable (${_workDisplayId(attention.workItemId)})';
    }
    final title = item.title.value;
    final identity = _workPrimaryLabel(item);
    return '${_humanize(attention.category)} · Work: $identity${title == null || title == identity ? '' : ' — $title'}';
  }

  Widget _attentionEmptyState(ManaSemanticReadModel model) {
    final coverage = model.workItems?.coverage;
    if (model.refreshError != null) {
      return _attentionUncertainState(
        icon: Icons.sync_problem_outlined,
        title: 'Attention data may be stale',
        message:
            'Refresh did not complete. The last successful attention data may be incomplete or stale, so project health cannot be determined.',
      );
    }
    if (coverage == 'complete') return _healthyAttentionState();
    final unavailable = coverage == null || coverage == 'none';
    return _attentionUncertainState(
      icon: unavailable ? Icons.help_outline : Icons.info_outline,
      title: unavailable
          ? 'Attention data is unavailable'
          : 'Attention data is partial',
      message: unavailable
          ? 'Mana has not reported enough work-item data. Project health cannot be determined.'
          : 'Mana reported no attention items, but the available work-item data is partial. Project health cannot be determined.',
    );
  }

  Widget _attentionUncertainState({
    required IconData icon,
    required String title,
    required String message,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeading('Needs attention'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
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
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh data'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );

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
    // A detail response is authoritative for this dossier only when it names
    // the currently selected stable work-item identity. An empty detail list
    // is meaningful; a missing response is not silently treated as empty.
    final detailForSelected = detail?.workItem.id == selected.id
        ? detail
        : null;
    final attention = detailForSelected == null
        ? selected.attentionItems
        : detailForSelected.attentionItems;
    final refs = detailForSelected == null
        ? selected.artifacts.where((a) => a.sectionId == section).toList()
        : detailForSelected.sections
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
                  ? _unknownReviewMessage(selected.review)
                  : 'Review state: ${_humanize(selected.review.state.name)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (section == ManaSectionId.overview &&
            selected.lifecycle.state == ManaLifecycleState.blocked &&
            attention.isNotEmpty) ...[
          const SizedBox(height: 18),
          _blockedWorkAttention(selected, attention),
        ],
        if (section == ManaSectionId.overview &&
            selected.lifecycle.state == ManaLifecycleState.blocked &&
            detailForSelected == null &&
            _workDetailErrors.containsKey(selected.id))
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'The latest dossier detail could not be loaded; showing the summary data.',
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

  Widget _blockedWorkAttention(
    ManaWorkItemSummary item,
    List<ManaAttentionItem> attentionItems,
  ) => Container(
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
            Icon(
              Icons.block_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              'Why this work is blocked',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...attentionItems.map(
          (attention) => _blockedAttentionCard(item, attention),
        ),
      ],
    ),
  );

  Widget _blockedAttentionCard(
    ManaWorkItemSummary item,
    ManaAttentionItem attention,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                attention.label ?? attention.id,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              _statusPill(_humanize(attention.category)),
              _statusPill(attention.severity),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Work: ${_workPrimaryLabel(item)}${item.title.value == null || item.title.value == _workPrimaryLabel(item) ? '' : ' — ${item.title.value}'}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            'Work ID: ${item.id}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            attention.nextAction == null || attention.nextAction!.trim().isEmpty
                ? 'Next action: Mana did not report one.'
                : 'Next action: ${attention.nextAction}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (attention.relatedArtifactIds.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Related artifacts:',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                ...attention.relatedArtifactIds.map((id) {
                  final artifact = _workArtifact(item, id);
                  if (artifact == null) return Text(id);
                  return TextButton(
                    onPressed: () => _openArtifact(
                      _summary(artifact),
                      workItemId: item.id,
                      section: artifact.sectionId,
                    ),
                    child: Text(artifact.label ?? artifact.id),
                  );
                }),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  ManaArtifactReference? _workArtifact(ManaWorkItemSummary item, String id) {
    final summary = item.artifacts
        .where((reference) => reference.id == id)
        .firstOrNull;
    if (summary != null) return summary;
    final detail = _workDetails[item.id];
    if (detail?.workItem.id != item.id) return null;
    for (final section in detail!.sections) {
      final reference = section.artifacts
          .where((value) => value.id == id)
          .firstOrNull;
      if (reference != null) return reference;
    }
    return null;
  }

  String _unknownReviewMessage(ManaReview review) =>
      review.provenance == ManaProvenance.unavailable ||
          review.coverage == 'none'
      ? 'Mana could not provide review information for this work item.'
      : 'Mana reports the review state as unknown for this work item.';

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
    final scheduler = widget.reviewSchedulerClient;
    if (scheduler == null) return _semanticReviews(model);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Project reviews'),
                icon: Icon(Icons.rate_review_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('PR Inbox'),
                icon: Icon(Icons.inbox_outlined),
              ),
            ],
            selected: {_scheduledReviews},
            onSelectionChanged: (values) =>
                setState(() => _scheduledReviews = values.single),
          ),
        ),
        Expanded(
          child: _scheduledReviews
              ? ScheduledReviewInboxPage(client: scheduler)
              : _semanticReviews(model),
        ),
      ],
    );
  }

  Widget _semanticReviews(ManaSemanticReadModel model) {
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
    if (_navigation.current.category == null &&
        widget.knowledgeClient != null) {
      final client = widget.knowledgeClient!;
      final categories =
          model.projectContext?.categories ??
          const <ManaProjectContextCategory>[];
      final journeys = categories.where(_isLearningJourneys).firstOrNull;
      return KnowledgeCenterPage(
        client: client,
        recentDocuments: widget.recentKnowledgeDocuments,
        onDocumentOpened: widget.onKnowledgeDocumentOpened,
        contextOverview: categories.isEmpty
            ? model.project.supportsProjectContext &&
                      model.projectContext == null
                  ? Text(
                      _knowledgeContextError == null
                          ? 'Loading project categories…'
                          : 'Project categories unavailable: $_knowledgeContextError',
                    )
                  : null
            : Column(
                children: categories
                    .where((category) => !_isLearningJourneys(category))
                    .map(_knowledgeCategoryRow)
                    .toList(),
              ),
        journeysBuilder: () => journeys == null
            ? model.project.supportsProjectContext &&
                      model.projectContext == null
                  ? _knowledgeContextError == null
                        ? const Center(child: CircularProgressIndicator())
                        : _placeholder(
                            'Journeys unavailable',
                            '$_knowledgeContextError',
                          )
                  : _placeholder(
                      'No Learning Journeys reported yet',
                      'Mana has not reported a Journey manifest for this project.',
                    )
            : _learningJourneys(journeys),
        refreshSignal: _feedbackRefresh,
        onReady: () => _recordAfterFrame('knowledge_visible'),
        onSettled: (available) {
          if (_knowledgeRefreshPending) {
            if (!available) {
              _recordAfterFrame('knowledge_refresh_unavailable');
            }
            _knowledgeRefreshPending = false;
            _recordAfterFrame('refresh_visible_route');
          }
        },
      );
    }
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
    if (selected != null && _isLearningJourneys(selected)) {
      return _learningJourneys(selected);
    }
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
        ] else ...[
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

  bool _isLearningJourneys(ManaProjectContextCategory category) =>
      category.category == 'learning_journeys';

  List<ManaArtifactReference> _journeysFor(
    ManaProjectContextCategory category,
  ) => category.artifacts
      .where((artifact) => artifact.kind == 'journey')
      .toList();

  Widget _learningJourneys(ManaProjectContextCategory category) {
    final journeyId = _navigation.current.journeyId;
    if (journeyId != null) {
      return widget.knowledgeBuilder?.call(journeyId) ?? widget.knowledge;
    }
    if (_journeysFor(category).isNotEmpty) {
      return widget.learningJourneysBuilder?.call(_openJourney) ??
          widget.knowledgeBuilder?.call(null) ??
          widget.knowledge;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
      children: const [
        Text('Knowledge'),
        SizedBox(height: 28),
        _ObservatoryEmptyState(
          icon: Icons.route_outlined,
          title: 'No Learning Journeys reported yet',
          message: 'Mana has not reported a Journey manifest for this project.',
        ),
      ],
    );
  }

  void _openJourney(String journeyId) => _navigate(
    ObservatoryRoute(
      destination: ObservatoryDestination.knowledge,
      category: 'learning_journeys',
      journeyId: journeyId,
    ),
  );

  Widget _knowledgeCategoryRow(ManaProjectContextCategory category) {
    final isLearningJourneys = _isLearningJourneys(category);
    final journeyCount = _journeysFor(category).length;
    final onlyDocument = category.artifacts.length == 1
        ? category.artifacts.single
        : null;
    return _quietRow(
      leading: Icon(
        category.artifacts.isEmpty
            ? Icons.menu_book_outlined
            : Icons.auto_stories_outlined,
      ),
      title: _humanize(category.category),
      subtitle: isLearningJourneys
          ? journeyCount == 0
                ? 'No journeys yet'
                : '$journeyCount journey${journeyCount == 1 ? '' : 's'}'
          : category.artifacts.isEmpty
          ? 'No material yet'
          : '${category.artifacts.length} document${category.artifacts.length == 1 ? '' : 's'}',
      trailing: const Icon(Icons.chevron_right),
      onTap: () => isLearningJourneys || onlyDocument == null
          ? _navigate(
              ObservatoryRoute(
                destination: ObservatoryDestination.knowledge,
                category: category.category,
              ),
            )
          : _openArtifact(_summary(onlyDocument), category: category.category),
    );
  }

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
    final events = _filteredActivityEvents(model);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
      itemCount: events.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Activity',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Mana-reported project activity, kept in producer order.',
              ),
              if (_activityPage != null)
                Text(
                  '${_pagedEvents.length} of ${_activityPage!.total} events loaded. Filters apply to loaded events.',
                ),
              const SizedBox(height: 18),
              _activityFilters(model),
              const SizedBox(height: 14),
            ],
          );
        }
        if (index == events.length + 1) {
          return Column(
            children: [
              if (events.isEmpty && !_activityPageLoading)
                const _ObservatoryEmptyState(
                  icon: Icons.bolt_outlined,
                  title: 'No matching activity',
                  message:
                      'Mana has not reported activity matching these filters.',
                ),
              if (_activityPageLoading) const LinearProgressIndicator(),
              if (_activityPageError != null) ...[
                const Text(
                  'Activity changed or could not be loaded. Reload to read the current view.',
                ),
                TextButton(
                  onPressed: () => _loadActivityPage(restart: true),
                  child: const Text('Reload activity'),
                ),
              ] else if (_activityPage?.nextCursor != null)
                TextButton(
                  onPressed: _activityPageLoading ? null : _loadActivityPage,
                  child: const Text('Load more activity'),
                ),
            ],
          );
        }
        final eventIndex = index - 1;
        final event = events[eventIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eventIndex == 0 ||
                _activityDayLabel(event) !=
                    _activityDayLabel(events[eventIndex - 1]))
              _activityDayHeading(_activityDayLabel(event)),
            _activityTimelineRow(model, event),
          ],
        );
      },
    );
  }

  Widget _activityFilters(ManaSemanticReadModel model) {
    final events = _activityPage?.activity != null
        ? _pagedEvents
        : model.activity?.events ?? const <ManaActivityEvent>[];
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

  List<ManaActivityEvent> _filteredActivityEvents(
    ManaSemanticReadModel model,
  ) =>
      (_activityPage != null
              ? _pagedEvents
              : model.activity?.events ?? const <ManaActivityEvent>[])
          .where(
            (event) =>
                (_activityKindFilter == null ||
                    event.kind == _activityKindFilter) &&
                (_activityWorkItemFilter == null ||
                    event.workItemId == _activityWorkItemFilter) &&
                (_activityTimeFilter == null ||
                    event.timestampProvenance == _activityTimeFilter),
          )
          .toList(growable: false);

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
    if (section == AdvancedSection.artifacts) {
      return _advancedArtifactCatalog(model);
    }
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
        _advancedDiagnostics(model),
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
    if (_catalogLoading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
        children: const [
          _ObservatoryEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Loading artifact catalog',
            message: 'Loading the raw catalog only when it is opened.',
          ),
        ],
      );
    }
    if (_catalogError != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
        children: const [
          _ObservatoryEmptyState(
            icon: Icons.error_outline,
            title: 'Artifact catalog unavailable',
            message:
                'Mana could not load the artifact catalog for this project.',
          ),
        ],
      );
    }
    final artifacts =
        model.catalog?.artifacts ?? const <ManaInspectArtifactSummary>[];
    if (artifacts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 18, 32, 36),
        children: const [
          _ObservatoryEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Artifact catalog unavailable',
            message:
                'Mana has not made a catalog available for this project capability mode.',
          ),
        ],
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
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 18, 32, 0),
          sliver: SliverList.list(
            children: [
              Text(
                'Advanced',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Technical inspect data, compatibility, and diagnostics.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _advancedNavigation(AdvancedSection.artifacts),
              const SizedBox(height: 20),
              Text(
                'Artifact catalog',
                style: Theme.of(context).textTheme.titleLarge,
              ),
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
                    onChanged: (value) =>
                        setState(() => _advancedKindFilter = value),
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
                const Text('No catalog artifacts match these controls.'),
            ],
          ),
        ),
        if (visible.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 36),
            sliver: SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final artifact = visible[index];
                return _quietRow(
                  leading: Icon(_artifactIcon(artifact.kind)),
                  title: artifact.id,
                  subtitle:
                      '${artifact.kind} • ${artifact.status}\n${artifact.path}',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openArtifact(artifact),
                );
              },
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
    title: section == ManaSectionId.overview
        ? 'No overview documents reported'
        : 'No documents reported for ${_sectionLabel(section).toLowerCase()}',
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
