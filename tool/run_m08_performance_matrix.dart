import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final values = _arguments(arguments);
  final manaArgument = values['--mana-root'];
  final manaRoot = manaArgument == null
      ? null
      : Directory(manaArgument).absolute.path;
  final harness = values['--harness'];
  final output = values['--output'];
  final coldRuns = int.tryParse(values['--cold-runs'] ?? '5');
  final warmRuns = int.tryParse(values['--warm-runs'] ?? '5');
  final classes = (values['--classes'] ?? 'small,medium,large,hostile-large')
      .split(',')
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  const allowedClasses = {'small', 'medium', 'large', 'hostile-large'};
  if (manaRoot == null ||
      harness == null ||
      output == null ||
      coldRuns == null ||
      warmRuns == null ||
      coldRuns < 1 ||
      warmRuns < 1 ||
      classes.isEmpty ||
      classes.any((value) => !allowedClasses.contains(value))) {
    stderr.writeln(
      'Usage: dart run tool/run_m08_performance_matrix.dart '
      '--mana-root <mana> --harness <release-executable> --output <report> '
      '[--classes small,medium,large,hostile-large] '
      '[--cold-runs 5] [--warm-runs 5]',
    );
    exitCode = 2;
    return;
  }
  final harnessFile = File(harness).absolute;
  final generator = File(
    '$manaRoot${Platform.pathSeparator}scripts${Platform.pathSeparator}generate-m08-fixture.py',
  );
  if (!harnessFile.existsSync()) {
    stderr.writeln('The release harness is missing.');
    exitCode = 2;
    return;
  }
  if (!generator.existsSync()) {
    stderr.writeln('The Mana fixture generator is missing.');
    exitCode = 2;
    return;
  }

  final temporary = Directory.systemTemp.createTempSync(
    'mana-familiar-m08-matrix-',
  );
  try {
    final environment = await _environment(manaRoot);
    final fixtureReports = <Map<String, Object?>>[];
    for (final fixtureClass in classes) {
      final fixture = Directory(
        '${temporary.path}${Platform.pathSeparator}$fixtureClass',
      );
      await _checked('python3', [
        generator.path,
        '--output',
        fixture.path,
        '--class',
        fixtureClass,
        '--seed',
        '20260928',
      ]);
      final manifest =
          jsonDecode(
                File(
                  '${fixture.path}${Platform.pathSeparator}m08-fixture-manifest.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final cold = <Map<String, dynamic>>[];
      for (var index = 0; index < coldRuns; index++) {
        final cache = Directory(
          '${temporary.path}${Platform.pathSeparator}cache-$fixtureClass-cold-$index',
        )..createSync();
        cold.add(
          await _runHarness(
            harness: harnessFile.path,
            projectRoot: fixture.path,
            manaRoot: manaRoot,
            cacheRoot: cache.path,
          ),
        );
      }
      final warmCache = Directory(
        '${temporary.path}${Platform.pathSeparator}cache-$fixtureClass-warm',
      )..createSync();
      await _runHarness(
        harness: harnessFile.path,
        projectRoot: fixture.path,
        manaRoot: manaRoot,
        cacheRoot: warmCache.path,
      );
      final warm = <Map<String, dynamic>>[];
      for (var index = 0; index < warmRuns; index++) {
        warm.add(
          await _runHarness(
            harness: harnessFile.path,
            projectRoot: fixture.path,
            manaRoot: manaRoot,
            cacheRoot: warmCache.path,
          ),
        );
      }
      fixtureReports.add({
        'class': fixtureClass,
        'manifest_digest': manifest['fixture_digest'],
        'logical_counts': manifest['logical_counts'],
        'cold': cold,
        'warm': warm,
        'median_us': {
          'cold_first_meaningful_overview': _median(
            cold.map(_meaningfulOverview),
          ),
          'warm_first_meaningful_overview': _median(
            warm.map(_meaningfulOverview),
          ),
          'cold_optional_surfaces_settled': _median(cold.map(_settled)),
          'warm_optional_surfaces_settled': _median(warm.map(_settled)),
        },
      });
    }
    final first = fixtureReports.first['cold'] as List<Map<String, dynamic>>;
    final report = {
      'schema': 'mana-familiar.c04.performance-matrix/v1',
      'build_mode': first.first['build_mode'],
      'environment': {
        ...(first.first['environment'] as Map<String, dynamic>),
        ...environment,
      },
      'runs_per_fixture': {'cold': coldRuns, 'warm': warmRuns},
      'background_load_policy':
          'route-minimal initial semantic snapshot; supporting context and activity after first meaningful model; raw catalog route-only',
      'cache_policy': {
        'cold': 'isolated empty MANA_CACHE_HOME per run',
        'warm': 'one priming run followed by repeated shared-cache runs',
      },
      'fixtures': fixtureReports,
      'privacy': {
        'source_content': false,
        'absolute_paths': false,
        'credentials': false,
        'responses': false,
      },
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(report);
    final outputFile = File(output);
    outputFile.parent.createSync(recursive: true);
    outputFile.writeAsStringSync('$encoded\n', flush: true);
    stdout.writeln(jsonEncode(report));
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

Future<Map<String, Object?>> _environment(String manaRoot) async {
  final familiarRoot = Directory.current.path;
  final machine = Platform.isWindows
      ? Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'unknown'
      : (await _checked('uname', ['-m'])).stdout.toString().trim();
  final flutter = _flutterVersion();
  return {
    'machine': machine,
    'flutter': flutter,
    'mana_revision': await _revision(manaRoot),
    'mana_dirty': await _dirty(manaRoot),
    'familiar_revision': await _revision(familiarRoot),
    'familiar_dirty': await _dirty(familiarRoot),
  };
}

String _flutterVersion() {
  final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
  for (final directory in (Platform.environment['PATH'] ?? '').split(
    Platform.isWindows ? ';' : ':',
  )) {
    if (directory.isEmpty) continue;
    final candidate = File('$directory${Platform.pathSeparator}$executable');
    if (!candidate.existsSync()) continue;
    try {
      final binary = candidate.resolveSymbolicLinksSync();
      final root = File(binary).parent.parent.path;
      final versionFile = File(
        '$root${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}flutter.version.json',
      );
      final version =
          jsonDecode(versionFile.readAsStringSync()) as Map<String, dynamic>;
      final framework = version['frameworkVersion'];
      final channel = version['channel'];
      if (framework is String && channel is String) {
        return '$framework ($channel)';
      }
    } catch (_) {
      return 'unavailable';
    }
  }
  return 'unavailable';
}

Future<String> _revision(String root) async {
  final result = await Process.run('git', [
    '-C',
    root,
    'rev-parse',
    'HEAD',
  ], runInShell: false);
  return result.exitCode == 0 ? result.stdout.toString().trim() : 'unavailable';
}

Future<bool?> _dirty(String root) async {
  final result = await Process.run('git', [
    '-C',
    root,
    'status',
    '--porcelain',
  ], runInShell: false);
  return result.exitCode == 0
      ? result.stdout.toString().trim().isNotEmpty
      : null;
}

Future<Map<String, dynamic>> _runHarness({
  required String harness,
  required String projectRoot,
  required String manaRoot,
  required String cacheRoot,
}) async {
  final result = await _checked(
    harness,
    ['--project-root', projectRoot, '--mana-root', manaRoot],
    environment: {...Platform.environment, 'MANA_CACHE_HOME': cacheRoot},
  );
  return jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
}

Future<ProcessResult> _checked(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    environment: environment,
    runInShell: false,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      result.stderr.toString().trim(),
      result.exitCode,
    );
  }
  return result;
}

int _meaningfulOverview(Map<String, dynamic> report) =>
    (report['milestones_us']
            as Map<String, dynamic>)['first_meaningful_overview']
        as int;

int _settled(Map<String, dynamic> report) =>
    (report['milestones_us']
            as Map<String, dynamic>)['optional_surfaces_settled']
        as int;

num _median(Iterable<int> values) {
  final ordered = values.toList()..sort();
  final middle = ordered.length ~/ 2;
  if (ordered.length.isOdd) return ordered[middle];
  return (ordered[middle - 1] + ordered[middle]) / 2;
}

Map<String, String> _arguments(List<String> values) {
  final result = <String, String>{};
  for (var index = 0; index < values.length; index += 2) {
    if (index + 1 >= values.length || !values[index].startsWith('--')) {
      return {};
    }
    result[values[index]] = values[index + 1];
  }
  return result;
}
