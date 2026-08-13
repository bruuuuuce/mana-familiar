import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../safe_path.dart';

const inspectProjectSchema = 'mana.inspect.project/v1';
const inspectArtifactsSchema = 'mana.inspect.artifacts/v1';
const inspectArtifactSchema = 'mana.inspect.artifact/v1';
const inspectSourceSchema = 'mana.inspect.source/v1';

enum ManaInspectMode { projectWrapper, producerRoot, snapshot }

class ManaInspectException implements Exception {
  const ManaInspectException(this.kind, this.message);
  final ManaInspectFailure kind;
  final String message;
  @override
  String toString() => 'Mana inspect $kind: $message';
}

enum ManaInspectFailure {
  transport,
  command,
  malformedJson,
  unsupportedSchema,
  missingProject,
  missingMana,
  partialCatalog,
}

class ManaInspectOperation {
  const ManaInspectOperation({
    required this.name,
    required this.schema,
    this.raw = const {},
  });
  final String name;
  final String schema;
  final Map<String, dynamic> raw;
}

class ManaInspectProject {
  const ManaInspectProject({
    required this.projectId,
    required this.frameworkCompatibility,
    required this.manaPresent,
    required this.operations,
    required this.raw,
  });
  final String projectId;
  final String? frameworkCompatibility;
  final bool manaPresent;
  final List<ManaInspectOperation> operations;
  final Map<String, dynamic> raw;

  bool supports(String operation, String schema) => operations.any(
    (candidate) => candidate.name == operation && candidate.schema == schema,
  );

  factory ManaInspectProject.fromJson(Map<String, dynamic> json) {
    _requireSchema(json, inspectProjectSchema);
    final mana = _map(json['mana']);
    return ManaInspectProject(
      projectId: _string(json['project_id'], 'project_id'),
      frameworkCompatibility:
          _map(json['framework'])['compatibility'] as String?,
      manaPresent: mana['present'] as bool? ?? false,
      operations: (_list(json['operations']))
          .whereType<Map>()
          .map((value) {
            final raw = value.cast<String, dynamic>();
            return ManaInspectOperation(
              name: _string(raw['name'], 'operations[].name'),
              schema: _string(raw['schema'], 'operations[].schema'),
              raw: raw,
            );
          })
          .toList(growable: false),
      raw: json,
    );
  }
}

class ManaInspectArtifactSummary {
  const ManaInspectArtifactSummary({
    required this.id,
    required this.path,
    required this.family,
    required this.kind,
    required this.status,
    required this.raw,
  });
  final String id;
  final String path;
  final String family;
  final String kind;
  final String status;
  final Map<String, dynamic> raw;
  factory ManaInspectArtifactSummary.fromJson(Map<String, dynamic> json) =>
      ManaInspectArtifactSummary(
        id: _string(json['artifact_id'], 'artifact_id'),
        path: _string(json['path'], 'path'),
        family: _string(json['family'], 'family'),
        kind: _string(json['kind'], 'kind'),
        status: _string(json['status'], 'status'),
        raw: json,
      );
}

class ManaInspectCatalog {
  const ManaInspectCatalog({
    required this.artifacts,
    required this.raw,
    this.partial = false,
  });
  final List<ManaInspectArtifactSummary> artifacts;
  final Map<String, dynamic> raw;
  final bool partial;
  factory ManaInspectCatalog.fromJson(Map<String, dynamic> json) {
    _requireSchema(json, inspectArtifactsSchema);
    final entries = _list(json['artifacts']);
    final artifacts = <ManaInspectArtifactSummary>[];
    var partial = false;
    for (final value in entries) {
      if (value is! Map) {
        partial = true;
        continue;
      }
      try {
        artifacts.add(
          ManaInspectArtifactSummary.fromJson(value.cast<String, dynamic>()),
        );
      } on ManaInspectException {
        partial = true;
      }
    }
    return ManaInspectCatalog(
      artifacts: artifacts,
      raw: json,
      partial: partial,
    );
  }
}

class ManaInspectArtifactDetail {
  const ManaInspectArtifactDetail({
    required this.artifact,
    required this.payload,
    required this.relations,
    required this.raw,
  });
  final ManaInspectArtifactSummary artifact;

  /// The producer-owned payload is intentionally opaque to the transport
  /// layer. Presentation selects a safe renderer from its schema and metadata.
  final Object? payload;
  final List<Map<String, dynamic>> relations;
  final Map<String, dynamic> raw;
  factory ManaInspectArtifactDetail.fromJson(Map<String, dynamic> json) {
    _requireSchema(json, inspectArtifactSchema);
    return ManaInspectArtifactDetail(
      artifact: ManaInspectArtifactSummary.fromJson(_map(json['artifact'])),
      payload: json['payload'],
      relations: _objects(json['relations']),
      raw: json,
    );
  }
}

class ManaInspectSourceRelations {
  const ManaInspectSourceRelations({
    required this.path,
    required this.availability,
    required this.coverage,
    required this.relations,
    required this.raw,
  });
  final String path;
  final String availability;
  final String coverage;
  final List<Map<String, dynamic>> relations;
  final Map<String, dynamic> raw;
  factory ManaInspectSourceRelations.fromJson(Map<String, dynamic> json) {
    _requireSchema(json, inspectSourceSchema);
    final source = _map(json['source']);
    return ManaInspectSourceRelations(
      path: _string(source['path'], 'source.path'),
      availability: _string(source['availability'], 'source.availability'),
      coverage: _string(json['coverage'], 'coverage'),
      relations: _objects(json['relations']),
      raw: json,
    );
  }
}

typedef ManaProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

class ManaInspectClient {
  ManaInspectClient({
    required this.projectRoot,
    this.manaRoot,
    this.snapshotPath,
    ManaProcessRunner? run,
  }) : _run =
           run ??
           ((executable, arguments, {workingDirectory}) => Process.run(
             executable,
             arguments,
             workingDirectory: workingDirectory,
           ));

  final String projectRoot;
  final String? manaRoot;
  final String? snapshotPath;
  final ManaProcessRunner _run;

  ManaInspectMode get mode {
    if (snapshotPath != null) return ManaInspectMode.snapshot;
    if (File('$projectRoot${Platform.pathSeparator}mana').existsSync()) {
      return ManaInspectMode.projectWrapper;
    }
    return ManaInspectMode.producerRoot;
  }

  Future<ManaInspectProject> project() async =>
      ManaInspectProject.fromJson(await _response('project'));

  Future<ManaInspectCatalog> catalog() async {
    if (snapshotPath != null) {
      return ManaInspectCatalog.fromJson(await _response('artifacts'));
    }
    final projectInfo = await project();
    if (!projectInfo.manaPresent) {
      throw const ManaInspectException(
        ManaInspectFailure.missingMana,
        'The selected project has no usable .mana workspace.',
      );
    }
    _requireOperation(projectInfo, 'artifacts', inspectArtifactsSchema);
    return ManaInspectCatalog.fromJson(await _response('artifacts'));
  }

  Future<ManaInspectArtifactDetail> artifact(String id) async {
    if (snapshotPath != null) {
      return ManaInspectArtifactDetail.fromJson(
        await _response('artifact', target: id),
      );
    }
    final projectInfo = await project();
    _requireOperation(projectInfo, 'artifact', inspectArtifactSchema);
    return ManaInspectArtifactDetail.fromJson(
      await _response('artifact', target: id),
    );
  }

  Future<ManaInspectSourceRelations> source(String path) async {
    if (!SafePathPolicy.isSafeRelativePath(path) || path.startsWith('.mana/')) {
      throw const ManaInspectException(
        ManaInspectFailure.missingProject,
        'Source paths must be safe project-relative paths.',
      );
    }
    if (snapshotPath != null) {
      return ManaInspectSourceRelations.fromJson(
        await _response('source', target: path),
      );
    }
    final projectInfo = await project();
    _requireOperation(projectInfo, 'source', inspectSourceSchema);
    return ManaInspectSourceRelations.fromJson(
      await _response('source', target: path),
    );
  }

  Future<Map<String, dynamic>> _response(
    String operation, {
    String? target,
  }) async {
    if (snapshotPath != null) return _readSnapshot(operation);
    final executable = mode == ManaInspectMode.projectWrapper
        ? '$projectRoot${Platform.pathSeparator}mana'
        : '${manaRoot ?? ''}${Platform.pathSeparator}scripts${Platform.pathSeparator}mana-inspect.sh';
    if (mode == ManaInspectMode.producerRoot &&
        (manaRoot == null ||
            manaRoot!.isEmpty ||
            !File(executable).existsSync())) {
      throw const ManaInspectException(
        ManaInspectFailure.transport,
        'No project-local ./mana wrapper or explicit compatible Mana root is available.',
      );
    }
    final arguments = <String>[
      if (mode == ManaInspectMode.projectWrapper) 'inspect',
      if (mode == ManaInspectMode.producerRoot) ...[
        '--project-root',
        projectRoot,
      ],
      operation,
      if (target case final String value) value,
      '--json',
    ];
    ProcessResult result;
    try {
      result = await _run(executable, arguments, workingDirectory: projectRoot);
    } on ProcessException catch (error) {
      throw ManaInspectException(ManaInspectFailure.transport, error.message);
    }
    if (result.exitCode != 0) {
      throw ManaInspectException(
        ManaInspectFailure.command,
        'Exit ${result.exitCode}: ${result.stderr}'.trim(),
      );
    }
    return _decode(result.stdout.toString());
  }

  Future<Map<String, dynamic>> _readSnapshot(String operation) async {
    try {
      final file = await SafePathPolicy.resolveDirectFile(snapshotPath!);
      if (file == null) {
        throw const ManaInspectException(
          ManaInspectFailure.transport,
          'Inspect snapshot does not exist.',
        );
      }
      final decoded = _decode(await file.readAsString());
      final expected = switch (operation) {
        'project' => inspectProjectSchema,
        'artifacts' => inspectArtifactsSchema,
        'artifact' => inspectArtifactSchema,
        'source' => inspectSourceSchema,
        _ => null,
      };
      if (decoded['schema'] == expected) return decoded;
      throw ManaInspectException(
        ManaInspectFailure.partialCatalog,
        'Snapshot contains ${decoded['schema']}, not the requested $operation response.',
      );
    } on SafePathException catch (error) {
      throw ManaInspectException(ManaInspectFailure.transport, error.message);
    }
  }
}

class ManaInspectRefreshService {
  ManaInspectRefreshService(
    this.client, {
    this.debounce = const Duration(milliseconds: 300),
  });
  final ManaInspectClient client;
  final Duration debounce;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _timer;
  Stream<ManaInspectCatalog> watchCatalog() {
    final controller = StreamController<ManaInspectCatalog>();
    final root = Directory(
      '${client.projectRoot}${Platform.pathSeparator}.mana',
    );
    if (!root.existsSync()) {
      controller.addError(
        const ManaInspectException(
          ManaInspectFailure.missingMana,
          '.mana is not available for refresh.',
        ),
      );
      return controller.stream;
    }
    _watch = root.watch(recursive: true).listen((_) {
      _timer?.cancel();
      _timer = Timer(debounce, () async {
        try {
          controller.add(await client.catalog());
        } catch (error, trace) {
          controller.addError(error, trace);
        }
      });
    }, onError: controller.addError);
    controller.onCancel = () async {
      _timer?.cancel();
      await _watch?.cancel();
    };
    return controller.stream;
  }
}

void _requireOperation(
  ManaInspectProject project,
  String operation,
  String schema,
) {
  if (!project.supports(operation, schema)) {
    throw ManaInspectException(
      ManaInspectFailure.unsupportedSchema,
      'Mana does not advertise $operation with $schema.',
    );
  }
}

void _requireSchema(Map<String, dynamic> json, String supported) {
  final actual = json['schema'];
  if (actual != supported) {
    throw ManaInspectException(
      ManaInspectFailure.unsupportedSchema,
      'Expected $supported but received ${actual ?? 'no schema'}.',
    );
  }
}

Map<String, dynamic> _decode(String raw) {
  try {
    final value = jsonDecode(raw);
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('response is not an object');
  } on FormatException catch (error) {
    throw ManaInspectException(ManaInspectFailure.malformedJson, error.message);
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw const ManaInspectException(
    ManaInspectFailure.malformedJson,
    'Expected an object.',
  );
}

List<dynamic> _list(Object? value) {
  if (value is List) return value;
  throw const ManaInspectException(
    ManaInspectFailure.malformedJson,
    'Expected an array.',
  );
}

List<Map<String, dynamic>> _objects(Object? value) => _list(value)
    .whereType<Map>()
    .map((value) => value.cast<String, dynamic>())
    .toList(growable: false);
String _string(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw ManaInspectException(
    ManaInspectFailure.malformedJson,
    'Expected non-empty $field.',
  );
}
