import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/project_observatory_page.dart';
import 'package:mana_familiar/semantic_navigation.dart';

void main() {
  Widget page(
    ManaSemanticReadModel model, {
    ObservatoryRoute? route,
    Future<ManaInspectArtifactDetail> Function(String id)? detailLoader,
    Widget Function(String? journeyId)? knowledgeBuilder,
  }) => MaterialApp(
    home: ProjectObservatoryPage(
      key: ValueKey('${model.mode}-${route?.destination}'),
      client: ManaInspectClient(projectRoot: '/project'),
      knowledge: const SizedBox(),
      initialReadModel: model,
      initialRoute: route,
      artifactDetailLoader: detailLoader,
      knowledgeBuilder: knowledgeBuilder,
    ),
  );

  testWidgets('Reviews uses typed work review state and enters its dossier', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        _semanticModel(),
        route: const ObservatoryRoute(
          destination: ObservatoryDestination.reviews,
        ),
      ),
    );

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Review status'), findsOneWidget);
    expect(find.text('IG-100'), findsAtLeastNWidgets(1));
    expect(find.text('unknown'), findsNothing);
    expect(find.text('file:.mana/features/IG-100/review.md'), findsNothing);

    await tester.tap(find.text('IG-100'));
    await tester.pump();
    expect(find.text('Review'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey('breadcrumb-work-item')), findsOneWidget);
    expect(find.byKey(const ValueKey('breadcrumb-section')), findsOneWidget);
  });

  testWidgets('Reviews is calm when every review state is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        _unknownReviewsModel(),
        route: const ObservatoryRoute(
          destination: ObservatoryDestination.reviews,
        ),
      ),
    );

    expect(
      find.text('No structured review information reported'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('unknown'), findsNothing);
  });

  testWidgets('Knowledge opens a single-document category directly', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        _semanticModel(),
        route: const ObservatoryRoute(
          destination: ObservatoryDestination.knowledge,
        ),
        detailLoader: (_) async => ManaInspectArtifactDetail.fromJson({
          'schema': inspectArtifactSchema,
          'artifact': {
            'artifact_id': 'file:.mana/global/architecture.md',
            'path': '.mana/global/architecture.md',
            'family': 'global',
            'kind': 'markdown',
            'status': 'available',
          },
          'payload': {'markdown': '# Architecture'},
          'relations': [],
        }),
      ),
    );

    expect(find.text('Architecture'), findsOneWidget);
    expect(find.text('1 document'), findsOneWidget);
    expect(find.text('Project decisions'), findsOneWidget);
    expect(find.text('No material yet'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Architecture'));
    await tester.pump();
    expect(find.byKey(const ValueKey('breadcrumb-category')), findsOneWidget);
    expect(find.byKey(const ValueKey('breadcrumb-document')), findsOneWidget);
  });

  testWidgets(
    'Knowledge retains a focused file list for fake multi-document data',
    (tester) async {
      final originalCategories = (_context['categories'] as List)
          .cast<Map<String, dynamic>>();
      final fakeModel = _semanticModelWithContext({
        ..._context,
        'categories': [
          {
            'category': 'architecture',
            'coverage': 'known',
            'artifacts': [
              (originalCategories.first['artifacts'] as List).first,
              {
                'artifact_id': 'file:.mana/global/deployment.md',
                'path': '.mana/global/deployment.md',
                'kind': 'markdown',
                'status': 'available',
                'work_item_id': null,
                'section_id': null,
                'label': 'Deployment architecture',
              },
            ],
          },
          ...originalCategories.skip(1),
        ],
      });
      await tester.pumpWidget(
        page(
          fakeModel,
          route: const ObservatoryRoute(
            destination: ObservatoryDestination.knowledge,
          ),
        ),
      );

      await tester.tap(find.text('Architecture'));
      await tester.pump();

      expect(find.text('Open document'), findsNWidgets(2));
      expect(find.text('Deployment architecture'), findsOneWidget);
      expect(find.text('Integrations'), findsNothing);
      expect(find.text('Other categories'), findsNothing);
    },
  );

  testWidgets('Knowledge opens Learning journeys in the Journey explorer', (
    tester,
  ) async {
    final model = _semanticModelWithContext({
      ..._context,
      'categories': [
        ...(_context['categories'] as List).where(
          (category) =>
              (category as Map<String, dynamic>)['category'] !=
              'learning_journeys',
        ),
        {
          'category': 'learning_journeys',
          'coverage': 'known',
          'artifacts': [
            _journeyArtifact('journey:jrn_first', 'journey'),
            _journeyArtifact('journey-record:node', 'journey_record'),
            _journeyArtifact('journey:jrn_second', 'journey'),
          ],
        },
      ],
    });
    String? requestedJourney;
    await tester.pumpWidget(
      page(
        model,
        route: const ObservatoryRoute(
          destination: ObservatoryDestination.knowledge,
        ),
        knowledgeBuilder: (journeyId) {
          requestedJourney = journeyId;
          return const Text('Existing Journey Explorer');
        },
      ),
    );

    expect(find.text('2 journeys'), findsOneWidget);
    await tester.tap(find.text('Learning journeys'));
    await tester.pump();

    expect(requestedJourney, isNull);
    expect(find.text('Existing Journey Explorer'), findsOneWidget);
    expect(find.text('Untitled document'), findsNothing);
  });

  testWidgets(
    'Activity is readable, retains filesystem provenance, and enters typed context',
    (tester) async {
      await tester.pumpWidget(
        page(
          _semanticModel(),
          route: const ObservatoryRoute(
            destination: ObservatoryDestination.activity,
          ),
        ),
      );

      expect(find.text('Review recorded'), findsOneWidget);
      expect(find.text('30 May 2024'), findsOneWidget);
      expect(
        find.text('artifact-update:file:.mana/features/IG-100/review.md'),
        findsNothing,
      );

      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('filesystem time'), findsAtLeastNWidgets(1));
      expect(find.text('Review notes updated'), findsOneWidget);

      await tester.tap(find.text('Review recorded'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('breadcrumb-work-item')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('breadcrumb-section')), findsOneWidget);
      expect(find.byKey(const ValueKey('breadcrumb-document')), findsOneWidget);
    },
  );

  testWidgets('dossier rows use typed labels and an honest untitled fallback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      page(
        _semanticModel(),
        route: const ObservatoryRoute(
          destination: ObservatoryDestination.work,
          workItemId: 'feature:IG-100',
          section: ManaSectionId.plan,
        ),
      ),
    );

    expect(find.text('Technical Task Breakdown'), findsOneWidget);
    expect(find.text('Untitled document'), findsOneWidget);
    expect(find.text('.mana/features/IG-100/task-breakdown.md'), findsNothing);
    expect(find.text('Document'), findsNothing);
  });

  testWidgets(
    'Activity resolves project-global targets and leaves stale targets inert',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        page(
          _semanticModel(),
          route: const ObservatoryRoute(
            destination: ObservatoryDestination.activity,
          ),
        ),
      );

      expect(find.text('Architecture updated'), findsOneWidget);
      expect(find.text('Unavailable document updated'), findsOneWidget);
      expect(find.textContaining('changed'), findsNothing);

      final unresolvedRow = find.ancestor(
        of: find.text('Unavailable document updated'),
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(unresolvedRow.first).onTap, isNull);

      await tester.tap(find.text('Architecture updated'));
      await tester.pump();
      expect(find.byKey(const ValueKey('breadcrumb-category')), findsOneWidget);
      expect(find.byKey(const ValueKey('breadcrumb-document')), findsOneWidget);
    },
  );

  testWidgets(
    'semantic breadcrumbs navigate typed parents and keep leaf inert',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        page(
          _semanticModel(),
          route: const ObservatoryRoute(
            destination: ObservatoryDestination.work,
            workItemId: 'feature:IG-100',
            section: ManaSectionId.plan,
            artifactId: 'file:.mana/features/IG-100/task-breakdown.md',
          ),
          detailLoader: (_) async => ManaInspectArtifactDetail.fromJson({
            'schema': inspectArtifactSchema,
            'artifact': _planSummary,
            'payload': {'kind': 'text', 'value': '# Technical Task Breakdown'},
            'relations': const [],
          }),
        ),
      );
      await tester.pumpAndSettle();

      final leaf = find.byKey(const ValueKey('breadcrumb-document'));
      expect(leaf, findsOneWidget);
      expect(
        find.ancestor(of: leaf, matching: find.byType(TextButton)),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('breadcrumb-section')));
      await tester.pump();
      expect(find.byKey(const ValueKey('breadcrumb-document')), findsNothing);
      expect(find.text('Technical Task Breakdown'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('breadcrumb-work-item')));
      await tester.pump();
      expect(find.text('Overview'), findsAtLeastNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('breadcrumb-destination')));
      await tester.pump();
      expect(find.text('Work'), findsAtLeastNWidgets(1));

      await tester.tap(find.byKey(const ValueKey('breadcrumb-project')));
      await tester.pump();
      expect(find.text('Project observatory'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      expect(find.text('Work'), findsAtLeastNWidgets(1));
      await tester.tap(find.byTooltip('Forward'));
      await tester.pump();
      expect(find.text('Project observatory'), findsOneWidget);
    },
  );

  testWidgets('Advanced exposes raw catalog and producer diagnostics', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        _semanticModel(),
        route: const ObservatoryRoute(
          destination: ObservatoryDestination.advanced,
        ),
      ),
    );

    expect(find.text('Artifact catalog'), findsAtLeastNWidgets(1));
    expect(find.text('file:.mana/features/IG-100/review.md'), findsOneWidget);
    expect(
      find.textContaining('.mana/features/IG-100/review.md'),
      findsAtLeastNWidgets(1),
    );

    await tester.tap(find.text('Inspect diagnostics'));
    await tester.pump();
    expect(find.text('Inspect diagnostics'), findsAtLeastNWidgets(1));
    expect(find.text('Incomplete coverage'), findsOneWidget);
  });

  testWidgets(
    'capability modes keep semantic and legacy experiences isolated',
    (tester) async {
      await tester.pumpWidget(
        page(
          _semanticModel(mode: ManaSemanticMode.workSemantic),
          route: const ObservatoryRoute(
            destination: ObservatoryDestination.knowledge,
          ),
        ),
      );
      expect(
        find.text('Project context is unavailable for this capability mode.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Activity'));
      await tester.pump();
      expect(
        find.text('Semantic activity is unavailable for this capability mode.'),
        findsOneWidget,
      );

      await tester.pumpWidget(
        page(
          _legacyModel(),
          route: const ObservatoryRoute(
            destination: ObservatoryDestination.reviews,
          ),
        ),
      );
      expect(find.text('Limited catalog mode'), findsOneWidget);
      await tester.tap(find.text('Activity'));
      await tester.pump();
      expect(find.text('Semantic activity is unavailable'), findsOneWidget);
      await tester.tap(find.text('Advanced'));
      await tester.pump();
      expect(find.text('file:.mana/features/IG-100/review.md'), findsOneWidget);
    },
  );
}

ManaSemanticReadModel _semanticModel({
  ManaSemanticMode mode = ManaSemanticMode.fullSemantic,
}) => ManaSemanticReadModel(
  project: _project(),
  mode: mode,
  catalog: ManaInspectCatalog.fromJson(_catalog),
  workItems: ManaWorkItemsResponse.fromJson(_workItems),
  projectContext: mode == ManaSemanticMode.fullSemantic
      ? ManaProjectContextResponse.fromJson(_context)
      : null,
  activity: mode == ManaSemanticMode.fullSemantic
      ? ManaActivityResponse.fromJson(_activity)
      : null,
);

ManaSemanticReadModel _semanticModelWithContext(Map<String, dynamic> context) =>
    ManaSemanticReadModel(
      project: _project(),
      mode: ManaSemanticMode.fullSemantic,
      catalog: ManaInspectCatalog.fromJson(_catalog),
      workItems: ManaWorkItemsResponse.fromJson(_workItems),
      projectContext: ManaProjectContextResponse.fromJson(context),
      activity: ManaActivityResponse.fromJson(_activity),
    );

ManaSemanticReadModel _unknownReviewsModel() => ManaSemanticReadModel(
  project: _project(),
  mode: ManaSemanticMode.fullSemantic,
  workItems: ManaWorkItemsResponse.fromJson({
    'schema': inspectWorkItemsSchema,
    'work_items': [_workItem('feature:IG-200', review: 'unknown')],
    'coverage': 'complete',
    'diagnostics': const [],
  }),
);

ManaSemanticReadModel _legacyModel() => ManaSemanticReadModel(
  project: _project(),
  mode: ManaSemanticMode.legacyCatalog,
  catalog: ManaInspectCatalog.fromJson(_catalog),
);

ManaInspectProject _project() => ManaInspectProject.fromJson({
  'schema': inspectProjectSchema,
  'project_id': 'project:semantic-surface-test',
  'framework': const {},
  'mana': const {'present': true},
  'operations': const [],
});

Map<String, dynamic> _workItem(String id, {required String review}) => {
  'work_item_id': id,
  'work_item_type': 'feature',
  'external_ticket_id': {
    'value': id.split(':').last,
    'provenance': 'explicit_workspace_manifest',
  },
  'title': const {
    'value': 'Improve review navigation',
    'provenance': 'explicit_workspace_manifest',
  },
  'purpose': const {'value': null, 'provenance': 'unavailable'},
  'branch': const {'value': null, 'provenance': 'unavailable'},
  'canonical_branch': null,
  'lifecycle': const {
    'state': 'in_progress',
    'provenance': 'explicit_workspace_manifest',
    'coverage': 'known',
  },
  'review': {
    'state': review,
    'provenance': review == 'unknown'
        ? 'unavailable'
        : 'explicit_workspace_manifest',
    'coverage': review == 'unknown' ? 'unknown' : 'known',
  },
  'attention_items': id == 'feature:IG-100'
      ? const [
          {
            'id': 'review-needed',
            'category': 'review_required',
            'severity': 'warning',
            'work_item_id': 'feature:IG-100',
            'related_artifact_ids': ['file:.mana/features/IG-100/review.md'],
            'provenance': 'explicit_workspace_manifest',
            'label': 'Review notes need attention',
          },
        ]
      : const [],
  'artifacts': id == 'feature:IG-100'
      ? [_reviewReference, _planReference, _untitledPlanReference]
      : const [],
};

const _reviewReference = {
  'artifact_id': 'file:.mana/features/IG-100/review.md',
  'path': '.mana/features/IG-100/review.md',
  'kind': 'markdown',
  'status': 'available',
  'work_item_id': 'feature:IG-100',
  'section_id': 'review',
  'label': 'Review notes',
};

const _planReference = {
  'artifact_id': 'file:.mana/features/IG-100/task-breakdown.md',
  'path': '.mana/features/IG-100/task-breakdown.md',
  'kind': 'markdown',
  'status': 'available',
  'work_item_id': 'feature:IG-100',
  'section_id': 'plan',
  'label': 'Technical Task Breakdown',
};

const _untitledPlanReference = {
  'artifact_id': 'file:.mana/features/IG-100/untitled.md',
  'path': '.mana/features/IG-100/untitled.md',
  'kind': 'markdown',
  'status': 'available',
  'work_item_id': 'feature:IG-100',
  'section_id': 'plan',
  'label': null,
};

const _planSummary = {
  'artifact_id': 'file:.mana/features/IG-100/task-breakdown.md',
  'path': '.mana/features/IG-100/task-breakdown.md',
  'family': 'workspace',
  'kind': 'markdown',
  'status': 'available',
};

final _workItems = {
  'schema': inspectWorkItemsSchema,
  'work_items': [
    _workItem('feature:IG-100', review: 'pending'),
    _workItem('feature:IG-101', review: 'approved'),
  ],
  'coverage': 'complete',
  'diagnostics': const [
    {
      'id': 'catalog-coverage',
      'kind': 'incomplete_coverage',
      'severity': 'warning',
      'provenance': 'conservative_fallback',
      'related_artifact_ids': [],
    },
  ],
};

const _context = {
  'schema': inspectProjectContextSchema,
  'categories': [
    {
      'category': 'architecture',
      'coverage': 'known',
      'artifacts': [
        {
          'artifact_id': 'file:.mana/global/architecture.md',
          'path': '.mana/global/architecture.md',
          'kind': 'markdown',
          'status': 'available',
          'work_item_id': null,
          'section_id': null,
          'label': 'Architecture',
        },
      ],
    },
    {'category': 'project_decisions', 'coverage': 'missing', 'artifacts': []},
    {'category': 'integrations', 'coverage': 'missing', 'artifacts': []},
    {'category': 'engineering_guards', 'coverage': 'missing', 'artifacts': []},
    {'category': 'glossary', 'coverage': 'missing', 'artifacts': []},
    {'category': 'learning_journeys', 'coverage': 'missing', 'artifacts': []},
    {'category': 'testing_policy', 'coverage': 'missing', 'artifacts': []},
    {'category': 'database_policy', 'coverage': 'missing', 'artifacts': []},
  ],
  'coverage': 'complete',
  'diagnostics': [],
};

Map<String, dynamic> _journeyArtifact(String id, String kind) => {
  'artifact_id': id,
  'path': '.mana/learning/journeys/${id.split(':').last}/journey.yaml',
  'kind': kind,
  'status': 'available',
  'work_item_id': null,
  'section_id': null,
  'label': null,
};

const _activity = {
  'schema': inspectActivitySchema,
  'events': [
    {
      'event_id': 'review:IG-100',
      'timestamp': {
        'value': '2026-05-30T10:15:00Z',
        'provenance': 'explicit_domain_timestamp',
      },
      'event_kind': 'review_recorded',
      'work_item_id': 'feature:IG-100',
      'related_artifact_ids': ['file:.mana/features/IG-100/review.md'],
      'target': {
        'artifact_id': 'file:.mana/features/IG-100/review.md',
        'work_item_id': 'feature:IG-100',
        'section_id': 'review',
        'project_context_category': null,
        'label': 'Review notes',
      },
      'summary': 'Review recorded',
      'provenance': 'explicit_workspace_manifest',
    },
    {
      'event_id': 'artifact-update:file:.mana/features/IG-100/review.md',
      'timestamp': {
        'value': '1717064100',
        'provenance': 'filesystem_mtime_epoch',
      },
      'event_kind': 'artifact_updated',
      'work_item_id': 'feature:IG-100',
      'related_artifact_ids': [],
      'target': {
        'artifact_id': 'file:.mana/features/IG-100/review.md',
        'work_item_id': 'feature:IG-100',
        'section_id': 'review',
        'project_context_category': null,
        'label': 'Review notes',
      },
      'summary': null,
      'provenance': 'conservative_fallback',
    },
    {
      'event_id': 'artifact-update:file:.mana/global/architecture.md',
      'timestamp': {
        'value': '1717064000',
        'provenance': 'filesystem_mtime_epoch',
      },
      'event_kind': 'artifact_updated',
      'work_item_id': null,
      'related_artifact_ids': ['file:.mana/global/architecture.md'],
      'target': {
        'artifact_id': 'file:.mana/global/architecture.md',
        'work_item_id': null,
        'section_id': null,
        'project_context_category': 'architecture',
        'label': 'Architecture',
      },
      'summary': null,
      'provenance': 'conservative_fallback',
    },
    {
      'event_id': 'artifact-update:file:.mana/global/removed.md',
      'timestamp': {
        'value': '1717063900',
        'provenance': 'filesystem_mtime_epoch',
      },
      'event_kind': 'artifact_updated',
      'work_item_id': null,
      'related_artifact_ids': ['file:.mana/global/removed.md'],
      'target': {
        'artifact_id': 'file:.mana/global/removed.md',
        'work_item_id': null,
        'section_id': null,
        'project_context_category': 'architecture',
        'label': 'Unavailable document',
      },
      'summary': null,
      'provenance': 'conservative_fallback',
    },
  ],
  'coverage': 'complete',
  'diagnostics': [],
};

const _catalog = {
  'schema': inspectArtifactsSchema,
  'artifacts': [
    {
      'artifact_id': 'file:.mana/features/IG-100/review.md',
      'path': '.mana/features/IG-100/review.md',
      'family': 'workspace',
      'kind': 'markdown',
      'status': 'available',
    },
    _planSummary,
    {
      'artifact_id': 'file:.mana/features/IG-100/untitled.md',
      'path': '.mana/features/IG-100/untitled.md',
      'family': 'workspace',
      'kind': 'markdown',
      'status': 'available',
    },
  ],
  'guarantees': {},
  'diagnostics': [],
};
