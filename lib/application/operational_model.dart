import 'mana_inspect.dart';

/// Producer-derived activity metadata. Missing fields stay explicitly unknown.
class OperationalActivity {
  const OperationalActivity({
    required this.artifact,
    required this.runIdentity,
    required this.timestamp,
    required this.timestampProvenance,
    required this.profile,
    required this.workspace,
    required this.status,
    required this.summary,
    required this.partial,
  });

  final ManaInspectArtifactSummary artifact;
  final String runIdentity;
  final String? timestamp;
  final String timestampProvenance;
  final String? profile;
  final String? workspace;
  final String status;
  final String summary;
  final bool partial;

  factory OperationalActivity.fromArtifact(
    ManaInspectArtifactSummary artifact,
  ) {
    final raw = artifact.raw;
    String? string(String key) =>
        raw[key] is String ? raw[key] as String : null;
    final timestamp =
        string('timestamp') ??
        string('occurred_at') ??
        string('created_at') ??
        string('updated_at');
    final run =
        string('run_id') ??
        string('session_id') ??
        string('runtime_id') ??
        'No run identity';
    final summary = string('summary') ?? string('message') ?? artifact.kind;
    return OperationalActivity(
      artifact: artifact,
      runIdentity: run,
      timestamp: timestamp,
      timestampProvenance: timestamp == null
          ? 'not provided by Mana'
          : 'Mana artifact metadata',
      profile: string('profile') ?? string('producer'),
      workspace: string('workspace') ?? string('workspace_id'),
      status: artifact.status,
      summary: summary,
      partial:
          artifact.status == 'malformed' ||
          artifact.status == 'quarantined' ||
          timestamp == null ||
          run == 'No run identity',
    );
  }
}

class ActivityFilters {
  const ActivityFilters({
    this.status,
    this.profileOrFamily,
    this.workspace,
    this.recentOnly = false,
  });
  final String? status;
  final String? profileOrFamily;
  final String? workspace;
  final bool recentOnly;

  List<OperationalActivity> apply(
    Iterable<ManaInspectArtifactSummary> artifacts,
  ) {
    final entries = artifacts.map(OperationalActivity.fromArtifact).where((
      entry,
    ) {
      if (status != null && entry.status != status) return false;
      if (profileOrFamily != null &&
          entry.profile != profileOrFamily &&
          entry.artifact.family != profileOrFamily) {
        return false;
      }
      if (workspace != null && entry.workspace != workspace) return false;
      if (recentOnly && entry.timestamp == null) return false;
      return true;
    }).toList();
    entries.sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
    return entries;
  }
}

class VerificationViewModel {
  const VerificationViewModel({
    required this.result,
    required this.checks,
    required this.trustOrigin,
    required this.effect,
    required this.limits,
    required this.evidencePaths,
    required this.rerunContext,
    required this.stale,
  });
  final String result;
  final List<Map<String, dynamic>> checks;
  final String? trustOrigin;
  final String? effect;
  final String? limits;
  final List<String> evidencePaths;
  final String? rerunContext;
  final bool stale;

  factory VerificationViewModel.fromPayload(
    Object? payload,
    Map<String, dynamic> raw,
  ) {
    final map = payload is Map ? payload : const <Object?, Object?>{};
    String? string(String key) => (map[key] ?? raw[key]) is String
        ? (map[key] ?? raw[key]) as String
        : null;
    final checksRaw = map['checks'] ?? raw['checks'];
    final evidenceRaw =
        map['evidence_paths'] ??
        raw['evidence_paths'] ??
        map['evidence'] ??
        raw['evidence'];
    return VerificationViewModel(
      result:
          string('result') ??
          string('overall_status') ??
          string('status') ??
          'UNKNOWN',
      checks: checksRaw is List
          ? checksRaw
                .whereType<Map>()
                .map((item) => item.cast<String, dynamic>())
                .toList()
          : const [],
      trustOrigin: string('trust_origin'),
      effect: string('effect'),
      limits: string('limits'),
      evidencePaths: evidenceRaw is List
          ? evidenceRaw
                .map(
                  (item) =>
                      item is Map ? item['path']?.toString() : item.toString(),
                )
                .whereType<String>()
                .toList()
          : const [],
      rerunContext: string('rerun_context') ?? string('rerun'),
      stale:
          string('comparability') == 'stale' ||
          raw['staleness'] == 'stale' ||
          raw['status'] == 'stale',
    );
  }
}

class RepairViewModel {
  const RepairViewModel({
    required this.concern,
    required this.allowedPath,
    required this.attemptCount,
    required this.candidateStatus,
    required this.baselineRevalidated,
    required this.finalResult,
  });
  final String? concern;
  final String? allowedPath;
  final int? attemptCount;
  final String? candidateStatus;
  final String? baselineRevalidated;
  final String finalResult;

  factory RepairViewModel.fromPayload(
    Object? payload,
    Map<String, dynamic> raw,
  ) {
    final map = payload is Map ? payload : const <Object?, Object?>{};
    Object? value(String key) => map[key] ?? raw[key];
    final candidate = value('candidate') ?? value('import_status');
    final result =
        value('final_result')?.toString() ??
        value('result')?.toString() ??
        'UNKNOWN';
    return RepairViewModel(
      concern:
          value('targeted_concern')?.toString() ?? value('concern')?.toString(),
      allowedPath:
          value('allowed_path')?.toString() ?? value('path_scope')?.toString(),
      attemptCount: value('attempt_count') is num
          ? (value('attempt_count') as num).toInt()
          : null,
      candidateStatus: candidate?.toString(),
      baselineRevalidated:
          value('live_baseline_revalidation')?.toString() ??
          value('baseline_revalidated')?.toString(),
      finalResult:
          const {
            'RESOLVED',
            'UNCHANGED',
            'REGRESSED',
            'UNKNOWN',
          }.contains(result)
          ? result
          : 'UNKNOWN',
    );
  }
}
