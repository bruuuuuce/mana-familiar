import 'mana_inspect.dart';

class ObservatoryAttention {
  const ObservatoryAttention({required this.artifact, required this.reason});
  final ManaInspectArtifactSummary artifact;
  final String reason;
}

/// Legacy catalog-only presentation adapter. It is not a semantic read model:
/// in particular, catalog order is never producer-defined activity. New
/// semantic UI must use [ManaActivityResponse] through [ManaSemanticRepository].
class ObservatoryOverview {
  const ObservatoryOverview({
    required this.failed,
    required this.blocking,
    required this.staleOrMissing,
    required this.attention,
    required this.lastMeaningfulActivity,
    required this.partial,
  });
  final List<ManaInspectArtifactSummary> failed;
  final List<ManaInspectArtifactSummary> blocking;
  final List<ManaInspectArtifactSummary> staleOrMissing;
  final List<ObservatoryAttention> attention;
  final ManaInspectArtifactSummary? lastMeaningfulActivity;
  final bool partial;

  factory ObservatoryOverview.fromCatalog(ManaInspectCatalog catalog) {
    final failed = catalog.artifacts
        .where((item) => item.status == 'failed')
        .toList();
    final blocking = catalog.artifacts
        .where((item) => item.status == 'blocked')
        .toList();
    final staleOrMissing = catalog.artifacts
        .where(
          (item) =>
              item.status == 'stale' ||
              item.status == 'missing' ||
              item.raw['staleness'] == 'stale' ||
              item.raw['staleness'] == 'missing',
        )
        .toList();
    final attention = <ObservatoryAttention>[
      ...failed.map(
        (item) => ObservatoryAttention(artifact: item, reason: 'Failed'),
      ),
      ...blocking.map(
        (item) => ObservatoryAttention(artifact: item, reason: 'Blocked'),
      ),
      ...staleOrMissing.map(
        (item) => ObservatoryAttention(
          artifact: item,
          reason: 'Stale or missing evidence',
        ),
      ),
      ...catalog.artifacts
          .where(
            (item) =>
                item.status == 'malformed' || item.status == 'quarantined',
          )
          .map(
            (item) => ObservatoryAttention(
              artifact: item,
              reason: 'Needs inspection',
            ),
          ),
    ];
    return ObservatoryOverview(
      failed: failed,
      blocking: blocking,
      staleOrMissing: staleOrMissing,
      attention: attention,
      lastMeaningfulActivity: catalog.artifacts.isEmpty
          ? null
          : catalog.artifacts.last,
      partial: catalog.partial,
    );
  }
}
