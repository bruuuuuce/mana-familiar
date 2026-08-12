import 'package:flutter/material.dart';

import '../application/explorer_config.dart';
import '../application/mana_inspect.dart';
import '../presentation/explorer_page.dart';
import '../presentation/project_observatory_page.dart';

/// Top-level Material composition for the read-only Familiar desktop client.
class ManaFamiliarApp extends StatefulWidget {
  const ManaFamiliarApp({
    super.key,
    required this.config,
    required this.preferences,
  });

  final ExplorerConfig config;
  final ExplorerPreferences preferences;

  @override
  State<ManaFamiliarApp> createState() => _ManaFamiliarAppState();
}

class _ManaFamiliarAppState extends State<ManaFamiliarApp> {
  late String _projectRoot = widget.config.projectRoot;

  Future<void> _openProject(String projectRoot) async {
    await widget.preferences.rememberProjectRoot(projectRoot);
    if (mounted) setState(() => _projectRoot = projectRoot);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: widget.preferences.themeMode,
    builder: (context, mode, _) => MaterialApp(
      title: 'Mana Familiar',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: mode,
      home: widget.config.fixturePath != null
          ? Banner(
              message: 'Limited Journey mode',
              location: BannerLocation.topEnd,
              child: ExplorerPage(
                store: JourneyStore(widget.config),
                preferences: widget.preferences,
                initialJourney: widget.config.journeyId,
              ),
            )
          : ProjectObservatoryPage(
              key: ValueKey(_projectRoot),
              client: ManaInspectClient(
                projectRoot: _projectRoot,
                manaRoot: widget.config.manaRoot,
                snapshotPath: widget.config.inspectSnapshotPath,
              ),
              knowledge: ExplorerPage(
                store: JourneyStore(
                  widget.config.withProjectRoot(_projectRoot),
                ),
                preferences: widget.preferences,
                initialJourney: widget.config.journeyId,
              ),
              knowledgeBuilder: (journeyId) => ExplorerPage(
                key: ValueKey(journeyId ?? widget.config.journeyId),
                store: JourneyStore(
                  widget.config.withProjectRoot(_projectRoot),
                ),
                preferences: widget.preferences,
                initialJourney: journeyId ?? widget.config.journeyId,
              ),
              recentProjectRoots: widget.preferences.recentProjectRoots,
              onOpenProject: _openProject,
            ),
    ),
  );

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff4f46e5),
      brightness: brightness,
    ),
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xff101114)
        : const Color(0xfff8f9fc),
    useMaterial3: true,
  );
}
