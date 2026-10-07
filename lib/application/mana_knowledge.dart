// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:io';

import 'mana_process.dart';

import 'mana_inspect.dart';

const manaKnowledgeCapabilitiesSchema = 'mana.knowledge.capabilities/v1';
const manaKnowledgeDocumentsSchema = 'mana.knowledge.documents/v1';
const manaKnowledgeDocumentSchema = 'mana.knowledge.document/v1';
const manaKnowledgeSearchSchema = 'mana.knowledge.search/v1';
const manaKnowledgePassageSchema = 'mana.knowledge.passage/v1';
const manaLearningQueueSchema = 'mana.learning.review-queue/v1';
const manaActionReceiptSchema = 'mana.action.receipt/v1';

class ManaKnowledgeException implements Exception {
  const ManaKnowledgeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ManaKnowledgeIndex {
  const ManaKnowledgeIndex(this.freshness, this.reason, this.revision);
  final String freshness;
  final String? reason;
  final String? revision;
  factory ManaKnowledgeIndex.fromJson(Map<String, dynamic> json) =>
      ManaKnowledgeIndex(
        _requiredString(json['freshness'], 'index.freshness'),
        _optionalString(json['reason']),
        _optionalString(json['revision']),
      );
}

class ManaKnowledgeScope {
  const ManaKnowledgeScope({
    required this.scope,
    required this.health,
    required this.editable,
    this.reason,
    this.sourceDisclosure,
  });
  final String scope;
  final String health;
  final bool editable;
  final String? reason;
  final String? sourceDisclosure;
  factory ManaKnowledgeScope.fromJson(Map<String, dynamic> json) =>
      ManaKnowledgeScope(
        scope: _requiredString(json['scope'], 'scope'),
        health: _requiredString(json['health'], 'health'),
        editable: _requiredBool(json['editable'], 'editable'),
        reason: _optionalString(json['reason']),
        sourceDisclosure: _optionalString(json['source_disclosure']),
      );
}

class ManaKnowledgeCapabilities {
  const ManaKnowledgeCapabilities({
    required this.index,
    required this.scopes,
    required this.operations,
    required this.effectiveContextStatus,
  });
  final ManaKnowledgeIndex index;
  final List<ManaKnowledgeScope> scopes;
  final List<String> operations;
  final String effectiveContextStatus;
  factory ManaKnowledgeCapabilities.fromJson(Map<String, dynamic> json) {
    _schema(json, manaKnowledgeCapabilitiesSchema);
    final trace = _map(
      json['effective_context_trace'],
      'effective_context_trace',
    );
    return ManaKnowledgeCapabilities(
      index: ManaKnowledgeIndex.fromJson(_map(json['index'], 'index')),
      scopes: _maps(
        json['scopes'],
        'scopes',
      ).map(ManaKnowledgeScope.fromJson).toList(growable: false),
      operations: _strings(json['operations'], 'operations'),
      effectiveContextStatus: _requiredString(trace['status'], 'trace.status'),
    );
  }
}

class ManaKnowledgeDocumentSummary {
  const ManaKnowledgeDocumentSummary({
    required this.id,
    required this.reference,
    required this.scope,
    required this.lifecycle,
    required this.revision,
    required this.byteSize,
    this.title,
  });
  final String id;
  final String reference;
  final String scope;
  final String lifecycle;
  final String revision;
  final int byteSize;
  final String? title;
  factory ManaKnowledgeDocumentSummary.fromJson(Map<String, dynamic> json) {
    final reference = _requiredString(
      json['source_reference'],
      'source_reference',
    );
    if (!_safeReference(reference)) {
      throw const ManaKnowledgeException(
        'Knowledge source reference is unsafe.',
      );
    }
    return ManaKnowledgeDocumentSummary(
      id: _id(json['document_id'], r'^doc_[0-9a-f]{24}$', 'document_id'),
      reference: reference,
      scope: _requiredString(json['source_scope'], 'source_scope'),
      lifecycle: _requiredString(json['lifecycle_state'], 'lifecycle_state'),
      revision: _revision(json['document_revision'], 'document_revision'),
      byteSize: _nonNegativeInt(json['byte_size'], 'byte_size'),
      title: _optionalString(json['title']),
    );
  }
}

class ManaKnowledgePassage {
  const ManaKnowledgePassage({
    required this.id,
    required this.body,
    required this.headingPath,
    required this.revision,
    required this.truncated,
  });
  final String id;
  final String body;
  final List<String> headingPath;
  final String revision;
  final bool truncated;
  factory ManaKnowledgePassage.fromJson(Map<String, dynamic> json) =>
      ManaKnowledgePassage(
        id: _id(json['passage_id'], r'^psg_[0-9a-f]{24}$', 'passage_id'),
        body: _requiredString(json['body'], 'body', allowEmpty: true),
        headingPath: _strings(json['heading_path'], 'heading_path'),
        revision: _revision(json['passage_revision'], 'passage_revision'),
        truncated: _requiredBool(json['truncated'], 'truncated'),
      );
}

class ManaKnowledgeDocument {
  const ManaKnowledgeDocument({
    required this.summary,
    required this.passages,
    required this.returnedBytes,
    required this.truncated,
    required this.editable,
    this.exactContent,
    this.expectedRevision,
    this.editTarget,
    this.sourceDisclosure,
  });
  final ManaKnowledgeDocumentSummary summary;
  final List<ManaKnowledgePassage> passages;
  final int returnedBytes;
  final bool truncated;
  final bool editable;
  final String? exactContent;
  final String? expectedRevision;
  final String? editTarget;
  final String? sourceDisclosure;
  factory ManaKnowledgeDocument.fromJson(Map<String, dynamic> json) {
    final edit = _map(json['edit_capability'], 'edit_capability');
    final editable = _requiredBool(edit['available'], 'edit.available');
    final summary = ManaKnowledgeDocumentSummary.fromJson(json);
    final exact = _optionalString(edit['exact_content'], allowEmpty: true);
    final expected = edit['expected_revision'] == null
        ? null
        : _revision(edit['expected_revision'], 'edit.expected_revision');
    final target = _optionalString(edit['target']);
    final disclosure = _optionalString(edit['source_disclosure']);
    final targetValid =
        target != null &&
        (summary.scope == 'project'
            ? target.startsWith('.mana/global/') && _safeReference(target)
            : summary.scope == 'user' && _safeRelativeTarget(target));
    final disclosureValid =
        summary.scope != 'user' ||
        (disclosure != null && _isAbsolutePath(disclosure));
    if (editable &&
        (exact == null ||
            expected != summary.revision ||
            !targetValid ||
            !disclosureValid)) {
      throw const ManaKnowledgeException(
        'Editable document metadata is inconsistent.',
      );
    }
    return ManaKnowledgeDocument(
      summary: summary,
      passages: _maps(
        json['passages'],
        'passages',
      ).map(ManaKnowledgePassage.fromJson).toList(growable: false),
      returnedBytes: _nonNegativeInt(json['returned_bytes'], 'returned_bytes'),
      truncated: _requiredBool(json['truncated'], 'truncated'),
      editable: editable,
      exactContent: exact,
      expectedRevision: expected,
      editTarget: target,
      sourceDisclosure: disclosure,
    );
  }
}

class ManaKnowledgeDocuments {
  const ManaKnowledgeDocuments(this.index, this.documents, this.nextOffset);
  final ManaKnowledgeIndex index;
  final List<ManaKnowledgeDocumentSummary> documents;
  final int? nextOffset;
  factory ManaKnowledgeDocuments.fromJson(Map<String, dynamic> json) {
    _schema(json, manaKnowledgeDocumentsSchema);
    return ManaKnowledgeDocuments(
      ManaKnowledgeIndex.fromJson(_map(json['index'], 'index')),
      _maps(
        json['documents'],
        'documents',
      ).map(ManaKnowledgeDocumentSummary.fromJson).toList(growable: false),
      json['next_offset'] == null
          ? null
          : _nonNegativeInt(json['next_offset'], 'next_offset'),
    );
  }
}

class ManaKnowledgeDocumentResponse {
  const ManaKnowledgeDocumentResponse(this.index, this.document);
  final ManaKnowledgeIndex index;
  final ManaKnowledgeDocument? document;
  factory ManaKnowledgeDocumentResponse.fromJson(Map<String, dynamic> json) {
    _schema(json, manaKnowledgeDocumentSchema);
    return ManaKnowledgeDocumentResponse(
      ManaKnowledgeIndex.fromJson(_map(json['index'], 'index')),
      json['document'] == null
          ? null
          : ManaKnowledgeDocument.fromJson(_map(json['document'], 'document')),
    );
  }
}

class ManaKnowledgeSearchResult {
  const ManaKnowledgeSearchResult({
    required this.passageId,
    required this.documentId,
    required this.scope,
    required this.lifecycle,
    required this.reference,
    required this.revision,
    this.title,
    this.snippet,
    this.documentRevision,
    this.headingPath = const [],
  });
  final String passageId;
  final String documentId;
  final String scope;
  final String lifecycle;
  final String reference;
  final String revision;
  final String? title;
  final String? snippet;
  final String? documentRevision;
  final List<String> headingPath;
  factory ManaKnowledgeSearchResult.fromJson(Map<String, dynamic> json) {
    final reference = _requiredString(
      json['source_reference'],
      'source_reference',
    );
    if (!_safeReference(reference)) {
      throw const ManaKnowledgeException(
        'Knowledge search reference is unsafe.',
      );
    }
    return ManaKnowledgeSearchResult(
      passageId: _id(json['passage_id'], r'^psg_[0-9a-f]{24}$', 'passage_id'),
      documentId: _id(
        json['document_id'],
        r'^doc_[0-9a-f]{24}$',
        'document_id',
      ),
      scope: _requiredString(json['source_scope'], 'source_scope'),
      lifecycle: _requiredString(json['lifecycle_state'], 'lifecycle_state'),
      reference: reference,
      revision: _revision(json['passage_revision'], 'passage_revision'),
      title: _optionalString(json['title']),
      snippet: _optionalString(json['snippet'], allowEmpty: true),
      documentRevision: json['document_revision'] == null
          ? null
          : _revision(json['document_revision'], 'document_revision'),
      headingPath: json['heading_path'] == null
          ? const []
          : _strings(json['heading_path'], 'heading_path'),
    );
  }
}

class ManaKnowledgeSearch {
  const ManaKnowledgeSearch(this.index, this.results, this.returnedBytes);
  final ManaKnowledgeIndex index;
  final List<ManaKnowledgeSearchResult> results;
  final int returnedBytes;
  factory ManaKnowledgeSearch.fromJson(Map<String, dynamic> json) {
    _schema(json, manaKnowledgeSearchSchema);
    return ManaKnowledgeSearch(
      ManaKnowledgeIndex.fromJson(_map(json['index'], 'index')),
      _maps(
        json['results'],
        'results',
      ).map(ManaKnowledgeSearchResult.fromJson).toList(growable: false),
      _nonNegativeInt(json['returned_bytes'], 'returned_bytes'),
    );
  }
}

class ManaKnowledgePassageResponse {
  const ManaKnowledgePassageResponse(
    this.index,
    this.documentId,
    this.documentRevision,
    this.passage,
  );
  final ManaKnowledgeIndex index;
  final String documentId;
  final String documentRevision;
  final ManaKnowledgePassage passage;

  factory ManaKnowledgePassageResponse.fromJson(Map<String, dynamic> json) {
    _schema(json, manaKnowledgePassageSchema);
    final value = _map(json['passage'], 'passage');
    if (!_safeReference(
      _requiredString(value['source_reference'], 'source_reference'),
    )) {
      throw const ManaKnowledgeException(
        'Knowledge passage source reference is unsafe.',
      );
    }
    return ManaKnowledgePassageResponse(
      ManaKnowledgeIndex.fromJson(_map(json['index'], 'index')),
      _id(value['document_id'], r'^doc_[0-9a-f]{24}$', 'document_id'),
      _revision(value['document_revision'], 'document_revision'),
      ManaKnowledgePassage.fromJson(value),
    );
  }
}

class ManaLearningCandidate {
  const ManaLearningCandidate({
    required this.id,
    required this.sourceScope,
    required this.revision,
    required this.status,
    required this.evidence,
    required this.promotionEligible,
    required this.promoted,
    this.proposal,
    this.counterEvidence,
    this.limitations,
    this.targetScope,
    this.reviewId,
    this.reviewRevision,
  });
  final String id;
  final String sourceScope;
  final String revision;
  final String status;
  final List<Object?> evidence;
  final bool promotionEligible;
  final bool promoted;
  final String? proposal;
  final Object? counterEvidence;
  final Object? limitations;
  final String? targetScope;
  final String? reviewId;
  final String? reviewRevision;
  factory ManaLearningCandidate.fromJson(Map<String, dynamic> json) {
    final scope = _requiredString(json['source_scope'], 'source_scope');
    final id = _requiredString(json['candidate_id'], 'candidate_id');
    final valid = scope == 'project'
        ? RegExp(r'^learning-[0-9a-f]{8}$').hasMatch(id)
        : scope == 'user' &&
              RegExp(r'^user-context-candidate-[0-9a-f]{64}$').hasMatch(id);
    if (!valid)
      throw const ManaKnowledgeException('Candidate identity is invalid.');
    final evidence = json['evidence'];
    if (evidence is! List) {
      throw const ManaKnowledgeException('Candidate evidence is invalid.');
    }
    return ManaLearningCandidate(
      id: id,
      sourceScope: scope,
      revision: _revision(json['revision'], 'revision'),
      status: _requiredString(json['status'], 'status'),
      proposal: _optionalString(json['proposal']),
      evidence: List<Object?>.unmodifiable(evidence),
      counterEvidence: json['counter_evidence'],
      limitations: json['limitations'],
      targetScope: _optionalString(json['target_scope']),
      reviewId: _optionalString(json['review_id']),
      reviewRevision: json['review_revision'] == null
          ? null
          : _revision(json['review_revision'], 'review_revision'),
      promotionEligible: _requiredBool(
        json['promotion_eligible'],
        'promotion_eligible',
      ),
      promoted: _requiredBool(json['promoted'], 'promoted'),
    );
  }
}

class ManaLearningQueue {
  const ManaLearningQueue(this.index, this.candidates);
  final ManaKnowledgeIndex index;
  final List<ManaLearningCandidate> candidates;
  factory ManaLearningQueue.fromJson(Map<String, dynamic> json) {
    _schema(json, manaLearningQueueSchema);
    return ManaLearningQueue(
      ManaKnowledgeIndex.fromJson(_map(json['index'], 'index')),
      _maps(
        json['candidates'],
        'candidates',
      ).map(ManaLearningCandidate.fromJson).toList(growable: false),
    );
  }
}

class ManaActionReceipt {
  const ManaActionReceipt({
    required this.actionId,
    required this.action,
    required this.outcome,
    required this.expectedRevision,
    this.afterRevision,
    this.proposalArtifact,
  });
  final String actionId;
  final String action;
  final String outcome;
  final String expectedRevision;
  final String? afterRevision;
  final String? proposalArtifact;
  factory ManaActionReceipt.fromJson(Map<String, dynamic> json) {
    _schema(json, manaActionReceiptSchema);
    return ManaActionReceipt(
      actionId: _id(json['action_id'], r'^act_[0-9a-f]{24}$', 'action_id'),
      action: _requiredString(json['action'], 'action'),
      outcome: _requiredString(json['outcome'], 'outcome'),
      expectedRevision: _revision(
        json['expected_revision'],
        'expected_revision',
      ),
      afterRevision: json['after_revision'] == null
          ? null
          : _revision(json['after_revision'], 'after_revision'),
      proposalArtifact: _optionalString(json['proposal_artifact']),
    );
  }
}

class ManaKnowledgeClient {
  ManaKnowledgeClient({
    required this.projectRoot,
    this.manaRoot,
    this.timeout = const Duration(seconds: 30),
    ManaProcessRunner? run,
  }) : _run = run ?? _runProcess;

  final String projectRoot;
  final String? manaRoot;
  final Duration timeout;
  final ManaProcessRunner _run;

  Future<ManaKnowledgeCapabilities> capabilities() async =>
      ManaKnowledgeCapabilities.fromJson(await _knowledge(['capabilities']));

  Future<ManaKnowledgeDocuments> documents({
    required String scope,
    String lifecycle = 'active',
    int limit = 50,
    int offset = 0,
  }) async => ManaKnowledgeDocuments.fromJson(
    await _knowledge([
      'documents',
      ..._scopeArguments(scope),
      ..._lifecycleArguments(lifecycle),
      '--limit',
      '$limit',
      '--offset',
      '$offset',
    ]),
  );

  Future<ManaKnowledgeDocumentResponse> document(
    String id, {
    String? ifRevision,
  }) async => ManaKnowledgeDocumentResponse.fromJson(
    await _knowledge([
      'document',
      id,
      '--max-bytes',
      '65536',
      if (ifRevision != null) ...['--if-revision', ifRevision],
    ]),
  );

  Future<ManaKnowledgeSearch> search({
    required String query,
    required String scope,
    String lifecycle = 'active',
  }) async => ManaKnowledgeSearch.fromJson(
    await _knowledge([
      'search',
      '--query',
      query,
      ..._scopeArguments(scope),
      ..._lifecycleArguments(lifecycle),
      '--limit',
      '20',
      '--max-bytes',
      '16384',
    ]),
  );

  Future<ManaLearningQueue> learningCandidates() async =>
      ManaLearningQueue.fromJson(await _knowledge(['learning-candidates']));

  Future<ManaKnowledgePassageResponse> passage(
    String id, {
    String? ifRevision,
  }) async => ManaKnowledgePassageResponse.fromJson(
    await _knowledge([
      'passage',
      id,
      '--max-bytes',
      '8192',
      if (ifRevision != null) ...['--if-revision', ifRevision],
    ]),
  );

  static List<String> _scopeArguments(String scope) => [
    for (final value
        in scope == 'all'
            ? const ['project', 'user', 'framework']
            : [scope]) ...['--scope', value],
  ];

  static List<String> _lifecycleArguments(String lifecycle) => [
    for (final value
        in lifecycle == 'all'
            ? const [
                'active',
                'candidate',
                'reviewed',
                'rejected',
                'deferred',
                'archived',
                'superseded',
              ]
            : [lifecycle]) ...['--lifecycle', value],
  ];

  Future<ManaActionReceipt> editDocument({
    required ManaKnowledgeDocument document,
    required String content,
  }) async {
    if (!document.editable ||
        !const {'project', 'user'}.contains(document.summary.scope) ||
        document.expectedRevision == null ||
        document.editTarget == null ||
        (document.summary.scope == 'user' &&
            document.sourceDisclosure == null)) {
      throw const ManaKnowledgeException(
        'The producer did not advertise this document as editable.',
      );
    }
    final directory = await Directory.systemTemp.createTemp(
      'mana-familiar-edit-',
    );
    final payload = File(
      '${directory.path}${Platform.pathSeparator}content.md',
    );
    try {
      await payload.writeAsString(content, flush: true);
      return ManaActionReceipt.fromJson(
        await _action([
          'knowledge-edit',
          '--scope',
          document.summary.scope,
          '--target',
          document.editTarget!,
          '--expected-revision',
          document.expectedRevision!,
          '--content-file',
          payload.path,
          if (document.summary.scope == 'user') ...[
            '--confirm-user-source',
            document.sourceDisclosure!,
          ],
        ]),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Future<ManaActionReceipt> editProjectDocument({
    required ManaKnowledgeDocument document,
    required String content,
  }) {
    if (document.summary.scope != 'project') {
      throw const ManaKnowledgeException(
        'The document is not project-owned knowledge.',
      );
    }
    return editDocument(document: document, content: content);
  }

  Future<ManaActionReceipt> disposeCandidate(
    ManaLearningCandidate candidate,
    String disposition, {
    String guidance = '',
    String reviewScope = '',
  }) async {
    final args = candidate.sourceScope == 'project'
        ? [
            'project-learning',
            '--candidate-id',
            candidate.id,
            '--expected-revision',
            candidate.revision,
            '--disposition',
            disposition,
          ]
        : [
            'user-learning',
            '--candidate-id',
            candidate.id,
            '--expected-revision',
            candidate.revision,
            '--disposition',
            disposition,
            if (guidance.isNotEmpty) ...['--guidance', guidance],
            if (reviewScope.isNotEmpty) ...['--review-scope', reviewScope],
          ];
    return ManaActionReceipt.fromJson(await _action(args));
  }

  Future<ManaActionReceipt> promoteCandidate(
    ManaLearningCandidate candidate,
  ) async {
    if (candidate.sourceScope != 'user' ||
        !candidate.promotionEligible ||
        candidate.promoted ||
        candidate.reviewId == null ||
        candidate.reviewRevision == null) {
      throw const ManaKnowledgeException(
        'The producer did not advertise this review as promotion eligible.',
      );
    }
    return ManaActionReceipt.fromJson(
      await _action([
        'user-learning-promote',
        '--review-id',
        candidate.reviewId!,
        '--expected-revision',
        candidate.reviewRevision!,
      ]),
    );
  }

  Future<Map<String, dynamic>> _knowledge(List<String> command) =>
      _invoke('knowledge', 'mana-knowledge.py', command);
  Future<Map<String, dynamic>> _action(List<String> command) =>
      _invoke('action', 'mana-actions.py', command);

  Future<Map<String, dynamic>> _invoke(
    String wrapperCommand,
    String script,
    List<String> command,
  ) async {
    final wrapper = File('$projectRoot${Platform.pathSeparator}mana');
    final executable = wrapper.existsSync()
        ? wrapper.path
        : '${manaRoot ?? ''}${Platform.pathSeparator}scripts${Platform.pathSeparator}$script';
    if (!wrapper.existsSync() &&
        (manaRoot == null || !File(executable).existsSync())) {
      throw const ManaKnowledgeException(
        'No compatible Mana producer is available.',
      );
    }
    final arguments = wrapper.existsSync()
        ? [wrapperCommand, ...command, '--json']
        : ['--project-root', projectRoot, ...command, '--json'];
    final result = await _run(
      executable,
      arguments,
      workingDirectory: projectRoot,
    ).timeout(timeout);
    if (result.exitCode != 0) {
      Map<String, dynamic>? error;
      try {
        error = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      } catch (_) {}
      throw ManaKnowledgeException(
        error?['code']?.toString() ?? 'Mana command exited ${result.exitCode}.',
      );
    }
    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is! Map<String, dynamic>) {
      throw const ManaKnowledgeException('Mana returned a malformed response.');
    }
    return decoded;
  }
}

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => runManaProcess(executable, arguments, workingDirectory: workingDirectory);

void _schema(Map<String, dynamic> json, String expected) {
  if (json['schema'] != expected)
    throw ManaKnowledgeException('Expected $expected.');
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is! Map) throw ManaKnowledgeException('$field must be an object.');
  return value.cast<String, dynamic>();
}

List<Map<String, dynamic>> _maps(Object? value, String field) {
  if (value is! List || value.any((item) => item is! Map)) {
    throw ManaKnowledgeException('$field must be an object list.');
  }
  return value
      .map((item) => (item as Map).cast<String, dynamic>())
      .toList(growable: false);
}

String _requiredString(Object? value, String field, {bool allowEmpty = false}) {
  if (value is! String || (!allowEmpty && value.isEmpty))
    throw ManaKnowledgeException('$field must be a string.');
  return value;
}

String? _optionalString(Object? value, {bool allowEmpty = false}) =>
    value == null
    ? null
    : _requiredString(value, 'optional string', allowEmpty: allowEmpty);
bool _requiredBool(Object? value, String field) {
  if (value is! bool) throw ManaKnowledgeException('$field must be a boolean.');
  return value;
}

int _nonNegativeInt(Object? value, String field) {
  if (value is! int || value < 0)
    throw ManaKnowledgeException('$field must be a non-negative integer.');
  return value;
}

List<String> _strings(Object? value, String field) {
  if (value is! List || value.any((item) => item is! String))
    throw ManaKnowledgeException('$field must be a string list.');
  return value.cast<String>();
}

String _id(Object? value, String pattern, String field) {
  final id = _requiredString(value, field);
  if (!RegExp(pattern).hasMatch(id))
    throw ManaKnowledgeException('$field is malformed.');
  return id;
}

String _revision(Object? value, String field) =>
    _id(value, r'^sha256:[0-9a-f]{64}$', field);
bool _safeReference(String value) =>
    value.startsWith('mana://framework/') ||
    value.startsWith('mana-user-state://') ||
    (value.startsWith('.mana/') && !value.split('/').contains('..'));

bool _safeRelativeTarget(String value) =>
    value.isNotEmpty &&
    !_isAbsolutePath(value) &&
    !value.replaceAll('\\', '/').split('/').contains('..');

bool _isAbsolutePath(String value) =>
    value.startsWith('/') ||
    RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\)').hasMatch(value);
