import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/native_e2e_bridge.dart';

void main() {
  Future<_BridgeResponse> request(
    NativeE2EBridge bridge,
    Map<String, Object?> payload,
  ) async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${bridge.boundPort}/v1/ui'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
    final response = await request.close();
    return _BridgeResponse(
      response.statusCode,
      jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>,
    );
  }

  test(
    'dispatches only registered widget callbacks on the loopback bridge',
    () async {
      final bridge = NativeE2EBridge(port: 0, token: 'test-token');
      await bridge.start();
      addTearDown(bridge.dispose);
      String? selected;
      var commentsOpened = false;
      String? author;
      String? body;
      var published = 0;
      bridge.registerDocument(
        NativeE2EDocumentBindings(
          status: () => {
            'stableSectionAnchors': {'implementation': 'plan'},
          },
          selectSection: (sectionId) async => selected = sectionId,
          openComments: () async => commentsOpened = true,
        ),
      );
      bridge.registerPanel(
        NativeE2EPanelBindings(
          status: () => {
            'composer': {'author': author, 'body': body},
          },
          setComposer: (nextAuthor, nextBody) async {
            author = nextAuthor;
            body = nextBody;
          },
          publish: () async => published++,
        ),
      );

      final status = await request(bridge, {
        'token': 'test-token',
        'action': 'status',
      });
      expect(status.statusCode, HttpStatus.ok);
      expect(status.body['document'], isNotNull);
      expect(status.body['panel'], isNotNull);

      await request(bridge, {
        'token': 'test-token',
        'action': 'selectSection',
        'sectionId': 'implementation',
      });
      await request(bridge, {'token': 'test-token', 'action': 'openComments'});
      await request(bridge, {
        'token': 'test-token',
        'action': 'setComposer',
        'author': 'Ada',
        'body': 'Line one\nLine two',
      });
      await request(bridge, {'token': 'test-token', 'action': 'publish'});

      expect(selected, 'implementation');
      expect(commentsOpened, isTrue);
      expect(author, 'Ada');
      expect(body, 'Line one\nLine two');
      expect(published, 1);

      final denied = await request(bridge, {
        'token': 'wrong',
        'action': 'status',
      });
      expect(denied.statusCode, HttpStatus.unauthorized);
    },
  );
}

class _BridgeResponse {
  const _BridgeResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;
}
