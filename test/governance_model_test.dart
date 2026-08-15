import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/governance_model.dart';

void main() {
  test(
    'orders blockers before warnings and information without hidden scoring',
    () {
      final model = ReviewViewModel.fromPayload({
        'findings': [
          {'severity': 'info', 'summary': 'note'},
          {'severity': 'warning', 'summary': 'risk'},
          {'severity': 'blocker', 'summary': 'must decide'},
        ],
      }, {});
      expect(model.findings.map((finding) => finding.severity), [
        FindingSeverity.blocker,
        FindingSeverity.warning,
        FindingSeverity.information,
      ]);
    },
  );

  test('does not invent an approval when review metadata omits it', () {
    final model = ReviewViewModel.fromPayload({'reviewed_scope': 'branch'}, {});
    expect(model.humanApprovalRequired, isNull);
  });

  test(
    'keeps evidence status and governance coverage separate from pass evidence',
    () {
      final evidence = EvidenceInventoryModel.fromPayload({
        'items': [
          {'id': 'missing-log', 'status': 'missing'},
          {'id': 'old-run', 'status': 'stale'},
          {'id': 'signed', 'status': 'untrusted'},
        ],
      }, {});
      expect(evidence.items.map((item) => item.status), [
        'missing',
        'stale',
        'untrusted',
      ]);

      final governance = GovernanceViewModel.fromPayload({
        'inventory': {'profiles': 3},
        'coverage': {'profiles': '1/3'},
        'stale_result_count': 2,
        'current_eval_pass_rate': {'passed': 1, 'total': 2},
      }, {});
      expect(governance.inventory['profiles'], 3);
      expect(governance.coverage['profiles'], '1/3');
      expect(governance.staleCount, 2);
    },
  );

  test(
    'preserves unknown fields and structured decisions with unresolved questions',
    () {
      final decision = DecisionViewModel.fromPayload({
        'decision_state': 'needs_human_decision',
        'alternatives': ['a', 'b'],
        'unresolved_questions': ['Which base?'],
        'future_field': true,
      }, {});
      expect(decision.state, 'needs_human_decision');
      expect(decision.questions, ['Which base?']);
    },
  );
}
