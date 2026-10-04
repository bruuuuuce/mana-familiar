import 'dart:io';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/main.dart' as familiar;

void main() {
  testWidgets('startup leaves semantics activation to the native embedder', (
    tester,
  ) async {
    final preferences = Directory.systemTemp.createTempSync(
      'familiar-bootstrap-semantics-',
    );
    addTearDown(() => preferences.deleteSync(recursive: true));
    final binding = SemanticsBinding.instance;
    final handles = binding.debugOutstandingSemanticsHandles;
    final enabled = binding.semanticsEnabled;
    await tester.runAsync(() async {
      await familiar.main(['--preferences-root', preferences.path]);
    });
    await tester.pump();
    expect(binding.debugOutstandingSemanticsHandles, handles);
    expect(binding.semanticsEnabled, enabled);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(binding.debugOutstandingSemanticsHandles, handles);
  });
}
