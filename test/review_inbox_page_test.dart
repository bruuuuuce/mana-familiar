import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/review_inbox_model.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/review_inbox_page.dart';

void main() {
  testWidgets('filters inbox items and copies but never runs a Mana command', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewInboxPage(
            artifacts: [
              _artifact(
                'verification:failed',
                'workspace',
                'verification-result',
                'failed',
              ),
              _artifact(
                'learning:learning-deadbeef',
                'learning',
                'file',
                'candidate',
              ),
            ],
            onOpenArtifact: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Review Inbox'), findsOneWidget);
    expect(find.text('Copy command'), findsOneWidget);
    expect(
      find.text('Command unavailable: required action metadata is absent.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Copy command'));
    await tester.pump();
    expect(copied, 'mana learning review learning-deadbeef');
    expect(
      find.text('Mana command copied; it has not been run.'),
      findsOneWidget,
    );

    await tester.tap(find.byType(DropdownButton<ReviewInboxFilter>));
    await tester.pump();
    await tester.tap(find.text('Blockers').last);
    await tester.pump();
    expect(find.text('verification:failed'), findsOneWidget);
    expect(find.text('learning:learning-deadbeef'), findsNothing);
  });
}

ManaInspectArtifactSummary _artifact(
  String id,
  String family,
  String kind,
  String status,
) => ManaInspectArtifactSummary.fromJson({
  'artifact_id': id,
  'path': '.mana/$id.json',
  'family': family,
  'kind': kind,
  'status': status,
});
