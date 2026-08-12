enum FindingSeverity { blocker, warning, information, unknown }

FindingSeverity findingSeverity(Object? value) => switch (value
    ?.toString()
    .toLowerCase()) {
  'blocker' || 'blocking' || 'error' || 'critical' => FindingSeverity.blocker,
  'warning' || 'warn' || 'risk' => FindingSeverity.warning,
  'info' || 'information' || 'note' => FindingSeverity.information,
  _ => FindingSeverity.unknown,
};

class ReviewFinding {
  const ReviewFinding({
    required this.severity,
    required this.summary,
    this.evidence,
    this.source,
  });
  final FindingSeverity severity;
  final String summary;
  final String? evidence;
  final String? source;
}

class ReviewViewModel {
  const ReviewViewModel({
    required this.scope,
    required this.base,
    required this.pr,
    required this.findings,
    required this.missingEvidence,
    required this.humanApprovalRequired,
    required this.recommendation,
  });
  final String? scope;
  final String? base;
  final String? pr;
  final List<ReviewFinding> findings;
  final List<String> missingEvidence;
  final bool? humanApprovalRequired;
  final String? recommendation;

  factory ReviewViewModel.fromPayload(
    Object? payload,
    Map<String, dynamic> raw,
  ) {
    final map = payload is Map ? payload : const <Object?, Object?>{};
    Object? value(String key) => map[key] ?? raw[key];
    String? string(String key) =>
        value(key) is String ? value(key) as String : null;
    final findingsValue = value('findings');
    final findings = findingsValue is List
        ? findingsValue.whereType<Map>().map((entry) {
            final item = entry.cast<String, dynamic>();
            return ReviewFinding(
              severity: findingSeverity(item['severity'] ?? item['status']),
              summary:
                  item['summary']?.toString() ??
                  item['message']?.toString() ??
                  'Unnamed finding',
              evidence:
                  item['evidence_strength']?.toString() ??
                  item['evidence']?.toString(),
              source:
                  item['source_reference']?.toString() ??
                  item['source']?.toString(),
            );
          }).toList()
        : <ReviewFinding>[];
    findings.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    final missing = value('missing_evidence') ?? value('missing_tests');
    return ReviewViewModel(
      scope: string('reviewed_scope') ?? string('scope'),
      base: string('base') ?? string('base_revision'),
      pr: string('pr_identity') ?? string('pr') ?? string('pull_request'),
      findings: findings,
      missingEvidence: missing is List
          ? missing.map((item) => item.toString()).toList()
          : const [],
      humanApprovalRequired: value('human_approval_required') is bool
          ? value('human_approval_required') as bool
          : null,
      recommendation: string('recommendation'),
    );
  }
}

class EvidenceItem {
  const EvidenceItem({required this.id, required this.status, this.summary});
  final String id;
  final String status;
  final String? summary;
}

class EvidenceInventoryModel {
  const EvidenceInventoryModel(this.items);
  final List<EvidenceItem> items;

  factory EvidenceInventoryModel.fromPayload(
    Object? payload,
    Map<String, dynamic> raw,
  ) {
    final map = payload is Map ? payload : const <Object?, Object?>{};
    final source =
        map['items'] ?? map['evidence'] ?? raw['items'] ?? raw['evidence'];
    if (source is! List) return const EvidenceInventoryModel([]);
    return EvidenceInventoryModel(
      source.whereType<Map>().map((entry) {
        final item = entry.cast<String, dynamic>();
        return EvidenceItem(
          id:
              item['artifact_id']?.toString() ??
              item['id']?.toString() ??
              'Unnamed evidence',
          status: item['status']?.toString() ?? 'unknown',
          summary: item['summary']?.toString(),
        );
      }).toList(),
    );
  }
}

class DecisionViewModel {
  const DecisionViewModel({
    required this.state,
    this.owner,
    this.approval,
    this.rationale,
    this.alternatives = const [],
    this.questions = const [],
  });
  final String? state;
  final String? owner;
  final String? approval;
  final String? rationale;
  final List<String> alternatives;
  final List<String> questions;

  factory DecisionViewModel.fromPayload(
    Object? payload,
    Map<String, dynamic> raw,
  ) {
    final map = payload is Map ? payload : const <Object?, Object?>{};
    Object? value(String key) => map[key] ?? raw[key];
    List<String> list(String key) => value(key) is List
        ? (value(key) as List).map((item) => item.toString()).toList()
        : const [];
    return DecisionViewModel(
      state: value('decision_state')?.toString() ?? value('status')?.toString(),
      owner: value('owner')?.toString(),
      approval:
          value('approval_status')?.toString() ??
          value('approval_required')?.toString(),
      rationale: value('rationale')?.toString(),
      alternatives: list('alternatives'),
      questions: list('unresolved_questions'),
    );
  }
}

class GovernanceViewModel {
  const GovernanceViewModel({
    required this.inventory,
    required this.coverage,
    required this.lifecycle,
    required this.staleCount,
    required this.passEvidence,
  });
  final Map<String, Object?> inventory;
  final Map<String, Object?> coverage;
  final Map<String, Object?> lifecycle;
  final Object? staleCount;
  final Object? passEvidence;

  factory GovernanceViewModel.fromPayload(
    Object? payload,
    Map<String, dynamic> raw,
  ) {
    final map = payload is Map ? payload : const <Object?, Object?>{};
    Map<String, Object?> object(String key) => (map[key] ?? raw[key]) is Map
        ? Map<Object?, Object?>.from(
            map[key] ?? raw[key],
          ).map((key, value) => MapEntry(key.toString(), value))
        : const {};
    return GovernanceViewModel(
      inventory: object('inventory'),
      coverage: object('coverage'),
      lifecycle: object('lifecycle_counts'),
      staleCount: map['stale_result_count'] ?? raw['stale_result_count'],
      passEvidence:
          map['current_eval_pass_rate'] ?? raw['current_eval_pass_rate'],
    );
  }
}
