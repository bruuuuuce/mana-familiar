import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mana_process.dart';

/// Producer-owned identity for a document contribution.  A path or heading is
/// intentionally never used as the identity: both may change on regeneration.
class HumanFeedbackTarget {
  const HumanFeedbackTarget({
    required this.projectId,
    required this.artifactId,
    required this.artifactRevision,
    this.sectionId,
  });

  final String projectId;
  final String artifactId;
  final String artifactRevision;
  final String? sectionId;

  String get key => [
    projectId,
    artifactId,
    artifactRevision,
    sectionId ?? '',
  ].map(Uri.encodeComponent).join('/');

  /// A draft belongs to the logical document/section. Its source revision is
  /// retained inside the draft payload, but must not strand a user's text
  /// when Story Start publishes a newer revision of the same target.
  String get documentKey => [
    projectId,
    artifactId,
    sectionId ?? '',
  ].map(Uri.encodeComponent).join('/');
}

enum HumanFeedbackThreadState { open, resolved }

enum HumanFeedbackLinkState { valid, changed, missing, ambiguous }

class HumanFeedbackEntry {
  const HumanFeedbackEntry({
    required this.id,
    required this.threadId,
    required this.body,
    required this.author,
    required this.recordedAt,
    required this.isReply,
  });

  final String id;
  final String threadId;
  final String body;
  final String author;
  final DateTime recordedAt;
  final bool isReply;
}

class HumanFeedbackThread {
  const HumanFeedbackThread({
    required this.id,
    required this.target,
    required this.state,
    required this.linkState,
    required this.revision,
    required this.entries,
  });

  final String id;
  final HumanFeedbackTarget target;
  final HumanFeedbackThreadState state;
  final HumanFeedbackLinkState linkState;
  final String revision;
  final List<HumanFeedbackEntry> entries;
}

class HumanFeedbackConflict implements Exception {
  const HumanFeedbackConflict(this.message);
  final String message;
  @override
  String toString() => message;
}

class HumanFeedbackBusy implements Exception {
  const HumanFeedbackBusy();
  @override
  String toString() => 'Human Feedback storage is busy. Retry the same draft.';
}

/// This is the client boundary for Mana's future write contract. Implementors
/// must persist and validate contributions; Familiar never writes `.mana`.
abstract interface class HumanFeedbackRepository {
  Future<List<HumanFeedbackThread>> threads(HumanFeedbackTarget target);

  Future<HumanFeedbackThread> createThread({
    required HumanFeedbackTarget target,
    required String body,
    required String author,
    required String idempotencyKey,
  });

  Future<HumanFeedbackThread> reply({
    required String threadId,
    required String revision,
    required String body,
    required String author,
    required String idempotencyKey,
  });

  Future<HumanFeedbackThread> setResolved({
    required String threadId,
    required String revision,
    required bool resolved,
    required String idempotencyKey,
  });
}

class HumanFeedbackCommandResult {
  const HumanFeedbackCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class HumanFeedbackCapabilities {
  const HumanFeedbackCapabilities(this.operations);

  final Set<String> operations;
  bool supports(String operation) => operations.contains(operation);
  static const unavailable = HumanFeedbackCapabilities(<String>{});
}

class HumanFeedbackThreadPage {
  const HumanFeedbackThreadPage({
    required this.threads,
    required this.nextCursor,
    required this.viewRevision,
  });

  final List<HumanFeedbackThread> threads;
  final String? nextCursor;
  final String? viewRevision;
}

/// A producer-declared stable target and its location in one rendered
/// Markdown revision. `headingIndex` is only a presentation locator; the
/// immutable section ID is what is persisted with a contribution.
class HumanFeedbackSectionTarget {
  const HumanFeedbackSectionTarget({
    required this.id,
    required this.headingIndex,
  });

  final String id;
  final int headingIndex;
}

class HumanFeedbackTargets {
  const HumanFeedbackTargets({
    required this.stableSections,
    required this.sections,
  });

  final bool stableSections;
  final List<HumanFeedbackSectionTarget> sections;

  static const unavailable = HumanFeedbackTargets(
    stableSections: false,
    sections: <HumanFeedbackSectionTarget>[],
  );
}

class HumanDecisionOption {
  const HumanDecisionOption({
    required this.id,
    required this.label,
    required this.summary,
  });
  final String id;
  final String label;
  final String summary;
}

class HumanDecisionTarget {
  const HumanDecisionTarget({
    required this.id,
    required this.question,
    required this.status,
    required this.options,
  });
  final String id;
  final String question;
  final String status;
  final List<HumanDecisionOption> options;
}

class HumanDecisionTargets {
  const HumanDecisionTargets({
    required this.sourcePath,
    required this.sourceRevision,
    required this.decisions,
  });
  final String sourcePath;
  final String sourceRevision;
  final List<HumanDecisionTarget> decisions;
}

class HumanDecisionState {
  const HumanDecisionState({
    required this.decisionId,
    required this.revision,
    required this.selectedOptionId,
  });
  final String decisionId;
  final String revision;
  final String? selectedOptionId;
}

typedef HumanFeedbackCommandRunner =
    Future<HumanFeedbackCommandResult> Function(
      String executable,
      List<String> arguments,
      String request,
    );

typedef HumanFeedbackProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Calls the explicit Mana command through structured arguments and JSON on
/// stdin. It never derives paths from a rendered Markdown payload.
class ManaHumanFeedbackRepository implements HumanFeedbackRepository {
  ManaHumanFeedbackRepository({
    required this.projectRoot,
    this.manaRoot,
    this.commandTimeout = const Duration(seconds: 30),
    HumanFeedbackCommandRunner? run,
    HumanFeedbackProcessStarter? startProcess,
  }) : _run =
           run ??
           ((executable, arguments, request) => _runProcess(
             executable,
             arguments,
             request,
             commandTimeout,
             startProcess: startProcess,
           ));

  final String projectRoot;
  final String? manaRoot;
  final Duration commandTimeout;
  final HumanFeedbackCommandRunner _run;

  Future<HumanFeedbackCapabilities> capabilities() async {
    final response = await _command('capabilities', const {});
    if (response['schemaVersion'] != 'mana.human-feedback.capabilities/v1' ||
        response['operations'] is! List) {
      throw const FormatException('Mana returned incompatible capabilities.');
    }
    final operations = (response['operations'] as List)
        .whereType<String>()
        .toSet();
    return HumanFeedbackCapabilities(operations);
  }

  Future<HumanDecisionTargets> decisionTargets(String sourcePath) async {
    final response = await _command('decision-targets', {
      'decisionSource': sourcePath,
    });
    if (response['schemaVersion'] !=
            'mana.human-feedback.decision-targets/v1' ||
        response['sourcePath'] is! String ||
        response['sourceRevision'] is! String ||
        response['decisions'] is! List) {
      throw const FormatException(
        'Mana returned incompatible decision targets.',
      );
    }
    final decisions = <HumanDecisionTarget>[];
    for (final item in response['decisions'] as List) {
      if (item is! Map ||
          item['decisionId'] is! String ||
          item['question'] is! String ||
          item['status'] is! String ||
          item['options'] is! List) {
        throw const FormatException('Mana returned an incomplete decision.');
      }
      final options = <HumanDecisionOption>[];
      for (final option in item['options'] as List) {
        if (option is! Map ||
            option['optionId'] is! String ||
            option['label'] is! String ||
            option['summary'] is! String) {
          throw const FormatException('Mana returned an incomplete option.');
        }
        options.add(
          HumanDecisionOption(
            id: option['optionId'] as String,
            label: option['label'] as String,
            summary: option['summary'] as String,
          ),
        );
      }
      decisions.add(
        HumanDecisionTarget(
          id: item['decisionId'] as String,
          question: item['question'] as String,
          status: item['status'] as String,
          options: options,
        ),
      );
    }
    return HumanDecisionTargets(
      sourcePath: response['sourcePath'] as String,
      sourceRevision: response['sourceRevision'] as String,
      decisions: decisions,
    );
  }

  Future<void> recordDecision({
    required HumanDecisionTargets targets,
    required String decisionId,
    required String decisionRevision,
    required String optionId,
    required String author,
    required String rationale,
    required String idempotencyKey,
  }) async {
    final response = await _command('decide', {
      'decisionSource': targets.sourcePath,
      'decisionSourceRevision': targets.sourceRevision,
      'decisionId': decisionId,
      'decisionRevision': decisionRevision,
      'optionId': optionId,
      'author': author,
      'body': rationale,
      'idempotencyKey': idempotencyKey,
    });
    if (response['schemaVersion'] != 'mana.human-feedback.decision-result/v1' ||
        response['status'] != 'recorded') {
      throw const FormatException(
        'Mana returned an incompatible decision result.',
      );
    }
  }

  Future<HumanDecisionState> decisionState(String decisionId) async {
    final response = await _command('decision-state', {
      'decisionId': decisionId,
    });
    if (response['schemaVersion'] != 'mana.human-feedback.decision-state/v1' ||
        response['decisionId'] is! String ||
        response['revision'] is! String) {
      throw const FormatException(
        'Mana returned an incompatible decision state.',
      );
    }
    final selected = response['selectedOptionId'];
    if (selected != null && selected is! String) {
      throw const FormatException('Mana returned an invalid selected option.');
    }
    return HumanDecisionState(
      decisionId: response['decisionId'] as String,
      revision: response['revision'] as String,
      selectedOptionId: selected as String?,
    );
  }

  Future<Map<String, dynamic>> _command(
    String operation,
    Map<String, String> request,
  ) async {
    final wrapper = File('$projectRoot${Platform.pathSeparator}mana');
    final script = manaRoot == null
        ? null
        : File(
            '$manaRoot${Platform.pathSeparator}scripts${Platform.pathSeparator}mana-human-feedback.sh',
          );
    if (!await wrapper.exists() && (script == null || !await script.exists())) {
      throw UnsupportedError(
        'This Mana producer does not provide human feedback.',
      );
    }
    final result =
        await _run(await wrapper.exists() ? wrapper.path : script!.path, [
          if (await wrapper.exists()) 'human-feedback',
          if (await wrapper.exists() == false) '--project-root',
          if (await wrapper.exists() == false) projectRoot,
          operation,
          '--request-stdin',
          '--json',
        ], jsonEncode(request));
    final value = _decodeCommand(result.stdout);
    if (result.exitCode == 3 && value != null) {
      throw HumanFeedbackConflict(
        value['currentRevision'] is String
            ? 'This thread changed remotely. Current revision: ${value['currentRevision']}.'
            : 'This thread changed remotely.',
      );
    }
    if (result.exitCode == 75 &&
        value?['schemaVersion'] == 'mana.human-feedback.busy/v1' &&
        value?['status'] == 'busy') {
      throw const HumanFeedbackBusy();
    }
    if (result.exitCode != 0) {
      throw StateError(
        result.stderr.trim().isEmpty
            ? 'Mana human-feedback exited ${result.exitCode}.'
            : result.stderr.trim(),
      );
    }
    if (value == null) {
      throw const FormatException('Mana returned invalid human-feedback JSON.');
    }
    return value;
  }

  @override
  Future<List<HumanFeedbackThread>> threads(HumanFeedbackTarget target) async {
    return _readAll((cursor) => threadPage(target, cursor: cursor));
  }

  /// Prefer Mana's history operation when it is negotiated. Older producers
  /// retain their exact-revision read and therefore keep their existing
  /// read-only behavior instead of receiving an invented link state.
  Future<List<HumanFeedbackThread>> threadsForDisplay(
    HumanFeedbackTarget target,
  ) async {
    try {
      final supported = await capabilities();
      if (supported.supports('list-history')) {
        return _readAll((cursor) => historyThreadPage(target, cursor: cursor));
      }
    } catch (_) {
      // A capability probe is additive. Keep the established list path when
      // a compatible older producer cannot negotiate it.
    }
    return threads(target);
  }

  /// Negotiates producer-owned Markdown section IDs. Older producers remain
  /// document-only: Familiar must not synthesize a target from a heading slug.
  Future<HumanFeedbackTargets> targets(HumanFeedbackTarget target) async {
    try {
      final capabilities = await this.capabilities();
      if (!capabilities.supports('targets')) {
        return HumanFeedbackTargets.unavailable;
      }
      final response = await _command('targets', _targetRequest(target));
      if (response['schemaVersion'] != 'mana.human-feedback.targets/v1' ||
          response['stableSections'] is! bool ||
          response['sections'] is! List) {
        throw const FormatException(
          'Mana returned incompatible feedback targets.',
        );
      }
      final sections = <HumanFeedbackSectionTarget>[];
      for (final entry in response['sections'] as List) {
        if (entry is! Map ||
            entry['sectionId'] is! String ||
            entry['headingIndex'] is! int ||
            (entry['headingIndex'] as int) < 1) {
          throw const FormatException(
            'Mana returned an invalid feedback target.',
          );
        }
        sections.add(
          HumanFeedbackSectionTarget(
            id: entry['sectionId'] as String,
            headingIndex: entry['headingIndex'] as int,
          ),
        );
      }
      return HumanFeedbackTargets(
        stableSections: response['stableSections'] as bool,
        sections: sections,
      );
    } catch (_) {
      // Target negotiation is additive. A transient or older producer keeps
      // the safe document-level comment path available.
      return HumanFeedbackTargets.unavailable;
    }
  }

  Future<List<HumanFeedbackThread>> _readAll(
    Future<HumanFeedbackThreadPage> Function(String? cursor) pageFor,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final all = <HumanFeedbackThread>[];
      String? cursor;
      String? viewRevision;
      var changed = false;
      do {
        final page = await pageFor(cursor);
        if (viewRevision != null &&
            page.viewRevision != null &&
            page.viewRevision != viewRevision) {
          changed = true;
          break;
        }
        viewRevision ??= page.viewRevision;
        all.addAll(page.threads);
        cursor = page.nextCursor;
      } while (cursor != null);
      if (!changed) return all;
    }
    throw const HumanFeedbackConflict(
      'Comments changed while loading. Please retry.',
    );
  }

  Future<HumanFeedbackThreadPage> threadPage(
    HumanFeedbackTarget target, {
    String? cursor,
    int? limit,
  }) async {
    if (limit != null && (limit < 1 || limit > 200)) {
      throw ArgumentError.value(limit, 'limit', 'must be in 1..200');
    }
    final response = await _command('list', {
      ..._targetRequest(target),
      'cursor': ?cursor,
      'limit': ?limit?.toString(),
    });
    if (response['schemaVersion'] != 'mana.human-feedback.threads/v1' ||
        response['threads'] is! List) {
      throw const FormatException(
        'Mana returned an incompatible thread response.',
      );
    }
    final next = response['nextCursor'];
    final view = response['viewRevision'];
    if ((next != null && next is! String) ||
        (view != null && view is! String)) {
      throw const FormatException('Mana returned invalid pagination metadata.');
    }
    return HumanFeedbackThreadPage(
      threads: (response['threads'] as List)
          .map((value) => _threadFromJson(value, target))
          .toList(growable: false),
      nextCursor: next as String?,
      viewRevision: view as String?,
    );
  }

  Future<HumanFeedbackThreadPage> historyThreadPage(
    HumanFeedbackTarget target, {
    String? cursor,
    int? limit,
  }) async {
    if (limit != null && (limit < 1 || limit > 200)) {
      throw ArgumentError.value(limit, 'limit', 'must be in 1..200');
    }
    final response = await _command('list-history', {
      ..._targetRequest(target),
      'cursor': ?cursor,
      'limit': ?limit?.toString(),
    });
    if (response['schemaVersion'] != 'mana.human-feedback.thread-history/v1' ||
        response['threads'] is! List) {
      throw const FormatException(
        'Mana returned an incompatible thread-history response.',
      );
    }
    final next = response['nextCursor'];
    final view = response['viewRevision'];
    if ((next != null && next is! String) ||
        (view != null && view is! String)) {
      throw const FormatException('Mana returned invalid pagination metadata.');
    }
    return HumanFeedbackThreadPage(
      threads: (response['threads'] as List)
          .map((value) => _threadFromJson(value, target))
          .toList(growable: false),
      nextCursor: next as String?,
      viewRevision: view as String?,
    );
  }

  @override
  Future<HumanFeedbackThread> createThread({
    required HumanFeedbackTarget target,
    required String body,
    required String author,
    required String idempotencyKey,
  }) async {
    final response = await _command('create', {
      ..._targetRequest(target),
      'body': body,
      'author': author,
      'idempotencyKey': idempotencyKey,
    });
    return _threadFromResult(response, target);
  }

  @override
  Future<HumanFeedbackThread> reply({
    required String threadId,
    required String revision,
    required String body,
    required String author,
    required String idempotencyKey,
  }) async => _threadFromResult(
    await _command('reply', {
      'threadId': threadId,
      'threadRevision': revision,
      'body': body,
      'author': author,
      'idempotencyKey': idempotencyKey,
    }),
    null,
  );

  @override
  Future<HumanFeedbackThread> setResolved({
    required String threadId,
    required String revision,
    required bool resolved,
    required String idempotencyKey,
  }) async => _threadFromResult(
    await _command(resolved ? 'resolve' : 'reopen', {
      'threadId': threadId,
      'threadRevision': revision,
      'idempotencyKey': idempotencyKey,
    }),
    null,
  );

  Map<String, String> _targetRequest(HumanFeedbackTarget target) => {
    'artifactId': target.artifactId,
    'artifactRevision': target.artifactRevision,
    if (target.sectionId != null) 'sectionId': target.sectionId!,
  };

  HumanFeedbackThread _threadFromResult(
    Map<String, dynamic> result,
    HumanFeedbackTarget? target,
  ) {
    if (result['schemaVersion'] != 'mana.human-feedback.result/v1' ||
        result['threadId'] is! String ||
        result['threadRevision'] is! String) {
      throw const FormatException(
        'Mana returned an incompatible write result.',
      );
    }
    // A write result confirms persistence. A following read supplies complete
    // history and target information, so callers always refresh after it.
    return HumanFeedbackThread(
      id: result['threadId'] as String,
      target:
          target ??
          const HumanFeedbackTarget(
            projectId: '',
            artifactId: '',
            artifactRevision: '',
          ),
      state: HumanFeedbackThreadState.open,
      linkState: HumanFeedbackLinkState.valid,
      revision: result['threadRevision'] as String,
      entries: const [],
    );
  }
}

Map<String, dynamic>? _decodeCommand(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

HumanFeedbackThread _threadFromJson(Object? input, HumanFeedbackTarget target) {
  if (input is! Map) throw const FormatException('Thread is not an object.');
  final json = input.cast<String, dynamic>();
  final threadId = json['threadId'];
  final revision = json['revision'];
  final state = json['state'];
  final entries = json['entries'];
  if (threadId is! String ||
      revision is! String ||
      state is! String ||
      entries is! List) {
    throw const FormatException('Thread is incomplete.');
  }
  final rawTarget = json['target'];
  HumanFeedbackTarget sourceTarget = target;
  if (rawTarget is Map) {
    final source = rawTarget.cast<String, dynamic>();
    final artifactId = source['artifactId'];
    final artifactRevision = source['artifactRevision'];
    final sectionId = source['sectionId'];
    if (artifactId is String &&
        artifactRevision is String &&
        (sectionId == null || sectionId is String)) {
      sourceTarget = HumanFeedbackTarget(
        projectId: target.projectId,
        artifactId: artifactId,
        artifactRevision: artifactRevision,
        sectionId: sectionId as String?,
      );
    }
  }
  final linkState = switch (json['linkState']) {
    'changed' => HumanFeedbackLinkState.changed,
    'missing' => HumanFeedbackLinkState.missing,
    'ambiguous' => HumanFeedbackLinkState.ambiguous,
    _ => HumanFeedbackLinkState.valid,
  };
  return HumanFeedbackThread(
    id: threadId,
    target: sourceTarget,
    state: state == 'resolved'
        ? HumanFeedbackThreadState.resolved
        : HumanFeedbackThreadState.open,
    linkState: linkState,
    revision: revision,
    entries: entries
        .map((entry) {
          if (entry is! Map ||
              entry['entryId'] is! String ||
              entry['author'] is! String ||
              entry['body'] is! String ||
              entry['recordedAt'] is! String) {
            throw const FormatException('Thread entry is incomplete.');
          }
          return HumanFeedbackEntry(
            id: entry['entryId'] as String,
            threadId: threadId,
            author: entry['author'] as String,
            body: entry['body'] as String,
            recordedAt: DateTime.parse(entry['recordedAt'] as String),
            isReply: entry['kind'] == 'reply',
          );
        })
        .toList(growable: false),
  );
}

Future<HumanFeedbackCommandResult> _runProcess(
  String executable,
  List<String> arguments,
  String request,
  Duration timeout, {
  HumanFeedbackProcessStarter? startProcess,
}) async {
  final process =
      await (startProcess ??
          (executable, arguments) =>
              startManaProcess(executable, arguments))(executable, arguments);
  process.stdin
    ..write(request)
    ..close();
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    await terminateManaProcess(process);
    try {
      await Future.wait<Object>([
        process.exitCode,
        stdout,
        stderr,
      ]).timeout(const Duration(seconds: 2));
    } on TimeoutException {
      await terminateManaProcess(process, force: true);
    }
    throw TimeoutException(
      'Mana human-feedback did not respond within ${timeout.inSeconds} seconds.',
    );
  }
  final result = await Future.wait([stdout, stderr]);
  return HumanFeedbackCommandResult(
    stdout: result[0],
    stderr: result[1],
    exitCode: exitCode,
  );
}

class HumanFeedbackUnavailable implements HumanFeedbackRepository {
  const HumanFeedbackUnavailable(this.reason);
  final String reason;

  Never _unsupported() => throw UnsupportedError(reason);

  @override
  Future<List<HumanFeedbackThread>> threads(HumanFeedbackTarget target) async =>
      _unsupported();
  @override
  Future<HumanFeedbackThread> createThread({
    required HumanFeedbackTarget target,
    required String body,
    required String author,
    required String idempotencyKey,
  }) async => _unsupported();
  @override
  Future<HumanFeedbackThread> reply({
    required String threadId,
    required String revision,
    required String body,
    required String author,
    required String idempotencyKey,
  }) async => _unsupported();
  @override
  Future<HumanFeedbackThread> setResolved({
    required String threadId,
    required String revision,
    required bool resolved,
    required String idempotencyKey,
  }) async => _unsupported();
}

/// A local draft is recoverable UI state, never a claim that Mana has accepted
/// a comment. Drafts deliberately live outside the observed project.
class HumanFeedbackDraft {
  const HumanFeedbackDraft({
    required this.target,
    required this.body,
    required this.author,
    required this.idempotencyKey,
    required this.updatedAt,
    this.composerId = 'comment',
    this.selectionId,
  });

  final HumanFeedbackTarget target;
  final String body;
  final String author;
  final String idempotencyKey;
  final DateTime updatedAt;

  /// Distinguishes the document composer from reply/decision composers.
  final String composerId;

  /// Optional stable selection for structured forms such as Story Start
  /// decisions. It is local recoverable state, not a producer-side choice.
  final String? selectionId;

  Map<String, Object?> toJson() => {
    'project_id': target.projectId,
    'artifact_id': target.artifactId,
    'artifact_revision': target.artifactRevision,
    'section_id': target.sectionId,
    'body': body,
    'author': author,
    'idempotency_key': idempotencyKey,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'composer_id': composerId,
    'selection_id': selectionId,
  };

  static HumanFeedbackDraft? fromJson(Object? input) {
    if (input is! Map) return null;
    final json = input.cast<Object?, Object?>();
    String? string(String name) =>
        json[name] is String ? json[name] as String : null;
    final project = string('project_id');
    final artifact = string('artifact_id');
    final revision = string('artifact_revision');
    final body = string('body');
    final author = string('author');
    final key = string('idempotency_key');
    final updated = DateTime.tryParse(string('updated_at') ?? '');
    if ([
          project,
          artifact,
          revision,
          body,
          author,
          key,
        ].any((value) => value == null) ||
        updated == null) {
      return null;
    }
    return HumanFeedbackDraft(
      target: HumanFeedbackTarget(
        projectId: project!,
        artifactId: artifact!,
        artifactRevision: revision!,
        sectionId: string('section_id'),
      ),
      body: body!,
      author: author!,
      idempotencyKey: key!,
      updatedAt: updated,
      composerId: string('composer_id') ?? 'comment',
      selectionId: string('selection_id'),
    );
  }
}

class HumanFeedbackDraftStore {
  HumanFeedbackDraftStore(
    this.root, {
    this.debounce = const Duration(milliseconds: 350),
    String sessionId = 'default',
  }) : sessionId = _validateSessionId(sessionId);
  final Directory root;
  final Duration debounce;
  final String sessionId;
  final Map<String, Timer> _timers = {};
  final Map<String, HumanFeedbackDraft> _pending = {};
  final Map<String, Future<void>> _writes = {};

  static String _validateSessionId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, 'sessionId');
    return normalized;
  }

  String _key(HumanFeedbackTarget target, String composerId) =>
      '$sessionId:$composerId:${target.documentKey}';

  File _file(
    HumanFeedbackTarget target, [
    String composerId = 'comment',
  ]) => File(
    '${root.path}${Platform.pathSeparator}${Uri.encodeComponent(sessionId)}${Platform.pathSeparator}${target.documentKey}${Platform.pathSeparator}${Uri.encodeComponent(composerId)}.json',
  );

  /// The first release keyed drafts by revision. Read that location only to
  /// migrate existing local text; all new writes use the stable document key.
  File _legacyFile(
    HumanFeedbackTarget target, [
    String composerId = 'comment',
  ]) => File(
    '${root.path}${Platform.pathSeparator}${target.key}${Platform.pathSeparator}${Uri.encodeComponent(composerId)}.json',
  );

  Future<HumanFeedbackDraft?> _read(File file, String composerId) async {
    try {
      final draft = HumanFeedbackDraft.fromJson(
        jsonDecode(await file.readAsString()),
      );
      return draft?.composerId == composerId ? draft : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(File file, HumanFeedbackDraft draft) async {
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsString(jsonEncode(draft.toJson()));
    await temporary.rename(file.path);
  }

  Future<HumanFeedbackDraft?> load(
    HumanFeedbackTarget target, [
    String composerId = 'comment',
  ]) async {
    final file = _file(target, composerId);
    final current = await _read(file, composerId);
    if (current != null) return current;

    final legacy = _legacyFile(target, composerId);
    final migrated = await _read(legacy, composerId);
    if (migrated != null) {
      await _enqueue(_key(target, composerId), () async {
        if (await file.exists()) return;
        await _write(file, migrated);
        if (await legacy.exists()) await legacy.delete();
      });
    }
    return migrated;
  }

  void schedule(HumanFeedbackDraft draft) {
    final key = _key(draft.target, draft.composerId);
    _pending[key] = draft;
    _timers.remove(key)?.cancel();
    _timers[key] = Timer(debounce, () {
      unawaited(flush(draft.target, draft.composerId));
    });
  }

  Future<void> flush(
    HumanFeedbackTarget target, [
    String composerId = 'comment',
  ]) async {
    final key = _key(target, composerId);
    _timers.remove(key)?.cancel();
    await _enqueue(key, () async {
      final draft = _pending.remove(key);
      if (draft == null) return;
      await _write(_file(target, draft.composerId), draft);
    });
  }

  Future<void> discard(
    HumanFeedbackTarget target, [
    String composerId = 'comment',
  ]) async {
    final key = _key(target, composerId);
    _timers.remove(key)?.cancel();
    _pending.remove(key);
    await _enqueue(key, () async {
      final file = _file(target, composerId);
      if (await file.exists()) await file.delete();
      final legacy = _legacyFile(target, composerId);
      if (await legacy.exists()) await legacy.delete();
    });
  }

  Future<void> flushAll() async {
    final drafts = _pending.values.toList(growable: false);
    for (final draft in drafts) {
      await flush(draft.target, draft.composerId);
    }
  }

  Future<void> dispose() async {
    await flushAll();
  }

  Future<void> _enqueue(String key, Future<void> Function() operation) {
    final previous = _writes[key] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then<void>((_) => operation());
    _writes[key] = next;
    unawaited(
      next.then<void>(
        (_) {
          if (identical(_writes[key], next)) _writes.remove(key);
        },
        onError: (error, stackTrace) {
          if (identical(_writes[key], next)) _writes.remove(key);
        },
      ),
    );
    return next;
  }
}
