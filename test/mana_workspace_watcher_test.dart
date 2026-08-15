import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/mana_workspace_watcher.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mana-watcher-test-');
    await Directory('${root.path}${Platform.pathSeparator}.mana').create();
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('uses the required 750 ms debounce by default', () {
    expect(
      ManaDirectoryWatcher(projectRoot: root.path).debounce,
      const Duration(milliseconds: 750),
    );
  });

  test(
    'reports one changed event after the debounce for .mana changes',
    () async {
      final watcher = ManaDirectoryWatcher(
        projectRoot: root.path,
        debounce: const Duration(milliseconds: 50),
      );
      final events = <ManaWorkspaceWatchEvent>[];
      final subscription = watcher.events.listen(events.add);
      await watcher.start();

      final file = File(
        '${root.path}${Platform.pathSeparator}.mana${Platform.pathSeparator}state.json',
      );
      await file.writeAsString('{"version": 1}');
      await file.writeAsString('{"version": 2}');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(events, [ManaWorkspaceWatchEvent.changed]);
      await subscription.cancel();
      await watcher.dispose();
    },
  );

  test('does not observe changes outside .mana', () async {
    final watcher = ManaDirectoryWatcher(
      projectRoot: root.path,
      debounce: const Duration(milliseconds: 30),
    );
    final events = <ManaWorkspaceWatchEvent>[];
    final subscription = watcher.events.listen(events.add);
    await watcher.start();
    // macOS may deliver the directory creation from setup after registration.
    // It is not part of the root-level write this test is exercising.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    events.clear();

    await File(
      '${root.path}${Platform.pathSeparator}unrelated.txt',
    ).writeAsString('ignored');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(events, isEmpty);
    await subscription.cancel();
    await watcher.dispose();
  });

  test('reports unavailable when .mana is absent', () async {
    final missingRoot = await Directory.systemTemp.createTemp(
      'mana-missing-test-',
    );
    addTearDown(() => missingRoot.delete(recursive: true));
    final watcher = ManaDirectoryWatcher(projectRoot: missingRoot.path);
    final event = watcher.events.first;

    await watcher.start();

    expect(await event, ManaWorkspaceWatchEvent.unavailable);
    await watcher.dispose();
  });

  test('dispose stops pending notifications', () async {
    final watcher = ManaDirectoryWatcher(
      projectRoot: root.path,
      debounce: const Duration(milliseconds: 100),
    );
    final events = <ManaWorkspaceWatchEvent>[];
    final subscription = watcher.events.listen(events.add);
    await watcher.start();
    await File(
      '${root.path}${Platform.pathSeparator}.mana${Platform.pathSeparator}state.json',
    ).writeAsString('{}');
    await watcher.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(events, isEmpty);
    await subscription.cancel();
  });
}
