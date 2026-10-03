// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:io';

import 'mana_process.dart';

import 'mana_inspect.dart';

const manaReviewStatusSchema = 'mana.review-scheduler.status/v1';
const manaReviewInboxSchema = 'mana.review-scheduler.inbox/v1';
const manaReviewRunSchema = 'mana.review-scheduler.run/v1';

class ManaReviewSchedulerException implements Exception {
  const ManaReviewSchedulerException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ManaReviewSchedulerStatus {
  const ManaReviewSchedulerStatus({
    required this.configured,
    required this.enabled,
    required this.state,
    required this.credentialsStored,
    this.policy,
  });
  final bool configured;
  final bool enabled;
  final String state;
  final bool credentialsStored;
  final String? policy;
  factory ManaReviewSchedulerStatus.fromJson(Map<String, dynamic> json) {
    _schema(json, manaReviewStatusSchema);
    return ManaReviewSchedulerStatus(
      configured: _bool(json['configured'], 'configured'),
      enabled: _bool(json['enabled'], 'enabled'),
      state: _string(json['state'], 'state'),
      credentialsStored: _bool(
        json['credentials_stored'],
        'credentials_stored',
      ),
      policy: json['policy'] is String ? json['policy'] as String : null,
    );
  }
}

class ManaReviewFinding {
  const ManaReviewFinding(this.id, this.severity, this.title, this.body);
  final String id;
  final String severity;
  final String title;
  final String body;
  factory ManaReviewFinding.fromJson(Map<String, dynamic> json) =>
      ManaReviewFinding(
        _id(json['draft_id'], r'^[A-Za-z0-9_.-]{1,96}$', 'draft_id'),
        _string(json['severity'], 'severity'),
        _string(json['title'], 'title'),
        _string(json['body'], 'body', allowEmpty: true),
      );
}

class ManaReviewRun {
  const ManaReviewRun({
    required this.id,
    required this.repository,
    required this.number,
    required this.headSha,
    required this.reviewer,
    required this.profileRevision,
    required this.contextRevision,
    required this.title,
    required this.url,
    required this.status,
    required this.attempt,
    required this.stale,
    required this.findings,
    this.draftRevision,
    this.errorCode,
    this.publicationStatus,
  });
  final String id;
  final String repository;
  final int number;
  final String headSha;
  final String reviewer;
  final String profileRevision;
  final String contextRevision;
  final String title;
  final String url;
  final String status;
  final int attempt;
  final bool stale;
  final List<ManaReviewFinding> findings;
  final String? draftRevision;
  final String? errorCode;
  final String? publicationStatus;
  factory ManaReviewRun.fromJson(Map<String, dynamic> json) {
    final findings = json['findings'];
    return ManaReviewRun(
      id: _id(json['run_id'], r'^review_[0-9a-f]{24}$', 'run_id'),
      repository: _id(
        json['repository'],
        r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$',
        'repository',
      ),
      number: _positiveInt(json['pr_number'], 'pr_number'),
      headSha: _id(json['head_sha'], r'^[0-9a-f]{40,64}$', 'head_sha'),
      reviewer: _string(json['reviewer'], 'reviewer'),
      profileRevision: _revision(json['profile_revision'], 'profile_revision'),
      contextRevision: _string(json['context_revision'], 'context_revision'),
      title: _string(json['title'], 'title', allowEmpty: true),
      url: _string(json['url'], 'url'),
      status: _string(json['status'], 'status'),
      attempt: _nonNegativeInt(json['attempt'], 'attempt'),
      stale: _bool(json['stale'], 'stale'),
      draftRevision: json['draft_revision'] == null
          ? null
          : _revision(json['draft_revision'], 'draft_revision'),
      errorCode: json['error_code'] is String
          ? json['error_code'] as String
          : null,
      publicationStatus: json['publication_status'] is String
          ? json['publication_status'] as String
          : null,
      findings: findings == null
          ? const []
          : _maps(
              findings,
              'findings',
            ).map(ManaReviewFinding.fromJson).toList(growable: false),
    );
  }
}

class ManaReviewInbox {
  const ManaReviewInbox(this.items);
  final List<ManaReviewRun> items;
  factory ManaReviewInbox.fromJson(Map<String, dynamic> json) {
    _schema(json, manaReviewInboxSchema);
    return ManaReviewInbox(
      _maps(
        json['items'],
        'items',
      ).map(ManaReviewRun.fromJson).toList(growable: false),
    );
  }
}

class ManaReviewSchedulerClient {
  ManaReviewSchedulerClient({
    required this.projectRoot,
    this.manaRoot,
    this.timeout = const Duration(seconds: 30),
    ManaProcessRunner? run,
  }) : _run = run ?? _runProcess;

  final String projectRoot;
  final String? manaRoot;
  final Duration timeout;
  final ManaProcessRunner _run;

  Future<ManaReviewSchedulerStatus> status() async =>
      ManaReviewSchedulerStatus.fromJson(await _invoke(['status']));
  Future<ManaReviewInbox> inbox({String? status}) async =>
      ManaReviewInbox.fromJson(
        await _invoke([
          'inbox',
          if (status != null) ...['--status', status],
          '--limit',
          '200',
        ]),
      );
  Future<ManaReviewRun> show(String runId) async {
    final value = await _invoke(['show', runId]);
    _schema(value, manaReviewRunSchema);
    return ManaReviewRun.fromJson(_map(value['run'], 'run'));
  }

  Future<void> retry(ManaReviewRun run) async => _invoke([
    'retry',
    run.id,
    if (run.draftRevision != null) ...[
      '--expected-draft-revision',
      run.draftRevision!,
    ],
  ]);
  Future<void> cancel(ManaReviewRun run) async => _invoke(['cancel', run.id]);
  Future<void> publish(ManaReviewRun run, ManaReviewFinding draft) async {
    if (run.draftRevision == null) {
      throw const ManaReviewSchedulerException(
        'This run has no current draft revision.',
      );
    }
    await _invoke([
      'publish',
      run.id,
      '--head-sha',
      run.headSha,
      '--draft-revision',
      run.draftRevision!,
      '--draft-id',
      draft.id,
      '--confirm',
      '--fake-result',
      'published',
    ]);
  }

  Future<Map<String, dynamic>> _invoke(List<String> command) async {
    final wrapper = File('$projectRoot${Platform.pathSeparator}mana');
    final script =
        '${manaRoot ?? ''}${Platform.pathSeparator}scripts${Platform.pathSeparator}mana-review-inbox.py';
    final executable = wrapper.existsSync() ? wrapper.path : script;
    if (!wrapper.existsSync() &&
        (manaRoot == null || !File(script).existsSync())) {
      throw const ManaReviewSchedulerException(
        'No compatible Mana review scheduler is available.',
      );
    }
    final arguments = wrapper.existsSync()
        ? ['review-inbox', ...command, '--json']
        : [...command, '--json'];
    final result = await _run(
      executable,
      arguments,
      workingDirectory: projectRoot,
    ).timeout(timeout);
    if (result.exitCode != 0) {
      try {
        final error =
            jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
        throw ManaReviewSchedulerException(
          error['code']?.toString() ?? 'Scheduler command failed.',
        );
      } on FormatException {
        throw ManaReviewSchedulerException(
          'Scheduler command exited ${result.exitCode}.',
        );
      }
    }
    final value = jsonDecode(result.stdout.toString());
    if (value is! Map<String, dynamic>) {
      throw const ManaReviewSchedulerException(
        'Scheduler returned malformed JSON.',
      );
    }
    return value;
  }
}

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => runManaProcess(executable, arguments, workingDirectory: workingDirectory);

void _schema(Map<String, dynamic> json, String expected) {
  if (json['schema'] != expected)
    throw ManaReviewSchedulerException('Expected $expected.');
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is! Map)
    throw ManaReviewSchedulerException('$field must be an object.');
  return value.cast<String, dynamic>();
}

List<Map<String, dynamic>> _maps(Object? value, String field) {
  if (value is! List || value.any((item) => item is! Map))
    throw ManaReviewSchedulerException('$field must be an object list.');
  return value
      .map((item) => (item as Map).cast<String, dynamic>())
      .toList(growable: false);
}

String _string(Object? value, String field, {bool allowEmpty = false}) {
  if (value is! String || (!allowEmpty && value.isEmpty))
    throw ManaReviewSchedulerException('$field must be a string.');
  return value;
}

String _id(Object? value, String pattern, String field) {
  final id = _string(value, field);
  if (!RegExp(pattern).hasMatch(id))
    throw ManaReviewSchedulerException('$field is malformed.');
  return id;
}

String _revision(Object? value, String field) =>
    _id(value, r'^sha256:[0-9a-f]{64}$', field);
bool _bool(Object? value, String field) {
  if (value is! bool)
    throw ManaReviewSchedulerException('$field must be a boolean.');
  return value;
}

int _nonNegativeInt(Object? value, String field) {
  if (value is! int || value < 0)
    throw ManaReviewSchedulerException('$field must be non-negative.');
  return value;
}

int _positiveInt(Object? value, String field) {
  final number = _nonNegativeInt(value, field);
  if (number == 0)
    throw ManaReviewSchedulerException('$field must be positive.');
  return number;
}
