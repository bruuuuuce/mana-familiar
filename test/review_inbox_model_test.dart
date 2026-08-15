import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/review_inbox_model.dart';
import 'package:mana_familiar/mana_inspect.dart';

void main() {
  test(
    'derives, prioritizes, and de-duplicates explicit catalog attention',
    () {
      final model = ReviewInboxModel.fromCatalog(
        _catalog([
          _artifact(
            'stale:evidence',
            'evidence',
            'index',
            'available',
            staleness: 'stale',
          ),
          _artifact(
            'learning:learning-deadbeef',
            'learning',
            'file',
            'candidate',
          ),
          _artifact(
            'verification:failed',
            'workspace',
            'verification-result',
            'failed',
          ),
          _artifact(
            'verification:failed',
            'workspace',
            'verification-result',
            'failed',
          ),
          _artifact(
            'artifact:bad',
            'unknown',
            'unknown',
            'malformed',
            diagnostic: 'malformed_json',
          ),
        ]),
      );

      expect(model.items.map((item) => item.artifact.id), [
        'artifact:bad',
        'verification:failed',
        'learning:learning-deadbeef',
        'stale:evidence',
      ]);
      expect(
        model.filtered(ReviewInboxFilter.pending).single.command?.shellDisplay,
        'mana learning review learning-deadbeef',
      );
    },
  );

  test('does not guess a command from malicious or incomplete metadata', () {
    final model = ReviewInboxModel.fromCatalog(
      _catalog([
        _artifact(
          'learning:bad',
          'learning',
          'file',
          'candidate',
          candidateId: 'learning-deadbeef; touch /tmp/unsafe',
        ),
        _artifact(
          'verification:failed',
          'workspace',
          'verification-result',
          'failed',
        ),
      ]),
    );

    final candidate = model.items.firstWhere(
      (item) => item.category == ReviewInboxCategory.learningCandidate,
    );
    expect(candidate.command, isNull);
    expect(candidate.nextStep, contains('did not provide'));
    expect(
      ManaCliHandoff.learningReview('learning-deadbeef; touch /tmp/unsafe'),
      isNull,
    );
    expect(
      model.items
          .firstWhere((item) => item.artifact.id == 'verification:failed')
          .command,
      isNull,
    );
  });

  test('keeps owner, approval, and explicit related references traceable', () {
    final item = ReviewInboxModel.fromCatalog(
      _catalog([
        _artifact(
          'review:blocking',
          'workspace',
          'review',
          'blocked',
          owner: 'release-owner',
          approval: 'required',
          relations: [
            {'artifact_id': 'verification:run-1'},
            {
              'source': {'path': 'lib/payment.dart'},
            },
          ],
        ),
      ]),
    ).items.single;

    expect(item.category, ReviewInboxCategory.blockingReview);
    expect(item.owner, 'release-owner');
    expect(item.approvalRequirement, 'required');
    expect(item.relatedReferences, ['lib/payment.dart', 'verification:run-1']);
  });

  test(
    'resolved items disappear when a refreshed catalog no longer reports attention',
    () {
      final pending = ReviewInboxModel.fromCatalog(
        _catalog([
          _artifact(
            'learning:learning-deadbeef',
            'learning',
            'file',
            'candidate',
          ),
        ]),
      );
      final refreshed = ReviewInboxModel.fromCatalog(
        _catalog([
          _artifact(
            'learning:learning-deadbeef',
            'learning',
            'file',
            'reviewed',
          ),
        ]),
      );

      expect(pending.items, hasLength(1));
      expect(refreshed.items, isEmpty);
    },
  );
}

ManaInspectCatalog _catalog(List<Map<String, dynamic>> artifacts) =>
    ManaInspectCatalog.fromJson({
      'schema': inspectArtifactsSchema,
      'artifacts': artifacts,
      'guarantees': const {},
      'diagnostics': const [],
    });

Map<String, dynamic> _artifact(
  String id,
  String family,
  String kind,
  String status, {
  String? staleness,
  String? candidateId,
  String? diagnostic,
  String? owner,
  String? approval,
  List<Map<String, dynamic>>? relations,
}) => {
  'artifact_id': id,
  'path': '.mana/$id.json',
  'family': family,
  'kind': kind,
  'status': status,
  'staleness': ?staleness,
  'candidateId': ?candidateId,
  'diagnostic': ?diagnostic,
  'owner': ?owner,
  'approval_requirement': ?approval,
  'relations': ?relations,
};
