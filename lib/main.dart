import 'package:flutter/widgets.dart';

import 'app/mana_familiar_app.dart';
import 'application/explorer_config.dart';
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
  final config = ExplorerConfig.parse(args);
  final preferences = await ExplorerPreferences.load(config);
  if (config.fixturePath == null) {
    await preferences.rememberProjectRoot(config.projectRoot);
  }
  runApp(ManaFamiliarApp(config: config, preferences: preferences));
}
