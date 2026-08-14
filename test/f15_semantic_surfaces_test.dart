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
  }) => MaterialApp(
    home: ProjectObservatoryPage(
      key: ValueKey('${model.mode}-${route?.destination}'),
      client: ManaInspectClient(projectRoot: '/project'),
      knowledge: const SizedBox(),
      initialReadModel: model,
      initialRoute: route,
      artifactDetailLoader: detailLoader,
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
    expect(find.text('Project > Work > IG-100 > Review'), findsOneWidget);
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

  testWidgets('Knowledge makes populated and empty categories distinct', (
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
    expect(find.text('Open document'), findsOneWidget);
    await tester.tap(find.text('Open document'));
    await tester.pump();
    expect(
      find.text('Project > Knowledge > architecture > Architecture'),
      findsOneWidget,
    );
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
      expect(find.text('filesystem time'), findsOneWidget);
      expect(find.text('30 May 2024'), findsOneWidget);
      expect(
        find.text('artifact-update:file:.mana/features/IG-100/review.md'),
        findsNothing,
      );

      await tester.tap(find.text('Review recorded'));
      await tester.pump();
      expect(
        find.text('Project > Work > IG-100 > Review > Review notes'),
        findsOneWidget,
      );
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
  'artifacts': id == 'feature:IG-100' ? [_reviewReference] : const [],
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
  ],
  'guarantees': {},
  'diagnostics': [],
};
