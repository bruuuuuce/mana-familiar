import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../safe_path.dart';

const inspectProjectSchema = 'mana.inspect.project/v1';
const inspectArtifactsSchema = 'mana.inspect.artifacts/v1';
const inspectArtifactSchema = 'mana.inspect.artifact/v1';
const inspectSourceSchema = 'mana.inspect.source/v1';
const inspectWorkItemsSchema = 'mana.inspect.work-items/v1';
const inspectWorkItemSchema = 'mana.inspect.work-item/v1';
const inspectProjectContextSchema = 'mana.inspect.project-context/v1';
const inspectActivitySchema = 'mana.inspect.activity/v1';

/// Negotiated from the producer's advertised operations; never inferred from
/// catalog paths or names.
enum ManaSemanticMode { fullSemantic, workSemantic, legacyCatalog }

enum ManaWorkItemType { feature, session, unknown }

enum ManaLifecycleState {
  notStarted,
  inProgress,
  completed,
  blocked,
  failed,
  stale,
  unknown,
}

enum ManaReviewState {
  notRequested,
  pending,
  approved,
  changesRequested,
  merged,
  closed,
  unknown,
}

enum ManaProvenance {
  explicitWorkspaceManifest,
  canonicalPath,
  conservativeFallback,
  unavailable,
  unknown,
}

enum ManaSectionId {
  overview,
  requirements,
  plan,
  decisions,
  evidence,
  review,
  timeline,
  artifacts,
}

enum ManaActivityKind {
  workspaceCreated,
  verificationCompleted,
  reviewRecorded,
  decisionRecorded,
  artifactUpdated,
  unknown,
}

enum ManaTimestampProvenance {
  explicitDomainTimestamp,
  filesystemMtimeEpoch,
  unknown,
}

class ManaSemanticField {
  const ManaSemanticField({required this.value, required this.provenance});
  final String? value;
  final ManaProvenance provenance;
  factory ManaSemanticField.fromJson(Map<String, dynamic> json) =>
      ManaSemanticField(
        value: json['value'] is String ? json['value'] as String : null,
        provenance: _provenance(json['provenance']),
      );
}

class ManaArtifactReference {
  const ManaArtifactReference({
    required this.id,
    required this.path,
    required this.kind,
    required this.status,
    required this.workItemId,
    required this.sectionId,
    this.label,
  });
  final String id, path, kind, status;
  final String? workItemId, label;
  final ManaSectionId? sectionId;
  factory ManaArtifactReference.fromJson(Map<String, dynamic> json) {
    final path = _string(json['path'], 'path');
    if (!path.startsWith('.mana/') ||
        !SafePathPolicy.isSafeRelativePath(path)) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Artifact references must use safe .mana-relative paths.',
      );
    }
    final workItemId = json['work_item_id'];
    if (workItemId != null &&
        (workItemId is! String || !_isWorkItemId(workItemId))) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Artifact work_item_id is malformed.',
      );
    }
    final sectionValue = json['section_id'];
    return ManaArtifactReference(
      id: _string(json['artifact_id'], 'artifact_id'),
      path: path,
      kind: _string(json['kind'], 'kind'),
      status: _string(json['status'], 'status'),
      workItemId: workItemId as String?,
      sectionId: sectionValue == null ? null : _requiredSection(sectionValue),
      label: json['label'] is String ? json['label'] as String : null,
    );
  }
}

class ManaLifecycle {
  const ManaLifecycle(this.state, this.provenance, this.coverage);
  final ManaLifecycleState state;
  final ManaProvenance provenance;
  final String coverage;
  factory ManaLifecycle.fromJson(Map<String, dynamic> json) => ManaLifecycle(
    _lifecycle(json['state']),
    _provenance(json['provenance']),
    _string(json['coverage'], 'lifecycle.coverage'),
  );
}

class ManaReview {
  const ManaReview(this.state, this.provenance, this.coverage);
  final ManaReviewState state;
  final ManaProvenance provenance;
  final String coverage;
  factory ManaReview.fromJson(Map<String, dynamic> json) => ManaReview(
    _review(json['state']),
    _provenance(json['provenance']),
    _string(json['coverage'], 'review.coverage'),
  );
}

class ManaDiagnostic {
  const ManaDiagnostic({
    required this.id,
    required this.kind,
    required this.severity,
    required this.provenance,
    required this.relatedArtifactIds,
  });
  final String id, kind, severity;
  final ManaProvenance provenance;
  final List<String> relatedArtifactIds;
  factory ManaDiagnostic.fromJson(Map<String, dynamic> json) => ManaDiagnostic(
    id: _string(json['id'], 'diagnostic.id'),
    kind: _unknownString(json['kind']),
    severity: _unknownString(json['severity']),
    provenance: _provenance(json['provenance']),
    relatedArtifactIds: _strings(json['related_artifact_ids']),
  );
}

class ManaAttentionItem {
  const ManaAttentionItem({
    required this.id,
    required this.category,
    required this.severity,
    required this.workItemId,
    required this.relatedArtifactIds,
    required this.provenance,
    this.label,
    this.nextAction,
  });
  final String id, category, severity, workItemId;
  final List<String> relatedArtifactIds;
  final ManaProvenance provenance;
  final String? label, nextAction;
  factory ManaAttentionItem.fromJson(Map<String, dynamic> json) =>
      ManaAttentionItem(
        id: _string(json['id'], 'attention.id'),
        category: _unknownString(json['category']),
        severity: _unknownString(json['severity']),
        workItemId: _string(json['work_item_id'], 'attention.work_item_id'),
        relatedArtifactIds: _strings(json['related_artifact_ids']),
        provenance: _provenance(json['provenance']),
        label: json['label'] is String ? json['label'] as String : null,
        nextAction: json['next_action'] is String
            ? json['next_action'] as String
            : null,
      );
}

class ManaWorkItemSummary {
  const ManaWorkItemSummary({
    required this.id,
    required this.type,
    required this.externalTicketId,
    required this.title,
    required this.purpose,
    required this.branch,
    required this.canonicalBranch,
    required this.lifecycle,
    required this.review,
    required this.attentionItems,
    required this.artifacts,
  });
  final String id;
  final ManaWorkItemType type;
  final ManaSemanticField externalTicketId, title, purpose, branch;
  final bool? canonicalBranch;
  final ManaLifecycle lifecycle;
  final ManaReview review;
  final List<ManaAttentionItem> attentionItems;
  final List<ManaArtifactReference> artifacts;
  factory ManaWorkItemSummary.fromJson(Map<String, dynamic> json) {
    final id = _string(json['work_item_id'], 'work_item_id');
    if (!_isWorkItemId(id)) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'work_item_id is not a stable feature/session identity.',
      );
    }
    final attentionItems = _objects(
      json['attention_items'],
    ).map(ManaAttentionItem.fromJson).toList(growable: false);
    final artifacts = _objects(
      json['artifacts'],
    ).map(ManaArtifactReference.fromJson).toList(growable: false);
    if (attentionItems.any((item) => item.workItemId != id) ||
        artifacts.any((artifact) => artifact.workItemId != id)) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Work-item summary ownership is inconsistent.',
      );
    }
    return ManaWorkItemSummary(
      id: id,
      type: _workType(json['work_item_type']),
      externalTicketId: ManaSemanticField.fromJson(
        _map(json['external_ticket_id']),
      ),
      title: ManaSemanticField.fromJson(_map(json['title'])),
      purpose: ManaSemanticField.fromJson(_map(json['purpose'])),
      branch: ManaSemanticField.fromJson(_map(json['branch'])),
      canonicalBranch: json['canonical_branch'] is bool
          ? json['canonical_branch'] as bool
          : null,
      lifecycle: ManaLifecycle.fromJson(_map(json['lifecycle'])),
      review: ManaReview.fromJson(_map(json['review'])),
      attentionItems: attentionItems,
      artifacts: artifacts,
    );
  }
}

class ManaWorkItemsResponse {
  const ManaWorkItemsResponse({
    required this.workItems,
    required this.coverage,
    required this.diagnostics,
  });
  final List<ManaWorkItemSummary> workItems;
  final String coverage;
  final List<ManaDiagnostic> diagnostics;
  factory ManaWorkItemsResponse.fromJson(Map<String, dynamic> json) {
    _requireSchema(json, inspectWorkItemsSchema);
    final workItems = _objects(
      json['work_items'],
    ).map(ManaWorkItemSummary.fromJson).toList(growable: false);
    _requireUnique(workItems.map((item) => item.id), 'work_item_id');
    return ManaWorkItemsResponse(
      workItems: workItems,
      coverage: _string(json['coverage'], 'coverage'),
      diagnostics: _objects(
        json['diagnostics'],
      ).map(ManaDiagnostic.fromJson).toList(growable: false),
    );
  }
}

class ManaWorkItemSection {
  const ManaWorkItemSection({
    required this.id,
    required this.artifacts,
    this.summary,
  });
  final ManaSectionId id;
  final List<ManaArtifactReference> artifacts;
  final Map<String, dynamic>? summary;
  factory ManaWorkItemSection.fromJson(Map<String, dynamic> json) =>
      ManaWorkItemSection(
        id: _requiredSection(json['section_id']),
        artifacts: _objects(
          json['artifacts'],
        ).map(ManaArtifactReference.fromJson).toList(growable: false),
        summary: json['summary'] is Map
            ? (json['summary'] as Map).cast<String, dynamic>()
            : null,
      );
}

class ManaWorkItemResponse {
  const ManaWorkItemResponse({
    required this.workItem,
    required this.sections,
    required this.attentionItems,
    required this.coverage,
    required this.diagnostics,
  });
  final ManaWorkItemSummary workItem;
  final List<ManaWorkItemSection> sections;
  final List<ManaAttentionItem> attentionItems;
  final String coverage;
  final List<ManaDiagnostic> diagnostics;
  factory ManaWorkItemResponse.fromJson(Map<String, dynamic> json) {
    _requireSchema(json, inspectWorkItemSchema);
    final workItem = ManaWorkItemSummary.fromJson(_map(json['work_item']));
    final sections = _objects(
      json['sections'],
    ).map(ManaWorkItemSection.fromJson).toList(growable: false);
    _requireUniqueSections(sections);
    for (final section in sections) {
      if (section.artifacts.any(
        (artifact) =>
            artifact.workItemId != workItem.id ||
            artifact.sectionId != section.id,
      )) {
        throw const ManaInspectException(
          ManaInspectFailure.malformedJson,
          'Section artifact ownership is inconsistent.',
        );
      }
    }
    final attentionItems = _objects(
      json['attention_items'],
    ).map(ManaAttentionItem.fromJson).toList(growable: false);
    if (attentionItems.any((item) => item.workItemId != workItem.id)) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Work-item attention ownership is inconsistent.',
      );
    }
    return ManaWorkItemResponse(
      workItem: workItem,
      sections: sections,
      attentionItems: attentionItems,
      coverage: _string(json['coverage'], 'coverage'),
      diagnostics: _objects(
        json['diagnostics'],
      ).map(ManaDiagnostic.fromJson).toList(growable: false),
    );
  }
}

class ManaProjectContextCategory {
  const ManaProjectContextCategory({
    required this.category,
    required this.artifacts,
    required this.coverage,
  });
  final String category, coverage;
  final List<ManaArtifactReference> artifacts;
  factory ManaProjectContextCategory.fromJson(Map<String, dynamic> json) =>
      ManaProjectContextCategory(
        category: _unknownString(json['category']),
        artifacts: _objects(
          json['artifacts'],
        ).map(ManaArtifactReference.fromJson).toList(growable: false),
        coverage: _string(json['coverage'], 'category.coverage'),
      );
}

class ManaProjectContextResponse {
  const ManaProjectContextResponse({
    required this.categories,
    required this.coverage,
    required this.diagnostics,
  });
  final List<ManaProjectContextCategory> categories;
  final String coverage;
  final List<ManaDiagnostic> diagnostics;
  factory ManaProjectContextResponse.fromJson(Map<String, dynamic> json) {
    _requireSchema(json, inspectProjectContextSchema);
    final categories = _objects(
      json['categories'],
    ).map(ManaProjectContextCategory.fromJson).toList(growable: false);
    _requireExactCategories(categories);
    if (categories.any(
      (category) => category.artifacts.any(
        (artifact) => artifact.workItemId != null || artifact.sectionId != null,
      ),
    )) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Project-context artifacts must remain project-global.',
      );
    }
    return ManaProjectContextResponse(
      categories: categories,
      coverage: _string(json['coverage'], 'coverage'),
      diagnostics: _objects(
        json['diagnostics'],
      ).map(ManaDiagnostic.fromJson).toList(growable: false),
    );
  }
}

class ManaActivityEvent {
  const ManaActivityEvent({
    required this.id,
    required this.timestamp,
    required this.timestampProvenance,
    required this.kind,
    required this.workItemId,
    required this.relatedArtifactIds,
    required this.provenance,
    this.target,
    this.summary,
  });
  final String id, timestamp;
  final ManaTimestampProvenance timestampProvenance;
  final ManaProvenance provenance;
  final ManaActivityKind kind;
  final String? workItemId, summary;
  final List<String> relatedArtifactIds;
  final ManaActivityTarget? target;
  factory ManaActivityEvent.fromJson(Map<String, dynamic> json) {
    final timestamp = _map(json['timestamp']);
    final workItemId = json['work_item_id'];
    if (workItemId != null &&
        (workItemId is! String || !_isWorkItemId(workItemId))) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Activity work_item_id is malformed.',
      );
    }
    return ManaActivityEvent(
      id: _string(json['event_id'], 'event_id'),
      timestamp: _string(timestamp['value'], 'timestamp.value'),
      timestampProvenance: _timestampProvenance(timestamp['provenance']),
      kind: _activityKind(json['event_kind']),
      workItemId: workItemId as String?,
      relatedArtifactIds: _strings(json['related_artifact_ids']),
      target: json['target'] == null
          ? null
          : ManaActivityTarget.fromJson(_map(json['target'])),
      summary: json['summary'] is String ? json['summary'] as String : null,
      provenance: _provenance(json['provenance']),
    );
  }
}

class ManaActivityTarget {
  const ManaActivityTarget({
    required this.artifactId,
    required this.workItemId,
    required this.sectionId,
    required this.projectContextCategory,
    required this.label,
  });

  final String artifactId;
  final String? workItemId;
  final ManaSectionId? sectionId;
  final String? projectContextCategory;
  final String? label;

  factory ManaActivityTarget.fromJson(Map<String, dynamic> json) {
    for (final field in const [
      'artifact_id',
      'work_item_id',
      'section_id',
      'project_context_category',
      'label',
    ]) {
      if (!json.containsKey(field)) {
        throw const ManaInspectException(
          ManaInspectFailure.malformedJson,
          'Activity target is missing a required field.',
        );
      }
    }
    final workItemId = json['work_item_id'];
    if (workItemId != null &&
        (workItemId is! String || !_isWorkItemId(workItemId))) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Activity target work_item_id is malformed.',
      );
    }
    final category = json['project_context_category'];
    if (category != null &&
        (category is! String ||
            !_projectContextCategories.contains(category))) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Activity target project_context_category is malformed.',
      );
    }
    final label = json['label'];
    if (label != null &&
        (label is! String ||
            label.isEmpty ||
            utf8.encode(label).length > 256)) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Activity target label is malformed.',
      );
    }
    final section = json['section_id'];
    return ManaActivityTarget(
      artifactId: _string(json['artifact_id'], 'target.artifact_id'),
      workItemId: workItemId as String?,
      sectionId: section == null ? null : _requiredSection(section),
      projectContextCategory: category as String?,
      label: label as String?,
    );
  }
}

class ManaActivityResponse {
  const ManaActivityResponse({
    required this.events,
    required this.coverage,
    required this.diagnostics,
  });
  final List<ManaActivityEvent> events;
  final String coverage;
  final List<ManaDiagnostic> diagnostics;
  factory ManaActivityResponse.fromJson(Map<String, dynamic> json) {
    _requireSchema(json, inspectActivitySchema);
    final events = _objects(
      json['events'],
    ).map(ManaActivityEvent.fromJson).toList(growable: false);
    _requireUnique(events.map((event) => event.id), 'event_id');
    return ManaActivityResponse(
      events: events,
      coverage: _string(json['coverage'], 'coverage'),
      diagnostics: _objects(
        json['diagnostics'],
      ).map(ManaDiagnostic.fromJson).toList(growable: false),
    );
  }
}

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

  ManaSemanticMode get semanticMode {
    final work =
        supports('work-items', inspectWorkItemsSchema) &&
        supports('work-item', inspectWorkItemSchema);
    if (!work) return ManaSemanticMode.legacyCatalog;
    final context = supports('project-context', inspectProjectContextSchema);
    final activity = supports('activity', inspectActivitySchema);
    return context && activity
        ? ManaSemanticMode.fullSemantic
        : ManaSemanticMode.workSemantic;
  }

  bool get supportsWorkItems => supports('work-items', inspectWorkItemsSchema);
  bool get supportsWorkItem => supports('work-item', inspectWorkItemSchema);
  bool get supportsProjectContext =>
      supports('project-context', inspectProjectContextSchema);
  bool get supportsActivity => supports('activity', inspectActivitySchema);

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
  factory ManaInspectArtifactSummary.fromJson(Map<String, dynamic> json) {
    final path = _string(json['path'], 'path');
    if (!path.startsWith('.mana/') ||
        !SafePathPolicy.isSafeRelativePath(path)) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Artifact summaries must use safe .mana-relative paths.',
      );
    }
    return ManaInspectArtifactSummary(
      id: _string(json['artifact_id'], 'artifact_id'),
      path: path,
      family: _string(json['family'], 'family'),
      kind: _string(json['kind'], 'kind'),
      status: _string(json['status'], 'status'),
      raw: json,
    );
  }
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
    final path = _string(source['path'], 'source.path');
    if (!SafePathPolicy.isSafeRelativePath(path) || path.startsWith('.mana/')) {
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Source response path is not safe and project-relative.',
      );
    }
    return ManaInspectSourceRelations(
      path: path,
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
    this.processTimeout = const Duration(seconds: 30),
    ManaProcessRunner? run,
  }) : _run =
           run ??
           ((executable, arguments, {workingDirectory}) => _runInspectProcess(
             executable,
             arguments,
             workingDirectory: workingDirectory,
             timeout: processTimeout,
           ));

  final String projectRoot;
  final String? manaRoot;
  final String? snapshotPath;
  final Duration processTimeout;
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

  Future<ManaInspectCatalog> catalog({ManaInspectProject? capabilities}) async {
    if (snapshotPath != null) {
      return ManaInspectCatalog.fromJson(await _response('artifacts'));
    }
    final projectInfo = capabilities ?? await project();
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

  Future<ManaWorkItemsResponse> workItems({
    ManaInspectProject? capabilities,
  }) async {
    final projectInfo = capabilities ?? await project();
    _requireOperation(projectInfo, 'work-items', inspectWorkItemsSchema);
    return ManaWorkItemsResponse.fromJson(await _response('work-items'));
  }

  Future<ManaWorkItemResponse> workItem(
    String id, {
    ManaInspectProject? capabilities,
  }) async {
    if (!RegExp(
      r'^(feature|session):[A-Za-z0-9][A-Za-z0-9._-]*$',
    ).hasMatch(id)) {
      throw const ManaInspectException(
        ManaInspectFailure.missingProject,
        'Work item IDs must be exact feature:<workspace-id> or session:<workspace-id> values.',
      );
    }
    final projectInfo = capabilities ?? await project();
    _requireOperation(projectInfo, 'work-item', inspectWorkItemSchema);
    return ManaWorkItemResponse.fromJson(
      await _response('work-item', target: id),
    );
  }

  Future<ManaProjectContextResponse> projectContext({
    ManaInspectProject? capabilities,
  }) async {
    final projectInfo = capabilities ?? await project();
    _requireOperation(
      projectInfo,
      'project-context',
      inspectProjectContextSchema,
    );
    return ManaProjectContextResponse.fromJson(
      await _response('project-context'),
    );
  }

  Future<ManaActivityResponse> activity({
    ManaInspectProject? capabilities,
  }) async {
    final projectInfo = capabilities ?? await project();
    _requireOperation(projectInfo, 'activity', inspectActivitySchema);
    return ManaActivityResponse.fromJson(await _response('activity'));
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
        'Exit ${result.exitCode}: ${_safeProcessDiagnostic(result.stderr, projectRoot)}',
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
        'work-items' => inspectWorkItemsSchema,
        'work-item' => inspectWorkItemSchema,
        'project-context' => inspectProjectContextSchema,
        'activity' => inspectActivitySchema,
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

/// Application read model. It coordinates one negotiated refresh and keeps
/// optional semantic failures from discarding independently successful data.
class ManaSemanticReadModel {
  const ManaSemanticReadModel({
    required this.project,
    required this.mode,
    this.catalog,
    this.workItems,
    this.projectContext,
    this.activity,
    this.refreshError,
  });
  final ManaInspectProject project;
  final ManaSemanticMode mode;
  final ManaInspectCatalog? catalog;
  final ManaWorkItemsResponse? workItems;
  final ManaProjectContextResponse? projectContext;
  final ManaActivityResponse? activity;
  final Object? refreshError;
}

class ManaSemanticRepository {
  ManaSemanticRepository(this.client);
  final ManaInspectClient client;
  Future<ManaSemanticReadModel>? _refreshing;
  Future<ManaSemanticReadModel>? _catalogLoading;
  final Map<String, Future<ManaWorkItemResponse>> _details = {};
  ManaSemanticReadModel? _latest;

  /// Refreshes the semantic surfaces needed for the cockpit. The raw artifact
  /// catalog is deliberately optional because it is only rendered in Advanced
  /// and can be substantially more expensive than the overview data.
  Future<ManaSemanticReadModel> refresh({bool includeCatalog = true}) =>
      _refreshing ??= _refresh(
        includeCatalog: includeCatalog,
        includeProjectContext: true,
        includeActivity: true,
      ).whenComplete(() => _refreshing = null);

  /// Loads just enough data to render the initial cockpit. Context and activity
  /// are filled in afterwards, so their producer work cannot delay opening a
  /// project.
  Future<ManaSemanticReadModel> initialLoad() => _refreshing ??= _refresh(
    includeCatalog: false,
    includeProjectContext: false,
    includeActivity: false,
  ).whenComplete(() => _refreshing = null);

  /// Completes the non-critical semantic surfaces after the first frame.
  Future<ManaSemanticReadModel> loadSupportingSurfaces() async {
    final latest = _latest;
    if (latest == null) return refresh(includeCatalog: false);
    ManaProjectContextResponse? context = latest.projectContext;
    ManaActivityResponse? activity = latest.activity;
    Object? error = latest.refreshError;
    final tasks = <Future<void>>[];
    Future<void> optional(Future<void> task) async {
      try {
        await task;
      } catch (caught) {
        error ??= caught;
      }
    }

    if (context == null && latest.project.supportsProjectContext) {
      tasks.add(
        optional(
          client
              .projectContext(capabilities: latest.project)
              .then((value) => context = value),
        ),
      );
    }
    if (activity == null && latest.project.supportsActivity) {
      tasks.add(
        optional(
          client
              .activity(capabilities: latest.project)
              .then((value) => activity = value),
        ),
      );
    }
    await Future.wait(tasks);
    final current = _latest ?? latest;
    final model = ManaSemanticReadModel(
      project: current.project,
      mode: current.mode,
      catalog: current.catalog,
      workItems: current.workItems,
      projectContext: context ?? current.projectContext,
      activity: activity ?? current.activity,
      refreshError: error,
    );
    _latest = model;
    return model;
  }

  /// Loads the raw catalog on demand, retaining the already-rendered semantic
  /// model while the producer command runs.
  Future<ManaSemanticReadModel> loadCatalog() {
    final latest = _latest;
    if (latest == null) return refresh();
    if (latest.catalog != null) return Future.value(latest);
    if (!latest.project.supports('artifacts', inspectArtifactsSchema)) {
      return Future.value(latest);
    }
    return _catalogLoading ??= client
        .catalog(capabilities: latest.project)
        .then((catalog) {
          final current = _latest ?? latest;
          final model = ManaSemanticReadModel(
            project: current.project,
            mode: current.mode,
            catalog: catalog,
            workItems: current.workItems,
            projectContext: current.projectContext,
            activity: current.activity,
            refreshError: current.refreshError,
          );
          _latest = model;
          return model;
        })
        .whenComplete(() => _catalogLoading = null);
  }

  Future<ManaWorkItemResponse> workItem(
    String id,
    ManaInspectProject project,
  ) => _details.putIfAbsent(
    id,
    () => client.workItem(id, capabilities: project),
  );

  Future<ManaSemanticReadModel> _refresh({
    required bool includeCatalog,
    required bool includeProjectContext,
    required bool includeActivity,
  }) async {
    ManaInspectProject project;
    try {
      project = await client.project();
    } catch (error) {
      final previous = _latest;
      if (previous == null) rethrow;
      return ManaSemanticReadModel(
        project: previous.project,
        mode: previous.mode,
        catalog: previous.catalog,
        workItems: previous.workItems,
        projectContext: previous.projectContext,
        activity: previous.activity,
        refreshError: error,
      );
    }
    final previous = _latest;
    final mayRetain =
        previous != null &&
        previous.project.projectId == project.projectId &&
        previous.mode == project.semanticMode;
    ManaInspectCatalog? catalog;
    ManaWorkItemsResponse? workItems;
    ManaProjectContextResponse? context;
    ManaActivityResponse? activity;
    Object? error;
    final tasks = <Future<void>>[];
    Future<void> optional(Future<void> task) async {
      try {
        await task;
      } catch (e) {
        error ??= e;
      }
    }

    final needsCatalog =
        includeCatalog ||
        project.semanticMode == ManaSemanticMode.legacyCatalog;
    if (needsCatalog && project.supports('artifacts', inspectArtifactsSchema)) {
      tasks.add(
        optional(
          client
              .catalog(capabilities: project)
              .then((value) => catalog = value),
        ),
      );
    }
    if (project.supportsWorkItems) {
      tasks.add(
        optional(
          client
              .workItems(capabilities: project)
              .then((value) => workItems = value),
        ),
      );
    }
    if (includeProjectContext && project.supportsProjectContext) {
      tasks.add(
        optional(
          client
              .projectContext(capabilities: project)
              .then((value) => context = value),
        ),
      );
    }
    if (includeActivity && project.supportsActivity) {
      tasks.add(
        optional(
          client
              .activity(capabilities: project)
              .then((value) => activity = value),
        ),
      );
    }
    await Future.wait(tasks);
    final model = ManaSemanticReadModel(
      project: project,
      mode: project.semanticMode,
      catalog:
          catalog ??
          (mayRetain && project.supports('artifacts', inspectArtifactsSchema)
              ? previous.catalog
              : null),
      workItems:
          workItems ??
          (mayRetain && project.supportsWorkItems ? previous.workItems : null),
      projectContext:
          context ??
          (mayRetain && project.supportsProjectContext
              ? previous.projectContext
              : null),
      activity:
          activity ??
          (mayRetain && project.supportsActivity ? previous.activity : null),
      refreshError: error,
    );
    _latest = model;
    if (!mayRetain || workItems != null) _details.clear();
    return model;
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
    .map((value) {
      if (value is Map) return value.cast<String, dynamic>();
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Expected an object array entry.',
      );
    })
    .toList(growable: false);
String _string(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw ManaInspectException(
    ManaInspectFailure.malformedJson,
    'Expected non-empty $field.',
  );
}

String _unknownString(Object? value) =>
    value is String && value.isNotEmpty ? value : 'unknown';
List<String> _strings(Object? value) => _list(value)
    .map((value) {
      if (value is String) return value;
      throw const ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Expected a string array entry.',
      );
    })
    .toList(growable: false);

bool _isWorkItemId(String value) =>
    RegExp(r'^(feature|session):[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value);

void _requireUnique(Iterable<String> values, String field) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      throw ManaInspectException(
        ManaInspectFailure.malformedJson,
        'Duplicate $field.',
      );
    }
  }
}

void _requireUniqueSections(List<ManaWorkItemSection> sections) {
  final actual = sections.map((section) => section.id).toSet();
  if (actual.length != sections.length) {
    throw const ManaInspectException(
      ManaInspectFailure.malformedJson,
      'Work-item section_id values must be unique.',
    );
  }
}

const _projectContextCategories = <String>{
  'architecture',
  'project_decisions',
  'integrations',
  'engineering_guards',
  'glossary',
  'learning_journeys',
  'testing_policy',
  'database_policy',
};

void _requireExactCategories(List<ManaProjectContextCategory> categories) {
  final actual = categories.map((category) => category.category).toSet();
  if (actual.length != categories.length ||
      actual.length != _projectContextCategories.length ||
      !actual.containsAll(_projectContextCategories)) {
    throw const ManaInspectException(
      ManaInspectFailure.malformedJson,
      'Project context must contain each frozen category exactly once.',
    );
  }
}

String _safeProcessDiagnostic(Object? stderr, String projectRoot) {
  var text = stderr.toString().replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ');
  final roots = <String>{projectRoot};
  try {
    roots.add(Directory(projectRoot).absolute.path);
  } on FileSystemException {
    // The user-facing diagnostic remains bounded even for a missing root.
  }
  for (final root in roots.where((value) => value.isNotEmpty)) {
    text = text.replaceAll(root, '<project>');
  }
  text = text.replaceAllMapped(
    RegExp(r'(^|\s)/(?:[^/\s:]+/)*[^/\s:]+'),
    (match) => '${match.group(1)}<host-path>',
  );
  text = text.trim();
  if (text.isEmpty) return 'inspect command failed';
  const limit = 512;
  return text.length <= limit ? text : '${text.substring(0, limit)}…';
}

Future<ProcessResult> _runInspectProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  required Duration timeout,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
  );
  final stdout = _collectBounded(process.stdout, 16 * 1024 * 1024);
  final stderr = _collectBounded(process.stderr, 8 * 1024);
  int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await stdout;
    await stderr;
    throw ProcessException(
      executable,
      arguments,
      'Inspect process exceeded its ${timeout.inSeconds}-second limit.',
    );
  }
  final output = await stdout;
  final errors = await stderr;
  if (output.truncated) {
    throw ProcessException(
      executable,
      arguments,
      'Inspect response exceeded the 16 MiB transport limit.',
    );
  }
  return ProcessResult(
    process.pid,
    exitCode,
    output.text,
    '${errors.text}${errors.truncated ? '…' : ''}',
  );
}

Future<({String text, bool truncated})> _collectBounded(
  Stream<List<int>> stream,
  int limit,
) async {
  final bytes = BytesBuilder(copy: false);
  var retained = 0;
  var truncated = false;
  await for (final chunk in stream) {
    final available = limit - retained;
    if (available > 0) {
      final take = chunk.length < available ? chunk.length : available;
      bytes.add(chunk.take(take).toList(growable: false));
      retained += take;
    }
    if (chunk.length > available) truncated = true;
  }
  return (
    text: utf8.decode(bytes.takeBytes(), allowMalformed: true),
    truncated: truncated,
  );
}

ManaProvenance _provenance(Object? value) => switch (value) {
  'explicit_workspace_manifest' => ManaProvenance.explicitWorkspaceManifest,
  'canonical_path' => ManaProvenance.canonicalPath,
  'conservative_fallback' => ManaProvenance.conservativeFallback,
  'unavailable' => ManaProvenance.unavailable,
  _ => ManaProvenance.unknown,
};
ManaWorkItemType _workType(Object? value) => switch (value) {
  'feature' => ManaWorkItemType.feature,
  'session' => ManaWorkItemType.session,
  _ => ManaWorkItemType.unknown,
};
ManaLifecycleState _lifecycle(Object? value) => switch (value) {
  'not_started' => ManaLifecycleState.notStarted,
  'in_progress' => ManaLifecycleState.inProgress,
  'completed' => ManaLifecycleState.completed,
  'blocked' => ManaLifecycleState.blocked,
  'failed' => ManaLifecycleState.failed,
  'stale' => ManaLifecycleState.stale,
  _ => ManaLifecycleState.unknown,
};
ManaReviewState _review(Object? value) => switch (value) {
  'not_requested' => ManaReviewState.notRequested,
  'pending' => ManaReviewState.pending,
  'approved' => ManaReviewState.approved,
  'changes_requested' => ManaReviewState.changesRequested,
  'merged' => ManaReviewState.merged,
  'closed' => ManaReviewState.closed,
  _ => ManaReviewState.unknown,
};
ManaSectionId? _section(Object? value) => switch (value) {
  'overview' => ManaSectionId.overview,
  'requirements' => ManaSectionId.requirements,
  'plan' => ManaSectionId.plan,
  'decisions' => ManaSectionId.decisions,
  'evidence' => ManaSectionId.evidence,
  'review' => ManaSectionId.review,
  'timeline' => ManaSectionId.timeline,
  'artifacts' => ManaSectionId.artifacts,
  _ => null,
};
ManaSectionId _requiredSection(Object? value) =>
    _section(value) ??
    (throw const ManaInspectException(
      ManaInspectFailure.malformedJson,
      'Unknown or missing section_id.',
    ));
ManaActivityKind _activityKind(Object? value) => switch (value) {
  'workspace_created' => ManaActivityKind.workspaceCreated,
  'verification_completed' => ManaActivityKind.verificationCompleted,
  'review_recorded' => ManaActivityKind.reviewRecorded,
  'decision_recorded' => ManaActivityKind.decisionRecorded,
  'artifact_updated' => ManaActivityKind.artifactUpdated,
  _ => ManaActivityKind.unknown,
};
ManaTimestampProvenance _timestampProvenance(Object? value) => switch (value) {
  'explicit_domain_timestamp' =>
    ManaTimestampProvenance.explicitDomainTimestamp,
  'filesystem_mtime_epoch' => ManaTimestampProvenance.filesystemMtimeEpoch,
  _ => ManaTimestampProvenance.unknown,
};
