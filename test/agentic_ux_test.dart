import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/application/mana_workspace_watcher.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/project_observatory_page.dart';

// Deliberately independent of the adjacent Mana checkout and real user data.
const _title = 'Prevent duplicate invoice payments during provider retries';
const _attention = 'Payment verification failed: duplicate charge detected';
const _field = ManaProvenance.explicitWorkspaceManifest;
const _work = ManaWorkItemSummary(
  id: 'feature:PAY-42',
  type: ManaWorkItemType.feature,
  externalTicketId: ManaSemanticField(value: 'PAY-42', provenance: _field),
  title: ManaSemanticField(value: _title, provenance: _field),
  purpose: ManaSemanticField(
    value: 'A retry must never charge the customer twice.',
    provenance: _field,
  ),
  branch: ManaSemanticField(value: 'feature/PAY-42', provenance: _field),
  canonicalBranch: true,
  lifecycle: ManaLifecycle(ManaLifecycleState.blocked, _field, 'complete'),
  review: ManaReview(
    ManaReviewState.unknown,
    ManaProvenance.unavailable,
    'none',
  ),
  attentionItems: [
    ManaAttentionItem(
      id: 'duplicate-charge',
      category: 'verification',
      severity: 'error',
      workItemId: 'feature:PAY-42',
      relatedArtifactIds: [],
      provenance: _field,
      label: _attention,
      nextAction: 'Inspect retry evidence before requesting another review.',
    ),
  ],
  artifacts: [],
);

class _QuietWatcher implements ManaWorkspaceWatcher {
  @override
  Stream<ManaWorkspaceWatchEvent> get events => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> dispose() async {}
}

class _Client extends ManaInspectClient {
  _Client() : super(projectRoot: '/synthetic/invoice-demo');
  @override
  Future<ManaWorkItemResponse> workItem(
    String id, {
    ManaInspectProject? capabilities,
  }) async {
    if (id != _work.id) throw StateError('Unexpected work item: $id');
    return ManaWorkItemResponse(
      workItem: _work,
      sections: [],
      attentionItems: _work.attentionItems,
      coverage: 'partial',
      diagnostics: [],
    );
  }
}

void main() {
  final output = Platform.environment['UX_EVIDENCE_DIR'];
  setUpAll(() async {
    // Use real fonts in ordinary flutter test too, so hit testing and layout
    // match the capture run rather than the very different Ahem metrics.
    final configFile = File('.dart_tool/package_config.json').absolute;
    final packages = jsonDecode(await configFile.readAsString()) as Map;
    final flutter = (packages['packages'] as List).cast<Map>().singleWhere(
      (package) => package['name'] == 'flutter',
    );
    final flutterRoot = flutter['rootUri'] as String;
    final flutterPackage = configFile.uri.resolve(
      flutterRoot.endsWith('/') ? flutterRoot : '$flutterRoot/',
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
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '$fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
    await icons.load();
  });

  for (final variant in [
    (id: 'desktop-light', size: const Size(1440, 900), scale: 1.0, dark: false),
    (id: 'compact-dark', size: const Size(1024, 768), scale: 1.3, dark: true),
  ]) {
    testWidgets('UX task and evidence: ${variant.id}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = variant.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final boundary = GlobalKey();
      final frames = <Map<String, Object>>[];
      var clickCount = 0;

      Future<void> capture(String name, String question) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Layout at $name');
        if (output == null) return;
        final fileName = '${variant.id}-$name.png';
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$output/$fileName',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        frames.add({
          'image': fileName,
          'question': question,
          'clicks': clickCount,
        });
      }

      Future<void> tap(Finder target) async {
        expect(target.hitTestable(), findsOneWidget);
        await tester.tap(target);
        clickCount++;
        await tester.pumpAndSettle();
      }

      Future<void> mount({bool sparse = false}) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'Roboto',
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff4f46e5),
                  brightness: variant.dark ? Brightness.dark : Brightness.light,
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(variant.scale)),
                child: child!,
              ),
              home: ProjectObservatoryPage(
                key: ValueKey(sparse),
                client: _Client(),
                watcher: _QuietWatcher(),
                knowledge: const SizedBox(),
                initialReadModel: ManaSemanticReadModel(
                  project: ManaInspectProject.fromJson({
                    'schema': inspectProjectSchema,
                    'project_id': 'Invoice demo',
                    'framework': <String, dynamic>{},
                    'mana': {'present': true},
                    'operations': <Object>[],
                  }),
                  mode: ManaSemanticMode.fullSemantic,
                  workItems: ManaWorkItemsResponse(
                    workItems: sparse ? [] : [_work],
                    coverage: sparse ? 'none' : 'partial',
                    diagnostics: const [],
                  ),
                  refreshError: sparse
                      ? const ManaInspectException(
                          ManaInspectFailure.transport,
                          'Synthetic producer unavailable',
                        )
                      : null,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      expect(find.text(_attention).hitTestable(), findsOneWidget);
      await capture(
        'overview',
        'Quale attenzione richiede questa schermata? Il lavoro interessato è identificabile?',
      );
      await tap(find.text(_attention));
      expect(find.text('PAY-42'), findsAtLeastNWidgets(1));
      expect(find.text(_title), findsAtLeastNWidgets(1));
      await capture(
        'work',
        'Qual è l’obiettivo del lavoro e qual è il suo stato?',
      );
      await tap(find.text('Review').last);
      expect(
        find.text(
          'Mana could not provide review information for this work item.',
        ),
        findsOneWidget,
      );
      await capture('review', 'Quale stato di review è comunicato?');
      await tap(find.byTooltip('Back'));
      expect(find.text(_title), findsAtLeastNWidgets(1));
      expect(clickCount, 3, reason: 'Attention → work → review → back');
      await mount(sparse: true);
      expect(
        find.text('Refresh incomplete. Showing the last successful data.'),
        findsOneWidget,
      );
      await capture(
        'unavailable',
        'Quale conclusione sullo stato del progetto è supportata dalla schermata?',
      );
      if (output != null) {
        await tester.runAsync(
          () => File('$output/${variant.id}.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'variant': variant.id,
              'viewport': [variant.size.width, variant.size.height],
              'textScale': variant.scale,
              'frames': frames,
            }),
          ),
        );
        // Kept outside observer-input by the runner. These facts never enter the
        // first model prompt and are compared only after its immutable output.
        await tester.runAsync(
          () => File('$output/${variant.id}.oracle.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'contract_version': '2.0',
              'checkpoints': [
                {
                  'checkpoint': 'c01',
                  'expected': 'PAY-42 needs attention for failed verification.',
                  'canonical': {
                    'identity': 'PAY-42',
                    'status': 'blocked',
                    'cause': 'duplicate_charge',
                  },
                  'producer': {
                    'identity': 'PAY-42',
                    'status': 'blocked',
                    'cause': 'duplicate_charge',
                  },
                  'text_aliases': ['PAY-42', 'duplicate', 'duplicato'],
                  'readability': 'fully_visible',
                  'answerability': 'answered',
                  'actionability': 'not_applicable',
                },
                {
                  'checkpoint': 'c02',
                  'expected': 'The work is blocked.',
                  'canonical': {'identity': 'PAY-42', 'status': 'blocked'},
                  'producer': {'identity': 'PAY-42', 'status': 'blocked'},
                  'text_aliases': ['blocked', 'bloccato'],
                  'readability': 'fully_visible',
                  'answerability': 'answered',
                  'actionability': 'not_applicable',
                },
                {
                  'checkpoint': 'c03',
                  'expected': 'Review status is unknown.',
                  'canonical': {'identity': 'PAY-42', 'status': 'unknown'},
                  'producer': {'identity': 'PAY-42', 'status': 'unknown'},
                  'text_aliases': ['unknown', 'sconosciut'],
                  'readability': 'fully_visible',
                  'answerability': 'answered',
                  'actionability': 'not_applicable',
                },
                {
                  'checkpoint': 'c04',
                  'expected': 'The project cannot be concluded healthy.',
                  'canonical': {'status': 'not_determinable'},
                  'producer': {'status': 'not_determinable'},
                  'text_aliases': ['cannot', 'determin', 'impossibile'],
                  'readability': 'fully_visible',
                  'answerability': 'answered',
                  'actionability': 'not_applicable',
                },
              ],
            }),
          ),
        );
      }
    });
  }
}
