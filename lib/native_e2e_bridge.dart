import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Debug-only, loopback-only bridge for the native desktop acceptance driver.
///
/// It can invoke and observe mounted Flutter widgets, but deliberately has no
/// repository or filesystem access. Real focus and process lifecycle remain
/// macOS actions in the shell gate. The bridge is unavailable in profile and
/// release builds so it cannot become a product control surface.
class NativeE2EBridge {
  NativeE2EBridge({required this.port, required this.token});

  final int port;
  final String token;
  HttpServer? _server;
  NativeE2EDocumentBindings? _document;
  NativeE2EPanelBindings? _panel;
  NativeE2EObservatoryBindings? _observatory;

  int get boundPort => _server?.port ?? port;

  Future<void> start() async {
    if (!kDebugMode) {
      throw StateError('Native E2E bridge is available only in debug builds.');
    }
    if (token.isEmpty) throw ArgumentError.value(token, 'token', 'is empty');
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    unawaited(_serve());
  }

  Future<void> dispose() async {
    _document = null;
    _panel = null;
    _observatory = null;
    await _server?.close(force: true);
    _server = null;
  }

  void registerDocument(NativeE2EDocumentBindings bindings) {
    _document = bindings;
  }

  void unregisterDocument(NativeE2EDocumentBindings bindings) {
    if (identical(_document, bindings)) _document = null;
  }

  void registerPanel(NativeE2EPanelBindings bindings) {
    _panel = bindings;
  }

  void unregisterPanel(NativeE2EPanelBindings bindings) {
    if (identical(_panel, bindings)) _panel = null;
  }

  void registerObservatory(NativeE2EObservatoryBindings bindings) {
    _observatory = bindings;
  }

  void unregisterObservatory(NativeE2EObservatoryBindings bindings) {
    if (identical(_observatory, bindings)) _observatory = null;
  }

  Future<void> _serve() async {
    final server = _server;
    if (server == null) return;
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method != 'POST' || request.uri.path != '/v1/ui') {
        await _write(request, HttpStatus.notFound, {'error': 'not_found'});
        return;
      }
      final source = await utf8.decoder.bind(request).join();
      final input = jsonDecode(source);
      if (input is! Map<String, dynamic> || input['token'] != token) {
        await _write(request, HttpStatus.unauthorized, {
          'error': 'unauthorized',
        });
        return;
      }
      final action = input['action'];
      if (action is! String) {
        await _write(request, HttpStatus.badRequest, {
          'error': 'invalid_action',
        });
        return;
      }
      final result = await _dispatch(action, input);
      await _write(request, HttpStatus.ok, result);
    } on FormatException {
      await _write(request, HttpStatus.badRequest, {'error': 'invalid_json'});
    } catch (error) {
      await _write(request, HttpStatus.conflict, {'error': '$error'});
    }
  }

  Future<Map<String, Object?>> _dispatch(
    String action,
    Map<String, dynamic> input,
  ) async {
    switch (action) {
      case 'status':
        return _status();
      case 'selectSection':
        final sectionId = input['sectionId'];
        if (sectionId is! String) throw ArgumentError('sectionId is required');
        final document = _document;
        if (document == null) throw StateError('document is not ready');
        await document.selectSection(sectionId);
        return _status();
      case 'openComments':
        final document = _document;
        if (document == null) throw StateError('document is not ready');
        await document.openComments();
        return _status();
      case 'setComposer':
        final author = input['author'];
        final body = input['body'];
        if (author is! String || body is! String) {
          throw ArgumentError('author and body are required');
        }
        final panel = _panel;
        if (panel == null) throw StateError('comment panel is not ready');
        await panel.setComposer(author, body);
        return _status();
      case 'publish':
        final panel = _panel;
        if (panel == null) throw StateError('comment panel is not ready');
        await panel.publish();
        return _status();
      default:
        throw ArgumentError('unsupported action: $action');
    }
  }

  Map<String, Object?> _status() => {
    'schemaVersion': 'mana.familiar.native-e2e-ui/v1',
    'document': _document?.status(),
    'panel': _panel?.status(),
    'observatory': _observatory?.status(),
  };

  Future<void> _write(
    HttpRequest request,
    int status,
    Map<String, Object?> value,
  ) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(value));
    await request.response.close();
  }
}

/// Widget-owned document controls exposed to the local debug driver.
///
/// This carries callbacks only. Keeping it free of model or repository types
/// prevents the test transport from becoming a second producer client.
class NativeE2EDocumentBindings {
  const NativeE2EDocumentBindings({
    required this.status,
    required this.selectSection,
    required this.openComments,
  });

  final Map<String, Object?> Function() status;
  final Future<void> Function(String sectionId) selectSection;
  final Future<void> Function() openComments;
}

/// Widget-owned feedback-panel controls exposed to the local debug driver.
class NativeE2EPanelBindings {
  const NativeE2EPanelBindings({
    required this.status,
    required this.setComposer,
    required this.publish,
  });

  final Map<String, Object?> Function() status;
  final Future<void> Function(String author, String body) setComposer;
  final Future<void> Function() publish;
}

/// Payload-free mounted-shell state used only to diagnose a failed UI setup.
class NativeE2EObservatoryBindings {
  const NativeE2EObservatoryBindings({required this.status});

  final Map<String, Object?> Function() status;
}
