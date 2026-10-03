import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/mana_process.dart';

void main() {
  test(
    'Windows timeout cleanup terminates the producer child tree',
    () async {
      final directory = await Directory.systemTemp.createTemp('mana-tree-');
      final childFile = File('${directory.path}/child.dart');
      final parentFile = File('${directory.path}/parent.dart');
      final pidFile = File('${directory.path}/child.pid');
      await childFile.writeAsString(
        "import 'dart:async';\n"
        'Future<void> main() => Future<void>.delayed(const Duration(seconds: 60));',
      );
      await parentFile.writeAsString(
        "import 'dart:io';\n"
        'Future<void> main(List<String> args) async { '
        'final child = await Process.start(Platform.resolvedExecutable, [args[0]], '
        'mode: ProcessStartMode.inheritStdio); '
        'await File(args[1]).writeAsString(child.pid.toString()); '
        'await child.exitCode; }',
      );
      final parent = await Process.start(_dartExecutable(), [
        parentFile.path,
        childFile.path,
        pidFile.path,
      ]);
      int? childPid;
      addTearDown(() async {
        parent.kill();
        if (childPid != null) Process.killPid(childPid);
        await directory.delete(recursive: true);
      });
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!pidFile.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(pidFile.existsSync(), isTrue);
      childPid = int.parse(await pidFile.readAsString());
      await terminateManaProcess(parent);
      await parent.exitCode.timeout(const Duration(seconds: 2));
      final processes = await Process.run('tasklist.exe', [
        '/FI',
        'PID eq $childPid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      expect(processes.exitCode, 0);
      expect(processes.stdout.toString(), isNot(contains('"$childPid"')));
    },
    skip: !Platform.isWindows,
  );

  test('keeps producer arguments separate from shell code', () {
    const arguments = ['a b', r'$(touch unexpected)', 'x&y', '"quoted"'];
    final command = ManaProcessCommand.resolve(
      'producer/mana-inspect.sh',
      arguments,
      windows: true,
      bashExecutable: 'git-bash.exe',
    );
    expect(command.executable, 'git-bash.exe');
    expect(command.arguments.take(2), ['--noprofile', '--norc']);
    expect(command.arguments.skip(3), arguments);
    expect(
      command.arguments[2],
      File('producer/mana-inspect.sh').absolute.path.replaceAll(r'\', '/'),
    );
  });

  test('uses Python for producer scripts and preserves native executables', () {
    final script = ManaProcessCommand.resolve(
      'producer/mana-knowledge.py',
      ['--scope', 'project'],
      windows: true,
      pythonExecutable: 'python.exe',
    );
    expect(script.executable, 'python.exe');
    expect(script.arguments.skip(1), ['--scope', 'project']);
    final native = ManaProcessCommand.resolve('producer.exe', [
      'argument',
    ], windows: true);
    expect(native.executable, 'producer.exe');
    expect(native.arguments, ['argument']);
  });

  test(
    'normalizes relative executables before changing the working directory',
    () {
      final command = ManaProcessCommand.resolve(
        '../mana/scripts/mana-inspect.sh',
        ['--json'],
        windows: false,
      );
      expect(
        command.executable,
        File('../mana/scripts/mana-inspect.sh').absolute.path,
      );
      expect(command.arguments, ['--json']);
    },
  );

  test(
    'Windows runs real shell and Python producers with literal arguments',
    () async {
      final directory = await Directory.systemTemp.createTemp('mana process ');
      addTearDown(() => directory.delete(recursive: true));
      final shell = File('${directory.path}${Platform.pathSeparator}mana');
      await shell.writeAsString('#!/bin/bash\nprintf "%s\\n" "\$@"\n');
      const arguments = [
        'with spaces',
        r'$(touch unexpected)',
        'x&y',
        '"quoted"',
      ];
      final shellResult = await runManaProcess(
        shell.path,
        arguments,
        workingDirectory: directory.path,
      );
      expect(shellResult.exitCode, 0);
      expect(
        const LineSplitter().convert(shellResult.stdout as String),
        arguments,
      );
      final python = File(
        '${directory.path}${Platform.pathSeparator}producer.py',
      );
      await python.writeAsString(
        'import json,sys\nprint(json.dumps(sys.argv[1:]))\n',
      );
      final pythonResult = await runManaProcess(
        python.path,
        arguments,
        workingDirectory: directory.path,
      );
      expect(pythonResult.exitCode, 0);
      expect(jsonDecode(pythonResult.stdout as String), arguments);
      expect(
        File(
          '${directory.path}${Platform.pathSeparator}unexpected',
        ).existsSync(),
        isFalse,
      );
    },
    skip: !Platform.isWindows,
  );
}

String _dartExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}dart-sdk'
      '${Platform.pathSeparator}bin${Platform.pathSeparator}dart.exe',
    );
    if (candidate.existsSync()) return candidate.path;
    if (directory.parent.path == directory.path) {
      throw StateError('Cannot locate the Flutter test runner Dart SDK.');
    }
    directory = directory.parent;
  }
}
