import 'dart:io';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'app/mana_familiar_app.dart';
import 'application/explorer_config.dart';
import 'application/m08_performance_probe.dart';
import 'presentation/explorer_page.dart';

export 'application/explorer_config.dart';
export 'application/artifact_renderer.dart';
export 'application/mana_inspect.dart';
export 'application/observatory_model.dart';
export 'application/operational_model.dart';
export 'application/governance_model.dart';
export 'application/review_inbox_model.dart';
export 'app/mana_familiar_app.dart';
export 'presentation/explorer_page.dart'
    show ExplorerPage, ExplorerPreferences, JourneyStore;

/// The composition root intentionally contains only process startup.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Familiar is a desktop reader with meaningful document navigation and
  // authoring controls. Keep the semantic tree available to macOS assistive
  // technology (and to the native acceptance driver) instead of relying on a
  // screen-reader process to happen to enable it after launch.
  // Windows creates its native accessibility bridge only after a UIA/MSAA
  // request. Emitting the tree before that bridge exists loses the initial
  // nodes and leaves assistive technology with an empty pane.
  if (!Platform.isWindows) SemanticsBinding.instance.ensureSemantics();
  final config = ExplorerConfig.parse(args);
  final probe = config.performanceTraceDirectory == null
      ? null
      : M08PerformanceProbe(config.performanceTraceDirectory!);
  probe?.mark('configuration_ready');
  final preferences = await ExplorerPreferences.load(config);
  probe?.mark('preferences_ready');
  if (config.fixturePath == null && config.hasExplicitProjectRoot) {
    await preferences.rememberProjectRoot(config.projectRoot);
  }
  probe?.mark('run_app_invoked');
  runApp(
    ManaFamiliarApp(
      config: config,
      preferences: preferences,
      performanceProbe: probe,
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    probe?.mark('first_application_frame');
  });
}
