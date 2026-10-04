import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../application/explorer_config.dart';
import '../application/mana_inspect.dart';
import '../application/mana_knowledge.dart';
import '../application/m08_performance_probe.dart';
import '../application/mana_review_scheduler.dart';
import '../application/human_feedback.dart';
import '../application/semantic_navigation.dart';
import '../native_project_window.dart';
import '../native_e2e_bridge.dart';
import '../presentation/explorer_page.dart';
import '../presentation/project_observatory_page.dart';
import '../presentation/project_welcome_page.dart';

/// Top-level Material composition for the read-only Familiar desktop client.
class ManaFamiliarApp extends StatefulWidget {
  const ManaFamiliarApp({
    super.key,
    required this.config,
    required this.preferences,
    this.performanceProbe,
  });

  final ExplorerConfig config;
  final ExplorerPreferences preferences;
  final M08PerformanceProbe? performanceProbe;

  @override
  State<ManaFamiliarApp> createState() => _ManaFamiliarAppState();
}

class _ManaFamiliarAppState extends State<ManaFamiliarApp> {
  AppLifecycleListener? _exitListener;
  late String _projectRoot = widget.config.projectRoot;
  late bool _hasOpenProject = widget.config.hasExplicitProjectRoot;
  late final HumanFeedbackDraftStore _feedbackDrafts = HumanFeedbackDraftStore(
    Directory(
      '${widget.preferences.storageRoot.path}${Platform.pathSeparator}human-feedback-drafts',
    ),
    sessionId: widget.config.windowSessionId ?? 'default',
  );
  late final NativeE2EBridge? _nativeE2E = widget.config.hasNativeE2EBridge
      ? NativeE2EBridge(
          port: widget.config.nativeE2EPort!,
          token: widget.config.nativeE2EToken!,
          openProjectPicker: _chooseProject,
        )
      : null;

  Future<void> _chooseProject() async {
    if (!mounted || _hasOpenProject) {
      throw StateError('The project picker belongs to the welcome page.');
    }
    final root = await NativeProjectWindow.chooseProject();
    if (root != null) await _openProject(root);
  }

  Future<void> _openProject(String projectRoot) async {
    await widget.preferences.rememberProjectRoot(projectRoot);
    await NativeProjectWindow.presentProject(projectRoot);
    if (mounted) {
      setState(() {
        _projectRoot = projectRoot;
        _hasOpenProject = true;
      });
    }
  }

  Future<void> _clearRecentProjects() async {
    await widget.preferences.clearRecentProjectRoots();
    await NativeProjectWindow.clearRecentProjects();
    if (mounted) setState(() {});
  }

  ObservatoryRoute? _initialRoute() {
    final artifactId = widget.config.initialArtifactId;
    if (artifactId == null || artifactId.isEmpty) {
      for (final destination in ObservatoryDestination.values) {
        if (destination.name == widget.config.initialDestination) {
          return ObservatoryRoute(destination: destination);
        }
      }
      return null;
    }
    return ObservatoryRoute(
      destination: ObservatoryDestination.advanced,
      advancedSection: AdvancedSection.artifacts,
      artifactId: artifactId,
    );
  }

  @override
  void initState() {
    super.initState();
    Future<void> prepareToClose() async {
      widget.performanceProbe?.mark('close_preparation_requested');
      await _feedbackDrafts.flushAll();
      widget.performanceProbe?.mark('close_preparation_completed');
    }

    if (Platform.isWindows) {
      _exitListener = AppLifecycleListener(
        onExitRequested: () async {
          try {
            await prepareToClose();
            return AppExitResponse.exit;
          } catch (_) {
            widget.performanceProbe?.mark('close_preparation_failed');
            return AppExitResponse.cancel;
          }
        },
      );
    } else {
      NativeProjectWindow.installClosePreparation(prepareToClose);
    }
    final bridge = _nativeE2E;
    if (bridge != null) unawaited(bridge.start());
    if (widget.config.hasExplicitProjectRoot) {
      NativeProjectWindow.presentProject(_projectRoot);
    }
  }

  @override
  void dispose() {
    _exitListener?.dispose();
    // Persist pending local drafts before the app tree releases its panels.
    _feedbackDrafts.dispose();
    final bridge = _nativeE2E;
    if (bridge != null) unawaited(bridge.dispose());
    widget.performanceProbe?.dispose();
    super.dispose();
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
          : !_hasOpenProject
          ? ProjectWelcomePage(
              recentProjectRoots: widget.preferences.recentProjectRoots,
              onOpenProject: _openProject,
              onChooseProject: _chooseProject,
              onClearRecentProjects: _clearRecentProjects,
            )
          : ProjectObservatoryPage(
              key: ValueKey(_projectRoot),
              client: ManaInspectClient(
                projectRoot: _projectRoot,
                manaRoot: widget.config.manaRoot,
                snapshotPath: widget.config.inspectSnapshotPath,
                onProcessTrace: widget.performanceProbe?.recordProcess,
                onDecodeTrace: widget.performanceProbe?.recordDecode,
                onProjectionTrace: widget.performanceProbe?.recordProjection,
              ),
              performanceMilestone: widget.performanceProbe?.mark,
              initialRoute: _initialRoute(),
              feedback: widget.config.inspectSnapshotPath == null
                  ? ManaHumanFeedbackRepository(
                      projectRoot: _projectRoot,
                      manaRoot: widget.config.manaRoot,
                    )
                  : null,
              feedbackDrafts: widget.config.inspectSnapshotPath == null
                  ? _feedbackDrafts
                  : null,
              nativeE2E: _nativeE2E,
              knowledgeClient: widget.config.inspectSnapshotPath == null
                  ? ManaKnowledgeClient(
                      projectRoot: _projectRoot,
                      manaRoot: widget.config.manaRoot,
                    )
                  : null,
              reviewSchedulerClient: widget.config.inspectSnapshotPath == null
                  ? ManaReviewSchedulerClient(
                      projectRoot: _projectRoot,
                      manaRoot: widget.config.manaRoot,
                    )
                  : null,
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
              learningJourneysBuilder: (onOpenJourney) => JourneyPickerPage(
                store: JourneyStore(
                  widget.config.withProjectRoot(_projectRoot),
                ),
                onOpenJourney: onOpenJourney,
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
