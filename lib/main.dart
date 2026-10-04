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
  // Let the desktop embedder enable semantics after its native accessibility
  // bridge exists. Forcing Dart semantics early also loses the initial nodes
  // on macOS: enabling VoiceOver later then sends a partial tree to a new
  // bridge, which can reject the update and crash on subsequent reparenting.
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
