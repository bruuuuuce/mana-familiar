import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/explorer_config.dart';

void main() {
  test(
    'retains an explicit initial artifact when a project window is opened',
    () {
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
    },
  );

  test('enables the native E2E bridge only with an endpoint and token', () {
    final enabled = ExplorerConfig.parse(const [
      '--native-e2e-port',
      '38123',
      '--native-e2e-token',
      'one-time-token',
    ]);
    final incomplete = ExplorerConfig.parse(const [
      '--native-e2e-port',
      '38123',
    ]);

    expect(enabled.nativeE2EPort, 38123);
    expect(enabled.hasNativeE2EBridge, isTrue);
    expect(enabled.withProjectRoot('/other').hasNativeE2EBridge, isTrue);
    expect(incomplete.hasNativeE2EBridge, isFalse);
  });
}
