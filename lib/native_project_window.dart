import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the macOS window chrome in step with the project shown by Flutter.
///
/// The native side owns File > Open and its recent-project list, so it can
/// create another application window without placing a second menu in the UI.
class NativeProjectWindow {
  NativeProjectWindow._();

  static const _channel = MethodChannel('mana_familiar/project_window');
  static Future<void> Function()? _prepareToClose;

  /// Installs the Flutter half of the native close handshake. The macOS
  /// window delegate keeps Close/Quit pending until this future completes.
  /// This is intentionally process-local: each Runner owns one window and
  /// one draft session.
  static void installClosePreparation(Future<void> Function() callback) {
    _prepareToClose = callback;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'prepareToClose') {
        throw MissingPluginException('Unsupported native lifecycle call.');
      }
      final prepare = _prepareToClose;
      if (prepare == null) return;
      await prepare();
    });
    // Before this acknowledgement arrives there is no mounted Flutter text
    // field to preserve, so native close can remain responsive during launch.
    _channel.invokeMethod<void>('closePreparationReady').catchError((_) {});
  }

  static Future<void> presentProject(String projectRoot) async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('presentProject', {
        'projectRoot': projectRoot,
      });
    } on MissingPluginException {
      // Native menu integration is deliberately macOS-only.
    }
  }

  /// Lets a Flutter empty state use the same native folder chooser as File.
  static Future<String?> chooseProject() async {
    if (!Platform.isMacOS) return null;
    try {
      return await _channel.invokeMethod<String>('chooseProject');
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> clearRecentProjects() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('clearRecentProjects');
    } on MissingPluginException {
      // Native menu integration is deliberately macOS-only.
    }
  }
}
