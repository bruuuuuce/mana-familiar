import 'mana_inspect.dart';

enum ReviewInboxCategory {
  blockingReview,
  failedVerification,
  boundedRepair,
  pendingDecision,
  staleEvidence,
  learningCandidate,
  incompatibleArtifact,
}

enum ReviewInboxPriority { blocker, pending, warning, unknown }

enum ReviewInboxFilter { all, blockers, pending, warnings, unknown }

/// Typed command arguments for a documented, human-triggered Mana action.
/// This object is presentation-only: Familiar never executes it.
class ManaCliHandoff {
  const ManaCliHandoff._(this.arguments);

  final List<String> arguments;

  static ManaCliHandoff? learningReview(String candidateId) {
    if (!RegExp(r'^learning-[a-f0-9]{8}$').hasMatch(candidateId)) return null;
    return ManaCliHandoff._(['mana', 'learning', 'review', candidateId]);
  }

  String get shellDisplay => arguments.map(_shellQuote).join(' ');

  static String _shellQuote(String value) {
    if (RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(value)) return value;
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }
}

class ReviewInboxItem {
  const ReviewInboxItem({
    required this.artifact,
    required this.category,
    required this.priority,
    required this.reason,
    required this.nextStep,
    required this.updatedAt,
    required this.relatedReferences,
    this.owner,
    this.approvalRequirement,
    this.command,
  });

  final ManaInspectArtifactSummary artifact;
  final ReviewInboxCategory category;
  final ReviewInboxPriority priority;
  final String reason;
  final String nextStep;
  final String? updatedAt;
  final List<String> relatedReferences;
  final String? owner;
  final String? approvalRequirement;
  final ManaCliHandoff? command;

  String get title => switch (category) {
    ReviewInboxCategory.blockingReview => 'Blocking review state',
    ReviewInboxCategory.failedVerification => 'Failed verification',
    ReviewInboxCategory.boundedRepair => 'Bounded repair needs a decision',
    ReviewInboxCategory.pendingDecision => 'Pending decision or approval',
    ReviewInboxCategory.staleEvidence => 'Stale or missing evidence',
    ReviewInboxCategory.learningCandidate =>
      'Learning candidate awaiting review',
    ReviewInboxCategory.incompatibleArtifact => 'Artifact needs investigation',
  };
}

/// Conservative, deterministic inbox derivation from catalog metadata only.
/// It deliberately does not inspect `.mana`, infer an owner, or guess a CLI.
class ReviewInboxModel {
  const ReviewInboxModel._(this.items);

  final List<ReviewInboxItem> items;

  factory ReviewInboxModel.fromCatalog(ManaInspectCatalog catalog) {
    final unique = <String, ReviewInboxItem>{};
    for (final artifact in catalog.artifacts) {
      final item = _fromArtifact(artifact);
      if (item != null) unique.putIfAbsent(artifact.id, () => item);
    }
    final items = unique.values.toList()
      ..sort((left, right) {
        final priority = left.priority.index.compareTo(right.priority.index);
        if (priority != 0) return priority;
        final pending = _pendingRank(left).compareTo(_pendingRank(right));
        if (pending != 0) return pending;
        return left.artifact.id.compareTo(right.artifact.id);
      });
    return ReviewInboxModel._(items);
  }

  List<ReviewInboxItem> filtered(ReviewInboxFilter filter) => items
      .where(
        (item) => switch (filter) {
          ReviewInboxFilter.all => true,
          ReviewInboxFilter.blockers =>
            item.priority == ReviewInboxPriority.blocker,
          ReviewInboxFilter.pending =>
            item.priority == ReviewInboxPriority.pending,
          ReviewInboxFilter.warnings =>
            item.priority == ReviewInboxPriority.warning,
          ReviewInboxFilter.unknown =>
            item.priority == ReviewInboxPriority.unknown,
        },
      )
      .toList();

  static ReviewInboxItem? _fromArtifact(ManaInspectArtifactSummary artifact) {
    final values =
        '${artifact.family} ${artifact.kind} ${artifact.raw['schema'] ?? ''} ${artifact.path}'
            .toLowerCase();
    final status = artifact.status.toLowerCase();
    final owner = _string(artifact.raw['owner']);
    final approval =
        _string(artifact.raw['approval_requirement']) ??
        _string(artifact.raw['approval_status']) ??
        _string(artifact.raw['human_approval_required']);
    final common = _Common(
      artifact: artifact,
      owner: owner,
      approval: approval,
      updatedAt: _updatedAt(artifact.raw['updated_at']),
      related: _relatedReferences(artifact.raw),
    );

    final repair = values.contains('repair');
    final review = values.contains('review');
    final verification = values.contains('verification');
    final decision = values.contains('decision') || values.contains('approval');
    final candidate = artifact.family == 'learning' && status == 'candidate';
    final stale =
        status == 'stale' ||
        status == 'missing' ||
        artifact.raw['staleness'] == 'stale' ||
        artifact.raw['staleness'] == 'missing';
    final awaitingDecision =
        artifact.raw['awaiting_human_decision'] == true ||
        artifact.raw['human_decision_required'] == true ||
        artifact.raw['approval_required'] == true;

    if (status == 'malformed' || status == 'quarantined') {
      return common.item(
        category: ReviewInboxCategory.incompatibleArtifact,
        priority: ReviewInboxPriority.blocker,
        reason:
            artifact.raw['diagnostic']?.toString() ??
            'Mana reported an incompatible or unsafe artifact.',
      );
    }
    if (repair && (status == 'blocked' || awaitingDecision)) {
      return common.item(
        category: ReviewInboxCategory.boundedRepair,
        priority: status == 'blocked'
            ? ReviewInboxPriority.blocker
            : ReviewInboxPriority.pending,
        reason: 'Mana reports a bounded repair awaiting a human decision.',
      );
    }
    if (review && status == 'blocked') {
      return common.item(
        category: ReviewInboxCategory.blockingReview,
        priority: ReviewInboxPriority.blocker,
        reason: 'Mana reports a blocking review state.',
      );
    }
    if (verification && (status == 'failed' || status == 'blocked')) {
      return common.item(
        category: ReviewInboxCategory.failedVerification,
        priority: ReviewInboxPriority.blocker,
        reason: 'Mana reports a failed verification result.',
      );
    }
    if (decision &&
        (status == 'pending' || status == 'blocked' || awaitingDecision)) {
      return common.item(
        category: ReviewInboxCategory.pendingDecision,
        priority: status == 'blocked'
            ? ReviewInboxPriority.blocker
            : ReviewInboxPriority.pending,
        reason: 'Mana records a decision or approval gate that remains open.',
      );
    }
    if (candidate) {
      final candidateId = _candidateId(artifact);
      final command = candidateId == null
          ? null
          : ManaCliHandoff.learningReview(candidateId);
      return common.item(
        category: ReviewInboxCategory.learningCandidate,
        priority: ReviewInboxPriority.pending,
        reason: 'Mana reports a learning candidate awaiting human review.',
        command: command,
        missingCommandMetadata: command == null,
      );
    }
    if (stale) {
      return common.item(
        category: ReviewInboxCategory.staleEvidence,
        priority: ReviewInboxPriority.warning,
        reason: 'Mana reports evidence that is stale or missing.',
      );
    }
    if (status == 'failed' || status == 'blocked') {
      return common.item(
        category: ReviewInboxCategory.incompatibleArtifact,
        priority: ReviewInboxPriority.blocker,
        reason: 'Mana reports an unresolved $status artifact.',
      );
    }
    return null;
  }

  static int _pendingRank(ReviewInboxItem item) => switch (item.priority) {
    ReviewInboxPriority.blocker => 0,
    ReviewInboxPriority.pending => 0,
    ReviewInboxPriority.warning => 1,
    ReviewInboxPriority.unknown => 2,
  };

  static String? _candidateId(ManaInspectArtifactSummary artifact) {
    final rawId =
        _string(artifact.raw['candidate_id']) ??
        _string(artifact.raw['candidateId']) ??
        (artifact.id.startsWith('learning:')
            ? artifact.id.substring('learning:'.length)
            : null);
    return rawId != null && RegExp(r'^learning-[a-f0-9]{8}$').hasMatch(rawId)
        ? rawId
        : null;
  }

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static String? _updatedAt(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is Map) {
      final recorded = value['value'];
      if (recorded != null && recorded.toString().isNotEmpty) {
        return recorded.toString();
      }
    }
    return null;
  }

  static List<String> _relatedReferences(Map<String, dynamic> raw) {
    final values = <String>{};
    void add(Object? value) {
      if (value is String && value.trim().isNotEmpty) values.add(value);
    }

    final relations = raw['relations'];
    if (relations is List) {
      for (final relation in relations.whereType<Map>()) {
        add(relation['artifact_id']);
        add(relation['to']);
        add(relation['evidence_id']);
        final source = relation['source'];
        if (source is Map) add(source['path']);
      }
    }
    final evidence = raw['evidence'] ?? raw['evidence_paths'];
    if (evidence is List) {
      for (final value in evidence) {
        add(value is Map ? value['path'] ?? value['id'] : value);
      }
    }
    return values.toList()..sort();
  }
}

class _Common {
  const _Common({
    required this.artifact,
    required this.owner,
    required this.approval,
    required this.updatedAt,
    required this.related,
  });

  final ManaInspectArtifactSummary artifact;
  final String? owner;
  final String? approval;
  final String? updatedAt;
  final List<String> related;

  ReviewInboxItem item({
    required ReviewInboxCategory category,
    required ReviewInboxPriority priority,
    required String reason,
    ManaCliHandoff? command,
    bool missingCommandMetadata = true,
  }) => ReviewInboxItem(
    artifact: artifact,
    category: category,
    priority: priority,
    reason: reason,
    owner: owner,
    approvalRequirement: approval,
    updatedAt: updatedAt,
    relatedReferences: related,
    command: command,
    nextStep: command != null
        ? 'Copy the documented Mana command and run it deliberately outside Familiar.'
        : missingCommandMetadata
        ? 'Open this artifact first. Mana did not provide the typed action metadata needed for a safe command handoff.'
        : 'Open this artifact and inspect the recorded evidence before choosing a governed action.',
  );
}
