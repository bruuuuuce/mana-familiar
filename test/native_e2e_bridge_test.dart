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
      var settledFrames = 0;
      final bridge = NativeE2EBridge(
        port: 0,
        token: 'test-token',
        settleFrame: () async {
          settledFrames++;
        },
      );
      await bridge.start();
      addTearDown(bridge.dispose);
      String? selected;
      var commentsOpened = false;
      String? author;
      String? body;
      var published = 0;
      String? replyThread;
      String? replyBody;
      var replyPublished = 0;
      var retried = 0;
      var decisionOpened = false;
      String? decisionId;
      String? optionId;
      String? rationale;
      var decisionPublished = 0;
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
          setReply: (threadId, body) async {
            replyThread = threadId;
            replyBody = body;
          },
          publishReply: (threadId) async {
            expect(threadId, replyThread);
            replyPublished++;
          },
          retry: () async => retried++,
        ),
      );
      bridge.registerArtifact(
        NativeE2EArtifactBindings(
          status: () => {'artifactId': 'plan'},
          openDecision: () async => decisionOpened = true,
        ),
      );
      bridge.registerDecision(
        NativeE2EDecisionBindings(
          status: () => {'selectedDecisionId': decisionId},
          setDecision: (nextDecisionId, nextOptionId, _, nextRationale) async {
            decisionId = nextDecisionId;
            optionId = nextOptionId;
            rationale = nextRationale;
          },
          publish: () async => decisionPublished++,
        ),
      );

      final status = await request(bridge, {
        'token': 'test-token',
        'action': 'status',
      });
      expect(status.statusCode, HttpStatus.ok);
      expect(settledFrames, 1);
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
      await request(bridge, {
        'token': 'test-token',
        'action': 'setReply',
        'threadId': 'thread-1',
        'body': 'Confirmed',
      });
      await request(bridge, {
        'token': 'test-token',
        'action': 'publishReply',
        'threadId': 'thread-1',
      });
      await request(bridge, {'token': 'test-token', 'action': 'retryFeedback'});
      await request(bridge, {'token': 'test-token', 'action': 'openDecision'});
      await request(bridge, {
        'token': 'test-token',
        'action': 'setDecision',
        'decisionId': 'decision-1',
        'optionId': 'option-a',
        'author': 'Ada',
        'rationale': 'Keep the durable option.',
      });
      await request(bridge, {
        'token': 'test-token',
        'action': 'publishDecision',
      });

      expect(selected, 'implementation');
      expect(commentsOpened, isTrue);
      expect(author, 'Ada');
      expect(body, 'Line one\nLine two');
      expect(published, 1);
      expect(replyThread, 'thread-1');
      expect(replyBody, 'Confirmed');
      expect(replyPublished, 1);
      expect(retried, 1);
      expect(decisionOpened, isTrue);
      expect(decisionId, 'decision-1');
      expect(optionId, 'option-a');
      expect(rationale, 'Keep the durable option.');
      expect(decisionPublished, 1);

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
