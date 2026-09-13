import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/explorer_config.dart';

void main() {
  test('retains an explicit initial artifact when a project window is opened', () {
    final config = ExplorerConfig.parse(const [
      '--project-root',
      '/synthetic',
      '--mana-root',
      '/mana',
      '--initial-artifact',
      'file:.mana/features/FEEDBACK-E2E/planning/story-start-scope-v2.md',
    ]);

    expect(
      config.initialArtifactId,
      'file:.mana/features/FEEDBACK-E2E/planning/story-start-scope-v2.md',
    );
    expect(
      config.withProjectRoot('/other').initialArtifactId,
      config.initialArtifactId,
    );
  });
}
