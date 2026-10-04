import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/human_feedback.dart';

void main() {
  const target = HumanFeedbackTarget(
    projectId: 'project:close',
    artifactId: 'file:plan.md',
    artifactRevision: 'sha256:close',
  );
  HumanFeedbackDraft draft(String body) => HumanFeedbackDraft(
    target: target,
    body: body,
    author: 'Close test',
    idempotencyKey: 'close-draft',
    updatedAt: DateTime.utc(2026, 10, 4),
  );

  test('native close waits for a debounce write already in flight', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final store = HumanFeedbackDraftStore(
      Directory.systemTemp,
      debounce: const Duration(days: 1),
      persistDraft: (_, _) async {
        started.complete();
        await release.future;
      },
    );
    store.schedule(draft('Pending text'));
    final writing = store.flush(target);
    await started.future;
    var closed = false;
    final close = store.flushAll().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    release.complete();
    await writing;
    await close;
    expect(closed, isTrue);
  });

  test('failed save retains text for the next close attempt', () async {
    var fail = true;
    final saved = <String>[];
    final store = HumanFeedbackDraftStore(
      Directory.systemTemp,
      debounce: const Duration(days: 1),
      persistDraft: (_, value) async {
        if (fail) throw const FileSystemException('Test disk unavailable');
        saved.add(value.body);
      },
    );
    store.schedule(draft('Recover this text'));
    await expectLater(store.flushAll(), throwsA(isA<FileSystemException>()));
    fail = false;
    await store.flushAll();
    expect(saved, ['Recover this text']);
  });

  test('an older failed write does not replace a newer edit', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final saved = <String>[];
    final store = HumanFeedbackDraftStore(
      Directory.systemTemp,
      debounce: const Duration(days: 1),
      persistDraft: (_, value) async {
        if (value.body == 'Old') {
          started.complete();
          await release.future;
          throw const FileSystemException('Test write failure');
        }
        saved.add(value.body);
      },
    );
    store.schedule(draft('Old'));
    final writing = store.flush(target);
    final error = expectLater(writing, throwsA(isA<FileSystemException>()));
    await started.future;
    store.schedule(draft('New'));
    release.complete();
    await error;
    await store.flushAll();
    expect(saved, ['New']);
  });
}
