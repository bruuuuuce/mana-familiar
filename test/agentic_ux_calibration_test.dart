import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Deliberate test-only controls. They do not mount production UI and each pair
// changes only the named communication property.
const _controls = [
  (
    'control-01',
    'Quale conclusione sul progetto è supportata?',
    false,
    'coverage',
  ),
  (
    'control-02',
    'Quale conclusione sul progetto è supportata?',
    true,
    'coverage',
  ),
  ('control-03', 'Quale stato di review è comunicato?', false, 'review'),
  ('control-04', 'Quale stato di review è comunicato?', true, 'review'),
  ('control-05', 'A quale lavoro appartiene il problema?', false, 'identity'),
  ('control-06', 'A quale lavoro appartiene il problema?', true, 'identity'),
  ('control-07', 'Quale azione è indicata?', false, 'readability'),
  ('control-08', 'Quale azione è indicata?', true, 'readability'),
];

Widget _card(String title, String body) => Card(
  child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(body, style: const TextStyle(fontSize: 18)),
      ],
    ),
  ),
);

Widget _fixture(String kind, bool defective) {
  switch (kind) {
    case 'coverage':
      return _card(
        'Project status',
        defective
            ? 'Data coverage: unavailable\nNothing needs attention.'
            : 'Data coverage: unavailable\nProject health cannot be determined. Refresh data.',
      );
    case 'review':
      return _card(
        'PAY-42 review',
        defective ? 'Review status: approved' : 'Review status: unknown',
      );
    case 'identity':
      return defective
          ? Column(
              children: [
                _card('PAY-42', 'No current issue.'),
                _card('PAY-43', 'No current issue.'),
                _card(
                  'Attention',
                  'Duplicate charge detected. Inspect retry evidence.',
                ),
              ],
            )
          : _card(
              'PAY-42 — Prevent duplicate payments',
              'Duplicate charge detected. Inspect retry evidence.',
            );
    default:
      return defective
          ? Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PAY-42',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 14,
                      child: ClipRect(
                        child: Text(
                          'Next action: Inspect retry evidence before another review.',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _card(
              'PAY-42',
              'Next action: Inspect retry evidence before another review.',
            );
  }
}

void main() {
  final output = Platform.environment['UX_EVIDENCE_DIR'];
  setUpAll(() async {
    final configFile = File('.dart_tool/package_config.json').absolute;
    final packages = jsonDecode(await configFile.readAsString()) as Map;
    final flutter = (packages['packages'] as List).cast<Map>().singleWhere(
      (package) => package['name'] == 'flutter',
    );
    final flutterPackage = configFile.uri.resolve(
      (flutter['rootUri'] as String).endsWith('/')
          ? flutter['rootUri'] as String
          : '${flutter['rootUri']}/',
    );
    final fonts =
        Platform.environment['UX_FONT_DIR'] ??
        flutterPackage
            .resolve('../../bin/cache/artifacts/material_fonts/')
            .toFilePath();
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        File(
          '$fonts/Roboto-$weight.ttf',
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
    }
    await loader.load();
  });
  testWidgets('renders documented calibration controls', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    for (final item in _controls) {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto'),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              appBar: AppBar(title: const Text('Calibration fixture')),
              body: Padding(
                padding: const EdgeInsets.all(32),
                child: ClipRect(child: _fixture(item.$4, item.$3)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (output != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$output/${item.$1}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
          await File('$output/${item.$1}.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'frames': [
                {'image': '${item.$1}.png', 'question': item.$2},
              ],
            }),
          );
        });
      }
    }
    if (output != null) {
      await tester.runAsync(
        () => File('$output/calibration.oracle.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'contract_version': '2.0',
            'control-01': {
              'checkpoints': [
                {
                  'checkpoint': 'c01',
                  'expected': 'Health is not determinable.',
                  'canonical': {'status': 'not_determinable'},
                  'producer': {'status': 'not_determinable'},
                  'text_aliases': ['cannot', 'determin', 'impossibile'],
                  'readability': 'fully_visible',
                  'answerability': 'answered',
                  'actionability': 'actionable',
                },
              ],
            },
            'control-02': {
              'checkpoints': [
                {
                  'checkpoint': 'c01',
                  'expected': 'Misleading success must be flagged.',
                  'canonical': {'status': 'healthy'},
                  'producer': {'status': 'not_determinable'},
                  'producer_fidelity': 'contradictory',
                  'text_aliases': [
                    'nothing needs attention',
                    'nessuna attenzione',
                  ],
                  'readability': 'fully_visible',
                  'answerability': 'answered',
                  'actionability': 'not_actionable',
                  'must_raise_finding': true,
                },
              ],
            },
            'control-03': {
              'checkpoints': [
                {
                  'checkpoint': 'c01',
                  'expected': 'Review unknown.',
                  'canonical': {'identity': 'PAY-42', 'status': 'unknown'},
                  'producer': {'status': 'unknown'},
                  'text_aliases': ['unknown', 'sconosciut'],
                  'readability': 'fully_visible',
                  'answerability': 'answered',
                  'actionability': 'not_applicable',
                },
              ],
            },
            'control-04': {
              'checkpoints': [
                {
                  'checkpoint': 'c01',
                  'expected': 'Incorrect approval must be flagged.',
                  'canonical': {'identity': 'PAY-42', 'status': 'approved'},
                  'producer': {'status': 'unknown'},
                  'producer_fidelity': 'contradictory',
                  'text_aliases': ['approved', 'approvat'],
                  'readability': 'fully_visible',
                  'answerability': 'answered',
                  'actionability': 'not_actionable',
                  'must_raise_finding': true,
                },
              ],
            },
            'control-05': {
              'checkpoints': [
                {
                  'checkpoint': 'c01',
                  'expected': 'PAY-42 is associated.',
                  'canonical': {
                    'identity': 'PAY-42',
                    'cause': 'duplicate_charge',
                  },
                  'producer': {
                    'identity': 'PAY-42',
                    'cause': 'duplicate_charge',
                  },
                  'text_aliases': ['PAY-42', 'duplicate'],
                  'readability': 'fully_visible',
                  'answerability': 'answered',
                  'actionability': 'actionable',
                },
              ],
            },
            'control-06': {
              'checkpoints': [
                {
                  'checkpoint': 'c01',
                  'expected': 'Association is not determinable.',
                  'canonical': {'identity': null, 'cause': 'duplicate_charge'},
                  'producer': {
                    'identity': 'PAY-42',
                    'cause': 'duplicate_charge',
                  },
                  'producer_fidelity': 'contradictory',
                  'text_aliases': ['cannot', 'non determinabile', 'uncertain'],
                  'readability': 'fully_visible',
                  'answerability': 'answered',
                  'actionability': 'not_actionable',
                  'must_raise_finding': true,
                },
              ],
            },
            'control-07': {
              'checkpoints': [
                {
                  'checkpoint': 'c01',
                  'expected': 'Inspect retry evidence.',
                  'canonical': {
                    'identity': 'PAY-42',
                    'action': 'inspect_retry_evidence',
                  },
                  'producer': {'action': 'inspect_retry_evidence'},
                  'text_aliases': ['inspect', 'ispezion'],
                  'readability': 'fully_visible',
                  'answerability': 'answered',
                  'actionability': 'actionable',
                },
              ],
            },
            'control-08': {
              'checkpoints': [
                {
                  'checkpoint': 'c01',
                  'expected':
                      'Essential action is clipped and must be flagged.',
                  'canonical': {
                    'identity': 'PAY-42',
                    'action': 'inspect_retry_evidence',
                  },
                  'producer': {'action': 'inspect_retry_evidence'},
                  'text_aliases': ['inspect', 'ispezion'],
                  'readability': 'partially_visible',
                  'answerability': 'answered',
                  'actionability': 'not_actionable',
                  'must_raise_finding': true,
                },
              ],
            },
          }),
        ),
      );
    }
  });
}
