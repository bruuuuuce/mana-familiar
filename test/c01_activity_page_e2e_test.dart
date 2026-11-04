import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/mana_inspect.dart';

Future<Map<String, String>> snapshotMana(Directory project) async {
  final root = Directory('${project.path}/.mana');
  final snapshot = <String, String>{};
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    final relative = entry.path.substring(root.path.length);
    if (entry is File) {
      snapshot[relative] = 'file:${base64Encode(await entry.readAsBytes())}';
    } else if (entry is Directory) {
      snapshot[relative] = 'directory';
    } else if (entry is Link) {
      snapshot[relative] = 'link:${await entry.target()}';
    }
  }
  return snapshot;
}

Matcher failure(ManaInspectFailure kind, [String? message]) =>
    isA<ManaInspectException>()
        .having((error) => error.kind, 'kind', kind)
        .having(
          (error) => error.message,
          'message',
          message == null ? anything : contains(message),
        );

void main() {
  final manaRoot = Platform.environment['MANA_ROOT'];
  test(
    'current Mana activity pages cross the real Familiar client boundary',
    () async {
      final project = await Directory.systemTemp.createTemp(
        'c01-activity-page-',
      );
      addTearDown(() => project.delete(recursive: true));
      final events = File(
        '${project.path}/.mana/runtime/events/synthetic.jsonl',
      );
      await events.parent.create(recursive: true);
      final records = <Map<String, String>>[
        for (var i = 0; i < 501; i++)
          {
            'eventId': 'synthetic:${i.toString().padLeft(4, '0')}',
            'timestamp': '2026-10-04T08:00:00Z',
          },
        {'eventId': 'synthetic:duplicate', 'timestamp': '2026-10-04T08:00:01Z'},
        {'eventId': 'synthetic:duplicate', 'timestamp': '2026-10-04T08:00:02Z'},
      ];
      await events.writeAsString(records.map(jsonEncode).join('\n') + '\n');
      final original = await snapshotMana(project);
      final client = ManaInspectClient(
        projectRoot: project.path,
        manaRoot: manaRoot,
      );
      final capabilities = await client.project();
      expect(capabilities.supportsActivityPages, isTrue);

      final direct = await Process.run('$manaRoot/scripts/mana-inspect.sh', [
        '--project-root',
        project.path,
        'activity-page',
        '--limit',
        '500',
        '--json',
      ]);
      expect(direct.exitCode, 0, reason: direct.stderr.toString());
      final response =
          jsonDecode(direct.stdout as String) as Map<String, dynamic>;
      expect(response['schema'], inspectActivityPageSchema);
      expect(
        (response['guarantees'] as Map<String, dynamic>)['writes'],
        isFalse,
      );

      final full = await client.activity(capabilities: capabilities);
      final first = await client.activityPage(capabilities: capabilities);
      final repeated = await client.activityPage(capabilities: capabilities);
      expect(
        first.activity.events.map((e) => e.id),
        orderedEquals(repeated.activity.events.map((e) => e.id)),
      );
      expect(first.revision, repeated.revision);
      expect(first.nextCursor, isNotNull);
      final seen = <ManaActivityEvent>[];
      var page = first;
      while (true) {
        expect(page.revision, first.revision);
        expect(page.total, full.events.length);
        expect(page.activity.events.length, lessThanOrEqualTo(500));
        seen.addAll(page.activity.events);
        final cursor = page.nextCursor;
        if (cursor == null) break;
        expect(seen.length, lessThan(page.total));
        page = await client.activityPage(
          capabilities: capabilities,
          cursor: cursor,
        );
      }
      expect(
        seen.map((e) => e.id),
        orderedEquals(full.events.map((e) => e.id)),
      );
      expect(seen.map((e) => e.id).toSet().length, seen.length);
      expect(seen.length, first.total);
      final duplicate = seen.where((e) => e.id == 'synthetic:duplicate').single;
      expect(duplicate.timestamp, '2026-10-04T08:00:02Z');
      int epoch(String value) =>
          int.tryParse(value) ??
          DateTime.parse(value).millisecondsSinceEpoch ~/ 1000;
      for (var i = 1; i < seen.length; i++) {
        final previous = seen[i - 1];
        final current = seen[i];
        final comparison = epoch(
          previous.timestamp,
        ).compareTo(epoch(current.timestamp));
        expect(
          comparison < 0 ||
              (comparison == 0 && previous.id.compareTo(current.id) <= 0),
          isTrue,
        );
      }
      await expectLater(
        client.activityPage(capabilities: capabilities, cursor: '../cursor'),
        throwsA(failure(ManaInspectFailure.command, 'Exit 4')),
      );
      expect(await snapshotMana(project), original);

      // These two adversarial responses are mutations of real producer output.
      // They exercise the real client decoder, not a claim that Mana emits them.
      Future<ProcessResult> mutated(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
        required bool duplicate,
      }) async {
        final actual = await Process.run(
          executable,
          arguments,
          workingDirectory: workingDirectory,
        );
        if (actual.exitCode != 0 || !arguments.contains('activity-page'))
          return actual;
        final json =
            jsonDecode(actual.stdout as String) as Map<String, dynamic>;
        if (duplicate) {
          final items = json['events'] as List<dynamic>;
          items[1] = items[0];
        } else {
          json['schema'] = 'mana.inspect.activity-page/v999';
        }
        return ProcessResult(
          actual.pid,
          actual.exitCode,
          jsonEncode(json),
          actual.stderr,
        );
      }

      for (final duplicateResponse in [false, true]) {
        final injected = ManaInspectClient(
          projectRoot: project.path,
          manaRoot: manaRoot,
          run: (executable, arguments, {workingDirectory}) => mutated(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            duplicate: duplicateResponse,
          ),
        );
        await expectLater(
          injected.activityPage(capabilities: capabilities),
          throwsA(
            failure(
              duplicateResponse
                  ? ManaInspectFailure.malformedJson
                  : ManaInspectFailure.unsupportedSchema,
            ),
          ),
        );
      }
      expect(await snapshotMana(project), original);

      // The only workspace write in the test is this deliberate source change.
      await events.writeAsString(
        '${jsonEncode({'eventId': 'synthetic:new', 'timestamp': '2026-10-04T08:00:03Z'})}\n',
        mode: FileMode.append,
      );
      final changed = await snapshotMana(project);
      await expectLater(
        client.activityPage(
          capabilities: capabilities,
          cursor: first.nextCursor,
        ),
        throwsA(
          failure(
            ManaInspectFailure.command,
            'activity_view_changed_or_invalid_cursor',
          ),
        ),
      );
      final restarted = await client.activityPage(capabilities: capabilities);
      expect(restarted.revision, isNot(first.revision));
      expect(restarted.total, first.total + 1);
      expect(await snapshotMana(project), changed);
    },
    skip: manaRoot == null
        ? 'Set MANA_ROOT to run against a real Mana checkout.'
        : false,
  );
}
