import 'dart:io';

/// Immutable startup configuration for direct-artifact and producer-backed
/// Journey loading modes.
class ExplorerConfig {
  const ExplorerConfig({
    required this.projectRoot,
    required this.manaRoot,
    this.hasExplicitProjectRoot = true,
    this.preferencesRoot,
    this.journeyId,
    this.fixturePath,
    this.inspectSnapshotPath,
  });

  final String projectRoot;
  final String manaRoot;

  /// Whether the project was deliberately selected at launch rather than
  /// inferred from the process working directory.
  final bool hasExplicitProjectRoot;
  final String? preferencesRoot;
  final String? journeyId;
  final String? fixturePath;

  /// A saved, versioned Mana inspect response for offline/demo use.
  final String? inspectSnapshotPath;

  ExplorerConfig withProjectRoot(String projectRoot) => ExplorerConfig(
    projectRoot: projectRoot,
    manaRoot: manaRoot,
    hasExplicitProjectRoot: true,
    preferencesRoot: preferencesRoot,
    journeyId: journeyId,
    fixturePath: fixturePath,
    inspectSnapshotPath: inspectSnapshotPath,
  );

  factory ExplorerConfig.parse(List<String> args) {
    String value(String flag, String fallback) {
      final index = args.indexOf(flag);
      return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
    }

    String? ancestorWith(Directory start, String child) {
      var directory = start;
      while (true) {
        if (Directory('${directory.path}/$child').existsSync()) {
          return directory.path;
        }
        final parent = directory.parent;
        if (parent.path == directory.path) return null;
        directory = parent;
      }
    }

    final starts = [
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];
    String detect(String child) {
      for (final start in starts) {
        final found = ancestorWith(start, child);
        if (found != null) return found;
      }
      return Directory.current.path;
    }

    final artifactPath = args.contains('--artifact')
        ? value('--artifact', '')
        : args.contains('--fixture')
        ? value('--fixture', '')
        : null;
    final hasExplicitProjectRoot = args.contains('--project-root');
    return ExplorerConfig(
      projectRoot: value('--project-root', detect('.mana')),
      manaRoot: value('--mana-root', detect('scripts/mana-journey.sh')),
      hasExplicitProjectRoot: hasExplicitProjectRoot,
      journeyId: args.contains('--journey') ? value('--journey', '') : null,
      fixturePath: artifactPath,
      inspectSnapshotPath: args.contains('--inspect-snapshot')
          ? value('--inspect-snapshot', '')
          : null,
    );
  }
}
