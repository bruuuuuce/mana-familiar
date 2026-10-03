// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mana_familiar/application/mana_inspect.dart';
import 'package:mana_familiar/application/mana_process.dart';

Future<void> main(List<String> arguments) async {
  final values = _arguments(arguments);
  final project = values['--project-root'];
  final mana = values['--mana-root'];
  if (project == null || mana == null) {
    stderr.writeln(
      'Usage: dart run tool/m08_performance_harness.dart --project-root <fixture> --mana-root <mana> [--output <report>]',
    );
    exitCode = 2;
    return;
  }
  final origin = Stopwatch()..start();
  final processes = <Map<String, Object?>>[];
  final decodes = <ManaInspectDecodeTrace>[];
  final projections = <ManaInspectProjectionTrace>[];
  Future<ProcessResult> runner(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    final started = origin.elapsedMicroseconds;
    final process = await startManaProcess(
      executable,
      args,
      workingDirectory: workingDirectory,
    );
    final output = BytesBuilder(copy: false);
    final errors = BytesBuilder(copy: false);
    int? firstByte;
    await Future.wait([
      process.stdout.listen((chunk) {
        firstByte ??= origin.elapsedMicroseconds;
        output.add(chunk);
      }).asFuture<void>(),
      process.stderr.listen(errors.add).asFuture<void>(),
    ]);
    final code = await process.exitCode;
    final ended = origin.elapsedMicroseconds;
    final stdoutBytes = output.takeBytes();
    processes.add({
      'operation': _operation(args),
      'start_us': started,
      'first_byte_us': firstByte,
      'last_byte_us': ended,
      'elapsed_us': ended - started,
      'response_bytes': stdoutBytes.length,
      'exit_code': code,
    });
    return ProcessResult(
      process.pid,
      code,
      utf8.decode(stdoutBytes),
      utf8.decode(errors.takeBytes(), allowMalformed: true),
    );
  }

  final client = ManaInspectClient(
    projectRoot: project,
    manaRoot: mana,
    run: runner,
    onDecodeTrace: decodes.add,
    onProjectionTrace: projections.add,
  );
  final repository = ManaSemanticRepository(client);
  final selectedAt = origin.elapsedMicroseconds;
  final initial = await repository.initialLoad();
  final meaningfulAt = origin.elapsedMicroseconds;
  final supporting = await repository.loadSupportingSurfaces();
  final settledAt = origin.elapsedMicroseconds;
  origin.stop();
  final report = {
    'schema': 'mana-familiar.c04.performance/v1',
    'build_mode': const bool.fromEnvironment('dart.vm.product')
        ? 'release'
        : 'debug',
    'environment': {
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'dart': Platform.version.split(' ').first,
    },
    'fixture': {
      'class': _fixtureClass(project),
      'manifest_digest': _manifestDigest(project),
    },
    'milestones_us': {
      'project_selected': selectedAt,
      'first_meaningful_overview': meaningfulAt,
      'optional_surfaces_settled': settledAt,
    },
    'model': {
      'mode': initial.mode.name,
      'work_items': initial.workItems?.workItems.length ?? 0,
      'semantic_revision': initial.semanticRevision,
      'supporting_project_context': supporting.projectContext != null,
      'supporting_activity': supporting.activity != null,
      'supporting_error': supporting.refreshError?.runtimeType.toString(),
    },
    'processes': processes,
    'decode': [
      for (final trace in decodes)
        {
          'response_bytes': trace.responseBytes,
          'offloaded': trace.offloaded,
          if (trace.pipelineElapsed != null)
            'pipeline_elapsed_us': trace.pipelineElapsed!.inMicroseconds,
          'elapsed_us': trace.elapsed.inMicroseconds,
        },
    ],
    'typed_projection': [
      for (final trace in projections)
        {
          'schema': trace.schema,
          if (trace.failureCode != null) 'failure_code': trace.failureCode,
          'offloaded': trace.offloaded,
          'elapsed_us': trace.elapsed.inMicroseconds,
        },
    ],
    'privacy': {
      'source_content': false,
      'absolute_paths': false,
      'credentials': false,
      'responses': false,
    },
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  final output = values['--output'];
  if (output != null)
    await File(output).writeAsString('$encoded\n', flush: true);
  stdout.writeln(jsonEncode(report));
}

Map<String, String> _arguments(List<String> values) {
  final result = <String, String>{};
  for (var index = 0; index < values.length; index += 2) {
    if (index + 1 >= values.length || !values[index].startsWith('--'))
      return {};
    result[values[index]] = values[index + 1];
  }
  return result;
}

String _operation(List<String> arguments) {
  for (final value in arguments) {
    if (const {
      'project',
      'semantic-snapshot',
      'artifacts',
      'work-items',
      'project-context',
      'activity',
    }.contains(value))
      return value;
  }
  return 'unknown';
}

String _fixtureClass(String root) {
  try {
    final value =
        jsonDecode(
              File(
                '$root${Platform.pathSeparator}m08-fixture-manifest.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    return value['fixture_class']?.toString() ?? 'unknown';
  } catch (_) {
    return 'unknown';
  }
}

String? _manifestDigest(String root) {
  try {
    final value =
        jsonDecode(
              File(
                '$root${Platform.pathSeparator}m08-fixture-manifest.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    return value['fixture_digest']?.toString();
  } catch (_) {
    return null;
  }
}
