import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/mana_process.dart';

void main() {
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
