import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/source_workspace.dart';

void main() {
  test(
    'resolves the analyzed snapshot and reports working-tree drift',
    () async {
      final root = await Directory.systemTemp.createTemp('mana-source-');
      addTearDown(() => root.delete(recursive: true));
      // Reuse a pinned local snapshot instead of creating a fixture commit.
      final repository = (await _git(Directory.current.path, [
        'rev-parse',
        '--show-toplevel',
      ])).trim();
      final revision = (await _git(repository, ['rev-parse', 'HEAD'])).trim();
      await _git(root.path, [
        'clone',
        '--quiet',
        '--no-hardlinks',
        '--no-checkout',
        repository,
        '.',
      ]);
      await _git(root.path, ['checkout', '--quiet', '--detach', revision]);
      const sourcePath = 'lib/source_workspace.dart';
      final snapshotContents = await _git(root.path, [
        'show',
        '$revision:$sourcePath',
      ]);
      final source = File('${root.path}/$sourcePath');
      await source.writeAsString('$snapshotContents// Working-tree drift.\n');

      final resolved = await SourceResolver().resolve(
        SourceLocation(
          projectRoot: root.path,
          path: sourcePath,
          startLine: 1,
          endLine: 1,
          revision: revision,
        ),
      );

      expect(resolved.state, SourceState.snapshot);
      expect(resolved.contents, snapshotContents);
      expect(resolved.drifted, isTrue);
    },
  );

  test(
    'does not treat a current file as authoritative when its snapshot is absent',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mana-source-missing-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/source.java');
      await source.writeAsString('class Source {}\n');

      final resolved = await SourceResolver().resolve(
        SourceLocation(
          projectRoot: root.path,
          path: 'source.java',
          startLine: 1,
          endLine: 1,
          revision: 'does-not-exist',
        ),
      );

      expect(resolved.state, SourceState.snapshotUnavailable);
      expect(resolved.available, isTrue);
      expect(resolved.status, contains('not authoritative'));
    },
  );

  test('resolves supported source languages and rejects unsafe locations', () {
    expect(sourceLanguage('lib/page.dart'), 'dart');
    expect(sourceLanguage('scripts/check.sh'), 'bash');
    expect(sourceLanguage('notes.unknown'), 'plaintext');
    expect(
      SourceLocation(
        projectRoot: '/project',
        path: '../outside.dart',
        startLine: 1,
        endLine: 1,
      ).isSafe,
      isFalse,
    );
  });

  test('reports a missing source explicitly', () async {
    final root = await Directory.systemTemp.createTemp('mana-source-absent-');
    addTearDown(() => root.delete(recursive: true));

    final resolved = await SourceResolver().resolve(
      SourceLocation(
        projectRoot: root.path,
        path: 'missing.dart',
        startLine: 1,
        endLine: 2,
      ),
    );

    expect(resolved.state, SourceState.missing);
    expect(resolved.available, isFalse);
  });

  test(
    'blocks a source anchor whose symlink escapes the project root',
    () async {
      final root = await Directory.systemTemp.createTemp('mana-source-root-');
      final outside = await Directory.systemTemp.createTemp('mana-source-out-');
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => outside.delete(recursive: true));
      final outsideFile = File('${outside.path}/secret.dart');
      await outsideFile.writeAsString('void secret() {}');
      await Directory('${root.path}/lib').create();
      await Link('${root.path}/lib/escape.dart').create(outsideFile.path);

      final resolved = await SourceResolver().resolve(
        SourceLocation(
          projectRoot: root.path,
          path: 'lib/escape.dart',
          startLine: 1,
          endLine: 1,
        ),
      );

      expect(resolved.state, SourceState.blocked);
      expect(resolved.status, contains('escapes its allowed root'));
    },
  );
}

Future<String> _git(String root, List<String> arguments) async {
  final result = await Process.run('git', ['-C', root, ...arguments]);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  return result.stdout.toString();
}
