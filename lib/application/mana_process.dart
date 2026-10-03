import 'dart:convert';
import 'dart:io';

/// Selects an interpreter without converting producer arguments into shell code.
class ManaProcessCommand {
  const ManaProcessCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  static ManaProcessCommand resolve(
    String executable,
    List<String> arguments, {
    required bool windows,
    String bashExecutable = 'bash.exe',
    String pythonExecutable = 'python.exe',
  }) {
    final name = executable.split(RegExp(r'[/\\]')).last.toLowerCase();
    final path = executable.contains('/') || executable.contains('\\')
        ? File(executable).absolute.path
        : executable;
    if (windows && name.endsWith('.py')) {
      return ManaProcessCommand(pythonExecutable, [path, ...arguments]);
    }
    if (windows && (name.endsWith('.sh') || name == 'mana')) {
      return ManaProcessCommand(bashExecutable, [
        '--noprofile',
        '--norc',
        path.replaceAll('\\', '/'),
        ...arguments,
      ]);
    }
    return ManaProcessCommand(path, arguments);
  }
}

Future<Process> startManaProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  final command = ManaProcessCommand.resolve(
    executable,
    arguments,
    windows: Platform.isWindows,
    bashExecutable: Platform.isWindows ? _gitBash() : 'bash',
  );
  return Process.start(
    command.executable,
    command.arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
    environment: Platform.isWindows
        ? {...Platform.environment, 'PYTHONUTF8': '1'}
        : null,
  );
}

Future<ProcessResult> runManaProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final process = await startManaProcess(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  await process.stdin.close();
  final streams = await Future.wait([
    process.stdout.transform(utf8.decoder).join(),
    process.stderr.transform(utf8.decoder).join(),
  ]);
  return ProcessResult(
    process.pid,
    await process.exitCode,
    streams[0],
    streams[1],
  );
}

String _gitBash() {
  for (final root in [
    Platform.environment['ProgramFiles'],
    Platform.environment['ProgramFiles(x86)'],
    Platform.environment['LOCALAPPDATA'],
  ]) {
    if (root == null) continue;
    final candidate = File(
      '$root${Platform.pathSeparator}Git'
      '${Platform.pathSeparator}bin${Platform.pathSeparator}bash.exe',
    );
    if (candidate.existsSync()) return candidate.path;
  }
  // An explicitly installed Git Bash on PATH remains supported.
  return 'bash.exe';
}
