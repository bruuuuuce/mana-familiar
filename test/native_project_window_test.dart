import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/native_project_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mana_familiar/project_window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('uses the native project picker on macOS', () async {
    const project = '/fixtures/mana-project';
    final nativeCalls = <MethodCall>[];
    var fallbackCalled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return project;
    });

    final selected = await NativeProjectWindow.chooseProject(
      directoryPicker: () async {
        fallbackCalled = true;
        return '/fixtures/fallback-project';
      },
    );

    expect(selected, project);
    expect(nativeCalls.map((call) => call.method), ['chooseProject']);
    expect(fallbackCalled, isFalse);
  }, skip: !Platform.isMacOS);

  test(
    'uses the cross-platform directory picker outside macOS',
    () async {
      const project = r'C:\Users\tester\mana-project';
      var pickerCalls = 0;
      var nativeCalled = false;
      messenger.setMockMethodCallHandler(channel, (_) async {
        nativeCalled = true;
        return '/fixtures/native-project';
      });

      final selected = await NativeProjectWindow.chooseProject(
        directoryPicker: () async {
          pickerCalls++;
          return project;
        },
      );

      expect(selected, project);
      expect(pickerCalls, 1);
      expect(nativeCalled, isFalse);
    },
    skip: Platform.isMacOS,
  );
}
