import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/safe_path.dart';

void main() {
  test(
    'accepts a valid nested asset contained by its canonical root',
    () async {
      final root = await Directory.systemTemp.createTemp('mana-safe-path-');
      addTearDown(() => root.delete(recursive: true));
      final asset = File('${root.path}/assets/nested/diagram.puml');
      await asset.parent.create(recursive: true);
      await asset.writeAsString('@startuml\n@enduml\n');

      final resolved = await SafePathPolicy(
        root.path,
      ).resolveFile('assets/nested/diagram.puml');

      expect(await resolved?.readAsString(), contains('@startuml'));
    },
  );

  test('rejects traversal and absolute artifact-relative paths', () async {
    final root = await Directory.systemTemp.createTemp('mana-safe-path-');
    addTearDown(() => root.delete(recursive: true));
    final policy = SafePathPolicy(root.path);

    expect(
      () => policy.resolveFile('../outside.puml'),
      throwsA(isA<SafePathException>()),
    );
    expect(
      () => policy.resolveFile('/tmp/outside.puml'),
      throwsA(isA<SafePathException>()),
    );
    expect(
      () => policy.resolveFile(r'C:\outside.puml'),
      throwsA(isA<SafePathException>()),
    );
  });

  test('rejects symlink escapes before reading them', () async {
    final root = await Directory.systemTemp.createTemp('mana-safe-path-');
    final outside = await Directory.systemTemp.createTemp('mana-outside-');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => outside.delete(recursive: true));
    final secret = File('${outside.path}/secret.puml');
    await secret.writeAsString('outside');
    await Link('${root.path}/escape.puml').create(secret.path);

    expect(
      () => SafePathPolicy(root.path).resolveFile('escape.puml'),
      throwsA(isA<SafePathException>()),
    );
  });

  test(
    'returns missing files and rejects oversized files before reading',
    () async {
      final root = await Directory.systemTemp.createTemp('mana-safe-path-');
      addTearDown(() => root.delete(recursive: true));
      final policy = SafePathPolicy(root.path, maxBytes: 8);
      expect(await policy.resolveFile('missing.puml'), isNull);
      final oversized = File('${root.path}/oversized.puml');
      await oversized.writeAsString('123456789');

      expect(
        () => policy.resolveFile('oversized.puml'),
        throwsA(isA<SafePathException>()),
      );
    },
  );
}
