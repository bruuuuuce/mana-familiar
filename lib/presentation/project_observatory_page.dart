import 'package:flutter/material.dart';

import '../application/mana_inspect.dart';
import '../application/observatory_model.dart';
import 'artifact_detail_view.dart';
import 'activity_view.dart';
import 'catalog_focus_view.dart';
import 'knowledge_module_page.dart';

enum ObservatoryDestination {
  overview,
  activity,
  review,
  evidence,
  knowledge,
  history,
}

class ProjectObservatoryPage extends StatefulWidget {
  const ProjectObservatoryPage({
    super.key,
    required this.client,
    required this.knowledge,
    this.knowledgeBuilder,
    this.initialProject,
    this.initialCatalog,
    this.recentProjectRoots = const [],
    this.onOpenProject,
    this.artifactDetailLoader,
  });
  final ManaInspectClient client;
  final Widget knowledge;
  final Widget Function(String? journeyId)? knowledgeBuilder;
  final ManaInspectProject? initialProject;
  final ManaInspectCatalog? initialCatalog;
  final List<String> recentProjectRoots;
  final Future<void> Function(String projectRoot)? onOpenProject;
  final Future<ManaInspectArtifactDetail> Function(String artifactId)?
  artifactDetailLoader;
  @override
  State<ProjectObservatoryPage> createState() => _ProjectObservatoryPageState();
}

class _ObservatoryRoute {
  const _ObservatoryRoute(this.destination, this.artifact);

  final ObservatoryDestination destination;
  final ManaInspectArtifactSummary? artifact;
}

class _ProjectObservatoryPageState extends State<ProjectObservatoryPage> {
  ObservatoryDestination _destination = ObservatoryDestination.overview;
  ManaInspectArtifactSummary? _selectedArtifact;
  ManaInspectArtifactDetail? _detail;
  Object? _detailError;
  var _detailLoading = false;
  final _history = <_ObservatoryRoute>[];
  int _historyIndex = -1;
  ManaInspectProject? _project;
  ManaInspectCatalog? _catalog;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject;
    _catalog = widget.initialCatalog;
    _loading = widget.initialCatalog == null;
    if (_loading) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      ManaInspectProject? project;
      ManaInspectCatalog? catalog;
      if (widget.client.snapshotPath != null) {
        catalog = await widget.client.catalog();
      } else {
        project = await widget.client.project();
        catalog = project.manaPresent ? await widget.client.catalog() : null;
      }
      if (mounted) {
        setState(() {
          _project = project;
          _catalog = catalog;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _select(ObservatoryDestination destination) {
    if (destination == _destination && _selectedArtifact == null) return;
    setState(() {
      _pushCurrentRoute();
      _destination = destination;
      _selectedArtifact = null;
    });
  }

  void _openArtifact(ManaInspectArtifactSummary artifact) {
    setState(() {
      _pushCurrentRoute();
      _destination = ObservatoryDestination.activity;
      _selectedArtifact = artifact;
      _detail = null;
      _detailError = null;
      _detailLoading = true;
    });
    _loadArtifactDetail(artifact);
  }

  Future<void> _loadArtifactDetail(ManaInspectArtifactSummary artifact) async {
    try {
      final detail =
          await (widget.artifactDetailLoader ?? widget.client.artifact)(
            artifact.id,
          );
      if (mounted && _selectedArtifact?.id == artifact.id) {
        setState(() {
          _detail = detail;
          _detailLoading = false;
        });
      }
    } catch (error) {
      if (mounted && _selectedArtifact?.id == artifact.id) {
        setState(() {
          _detailError = error;
          _detailLoading = false;
        });
      }
    }
  }

  void _pushCurrentRoute() {
    _history.removeRange(_historyIndex + 1, _history.length);
    _history.add(_ObservatoryRoute(_destination, _selectedArtifact));
    _historyIndex = _history.length - 1;
  }

  void _back() {
    if (_historyIndex < 0) return;
    late final ManaInspectArtifactSummary? artifact;
    setState(() {
      final route = _history[_historyIndex--];
      _destination = route.destination;
      _selectedArtifact = route.artifact;
      _detail = null;
      _detailError = null;
      _detailLoading = route.artifact != null;
      artifact = route.artifact;
    });
    if (artifact != null) _loadArtifactDetail(artifact!);
  }

  void _forward() {
    if (_historyIndex + 1 >= _history.length) return;
    late final ManaInspectArtifactSummary? artifact;
    setState(() {
      final route = _history[++_historyIndex];
      _destination = route.destination;
      _selectedArtifact = route.artifact;
      _detail = null;
      _detailError = null;
      _detailLoading = route.artifact != null;
      artifact = route.artifact;
    });
    if (artifact != null) _loadArtifactDetail(artifact!);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return _stateScaffold(
        _error is ManaInspectException &&
                (_error as ManaInspectException).kind ==
                    ManaInspectFailure.unsupportedSchema
            ? 'Inspect compatibility issue'
            : 'Could not inspect this project',
        _error.toString(),
        retry: _load,
      );
    }
    if (_project != null && !_project!.manaPresent) {
      return _stateScaffold(
        'No Mana workspace',
        'This project does not contain a usable .mana workspace.',
        retry: _load,
      );
    }
    final catalog = _catalog;
    if (catalog == null) {
      return _stateScaffold(
        'No inspect catalog available',
        'Open a project with Mana or a saved catalog snapshot.',
        retry: _load,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_project?.projectId ?? 'Saved inspect snapshot'),
        actions: [
          IconButton(
            onPressed: _historyIndex >= 0 ? _back : null,
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
          ),
          IconButton(
            onPressed: _historyIndex + 1 < _history.length ? _forward : null,
            icon: const Icon(Icons.arrow_forward),
            tooltip: 'Forward',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh catalog',
          ),
          if (widget.onOpenProject != null)
            PopupMenuButton<String>(
              tooltip: 'Open project',
              onSelected: (projectRoot) {
                if (projectRoot == '__choose__') {
                  _chooseProject();
                } else {
                  widget.onOpenProject!(projectRoot);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: '__choose__',
                  child: Text('Open project…'),
                ),
                if (widget.recentProjectRoots.isNotEmpty)
                  const PopupMenuDivider(),
                ...widget.recentProjectRoots.map(
                  (root) => PopupMenuItem(value: root, child: Text(root)),
                ),
              ],
              icon: const Icon(Icons.folder_open_outlined),
            ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _destination.index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (index) =>
                _select(ObservatoryDestination.values[index]),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: Text('Overview'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.bolt_outlined),
                label: Text('Activity'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.rate_review_outlined),
                label: Text('Review'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.fact_check_outlined),
                label: Text('Evidence'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.school_outlined),
                label: Text('Knowledge'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history),
                label: Text('History'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _body(catalog)),
        ],
      ),
    );
  }

  Widget _body(ManaInspectCatalog catalog) {
    final selectedArtifact = _selectedArtifact;
    if (selectedArtifact != null) {
      return ArtifactDetailView(
        artifact: selectedArtifact,
        detail: _detail,
        loading: _detailLoading,
        error: _detailError,
        onOpenRelatedArtifact: (id) {
          final related = catalog.artifacts.where(
            (artifact) => artifact.id == id,
          );
          if (related.isNotEmpty) _openArtifact(related.first);
        },
        sourceLoader: widget.client.source,
        projectRoot: widget.client.projectRoot,
      );
    }
    return switch (_destination) {
      ObservatoryDestination.overview => _overview(catalog),
      ObservatoryDestination.activity => ActivityView(
        artifacts: catalog.artifacts,
        onOpenArtifact: _openArtifact,
      ),
      ObservatoryDestination.review => CatalogFocusView(
        focus: CatalogFocus.review,
        artifacts: catalog.artifacts,
        onOpenArtifact: _openArtifact,
      ),
      ObservatoryDestination.evidence => CatalogFocusView(
        focus: CatalogFocus.evidence,
        artifacts: catalog.artifacts,
        onOpenArtifact: _openArtifact,
      ),
      ObservatoryDestination.knowledge => KnowledgeModulePage(
        journeys: widget.knowledge,
        journeysBuilder: widget.knowledgeBuilder,
        artifacts: catalog.artifacts,
        onOpenArtifact: _openArtifact,
      ),
      _ => _artifactList(catalog, _destination.name),
    };
  }

  Widget _overview(ManaInspectCatalog catalog) {
    final model = ObservatoryOverview.fromCatalog(catalog);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Project overview',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (_project != null) _workspaceState(),
        const SizedBox(height: 8),
        Text(
          _project == null
              ? 'Saved inspect snapshot — limited mode'
              : 'Project catalog — read only',
        ),
        if (_project?.frameworkCompatibility != 'mana-inspect/v1')
          const Card(
            child: ListTile(
              leading: Icon(Icons.warning_amber),
              title: Text('Inspect compatibility warning'),
              subtitle: Text(
                'Optional operations remain disabled unless advertised by Mana.',
              ),
            ),
          ),
        if (catalog.partial)
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Partial catalog'),
              subtitle: Text(
                'Some catalog entries could not be interpreted. Unknown data is not hidden.',
              ),
            ),
          ),
        _summary('Failed artifacts', model.failed.length, Icons.error_outline),
        _summary(
          'Blocking artifacts',
          model.blocking.length,
          Icons.block_outlined,
        ),
        if (catalog.artifacts.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.inbox_outlined),
              title: Text('Empty project catalog'),
              subtitle: Text('Mana did not report any inspectable artifacts.'),
            ),
          ),
        _summary(
          'Stale or missing evidence',
          model.staleOrMissing.length,
          Icons.link_off_outlined,
        ),
        const SizedBox(height: 16),
        Text(
          'Needs human attention',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (model.attention.isEmpty)
          const ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('No catalog item currently requires attention.'),
          ),
        ...model.attention.map(
          (item) => ListTile(
            leading: const Icon(Icons.priority_high),
            title: Text(item.artifact.id),
            subtitle: Text('${item.reason} • ${item.artifact.kind}'),
            onTap: () => _openArtifact(item.artifact),
          ),
        ),
        if (model.lastMeaningfulActivity != null)
          ListTile(
            leading: const Icon(Icons.update),
            title: const Text('Latest catalog activity'),
            subtitle: Text(model.lastMeaningfulActivity!.id),
            onTap: () => _openArtifact(model.lastMeaningfulActivity!),
          ),
      ],
    );
  }

  Widget _summary(String label, int count, IconData icon) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(
        '$count',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    ),
  );

  Widget _workspaceState() {
    final git = _project!.raw['git'];
    final gitMap = git is Map ? git : const <Object?, Object?>{};
    final branch = gitMap['branch']?.toString() ?? 'branch unavailable';
    final dirty = gitMap['dirty'] == true
        ? 'working tree has changes'
        : 'working tree clean or unavailable';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_tree_outlined),
        title: const Text('Workspace state'),
        subtitle: Text('$branch • $dirty'),
      ),
    );
  }

  Future<void> _chooseProject() async {
    final controller = TextEditingController();
    final projectRoot = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Project root',
            hintText: '/path/to/project',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    final trimmed = projectRoot?.trim();
    controller.dispose();
    if (trimmed != null && trimmed.isNotEmpty) {
      await widget.onOpenProject!(trimmed);
    }
  }

  Widget _artifactList(ManaInspectCatalog catalog, String title) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        title[0].toUpperCase() + title.substring(1),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const Text(
        'Generic catalog view; specialized renderers arrive in later phases.',
      ),
      const SizedBox(height: 12),
      ...catalog.artifacts.map(
        (artifact) => Card(
          child: ListTile(
            title: Text(artifact.id),
            subtitle: Text(
              '${artifact.family} • ${artifact.kind} • ${artifact.status}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openArtifact(artifact),
          ),
        ),
      ),
    ],
  );

  Widget _stateScaffold(
    String title,
    String message, {
    required VoidCallback retry,
  }) => Scaffold(
    appBar: AppBar(title: const Text('Mana Familiar')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 42),
              const SizedBox(height: 12),
              Text(title),
              const SizedBox(height: 8),
              SelectableText(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
