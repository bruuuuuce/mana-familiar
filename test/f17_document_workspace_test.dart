import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/artifact_detail_view.dart';

void main() {
  testWidgets('document workspace uses the available wide viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_document(_layoutMarkdown));
    await tester.pump();

    expect(find.byKey(const Key('markdown-outline-sticky')), findsOneWidget);
    expect(find.byKey(const Key('markdown-outline-compact')), findsNothing);
    expect(find.byKey(const Key('markdown-table-scroll')), findsOneWidget);
    expect(find.byKey(const Key('markdown-code-block')), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('markdown-full-width-document')))
          .width,
      greaterThan(1000),
    );
  });

  testWidgets('narrow viewport preserves body width with a compact outline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_document(_layoutMarkdown));
    await tester.pump();

    expect(find.byKey(const Key('markdown-outline-sticky')), findsNothing);
    expect(find.byKey(const Key('markdown-outline-compact')), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('markdown-full-width-document')))
          .width,
      greaterThan(620),
    );
  });

  testWidgets('renders every unordered and ordered list item once', (
    tester,
  ) async {
    await tester.pumpWidget(
      _document('''
# Lists

- Alpha
- Beta
- Gamma

1. First
2. Second
3. Third
'''),
    );
    await tester.pump();

    for (final item in <String>[
      'Alpha',
      'Beta',
      'Gamma',
      'First',
      'Second',
      'Third',
    ]) {
      expect(find.text(item), findsOneWidget);
    }
  });

  testWidgets('outline clicks scroll to stable anchors and updates selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_document(_longMarkdown));
    await tester.pump();

    expect(_isSelected(tester, 'outline-introduction'), isTrue);
    final before = tester.getTopLeft(
      find.byKey(const Key('heading-third-section')),
    );
    await tester.tap(find.byKey(const Key('outline-third-section')));
    await tester.pumpAndSettle();

    expect(_isSelected(tester, 'outline-third-section'), isTrue);
    expect(
      tester.getTopLeft(find.byKey(const Key('heading-third-section'))).dy,
      lessThan(before.dy),
    );
    expect(find.byKey(const Key('markdown-outline-sticky')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('markdown-document-scroll')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(_isSelected(tester, 'outline-third-section'), isTrue);
  });

  testWidgets('renders supported Mermaid and PlantUML locally', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _document('''
# Diagrams

```mermaid
flowchart LR
  A[Start] --> B[Complete]
```

```plantuml
@startuml
participant Client
participant Producer
Client -> Producer: inspect
Producer --> Client: response
@enduml
```
'''),
    );
    await tester.pump();

    expect(find.byKey(const Key('markdown-diagram-mermaid')), findsOneWidget);
    expect(find.byKey(const Key('markdown-diagram-plantUml')), findsOneWidget);
    expect(find.text('Diagram could not be rendered'), findsNothing);
  });

  testWidgets('diagram attacks and malformed input fail inertly with source', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const attacks = <String>[
      'click A "javascript:alert(1)"',
      '!include https://example.invalid/remote.puml',
      '!include ../../secret.txt',
      '<script>alert(1)</script>',
    ];
    for (final attack in attacks) {
      await tester.pumpWidget(
        _document('''
# Unsafe

```mermaid
flowchart LR
A --> B
$attack
```
'''),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('diagram-error-mermaid')),
        findsOneWidget,
        reason: attack,
      );
    }

    await tester.pumpWidget(
      _document('''
# Malformed

```plantuml
@startuml
participant OnlyOne
@enduml
```
'''),
    );
    await tester.pump();
    expect(find.byKey(const Key('diagram-error-plantUml')), findsOneWidget);
    await tester.tap(find.byKey(const Key('diagram-show-source-plantUml')));
    await tester.pump();
    expect(find.textContaining('participant OnlyOne'), findsOneWidget);

    await tester.tap(find.text('Source'));
    await tester.pump();
    expect(find.textContaining('```plantuml'), findsOneWidget);
  });
}

bool _isSelected(WidgetTester tester, String key) {
  final semantics = tester.widget<Semantics>(
    find
        .ancestor(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Semantics),
        )
        .first,
  );
  return semantics.properties.selected ?? false;
}

Widget _document(String markdown) => MaterialApp(
  home: Scaffold(
    body: ArtifactDetailView(
      artifact: ManaInspectArtifactSummary.fromJson(_artifact),
      detail: ManaInspectArtifactDetail.fromJson({
        'schema': inspectArtifactSchema,
        'artifact': _artifact,
        'payload': {'kind': 'text', 'value': markdown},
        'relations': const [],
      }),
      documentPresentation: true,
      contextualTitle: 'Implementation Plan',
    ),
  ),
);

const _artifact = <String, dynamic>{
  'artifact_id': 'file:.mana/features/PROJ-24342/plan.md',
  'path': '.mana/features/PROJ-24342/plan.md',
  'family': 'workspace',
  'kind': 'markdown',
  'content_type': 'text/markdown',
  'status': 'available',
};

const _layoutMarkdown = '''
# Decision table

Natural paragraphs use all of the document workspace without an arbitrary publishing column.

| Decision | Owner | Consequence | Evidence |
|---|---|---|---|
| Preserve typed semantics | Mana | Familiar stays honest | Contract |

```dart
final safelyWideCodeBlock = List.generate(20, (index) => index).join(', ');
```

## Detail

More detail.
''';

final _longMarkdown =
    '''
# Introduction

${List.filled(18, 'A long introductory paragraph that creates enough vertical content to exercise document-local scrolling without adding more controllers.').join('\n\n')}

## Second section

${List.filled(18, 'The second section remains readable while the outline stays beside the scrolling document.').join('\n\n')}

## Third section

${List.filled(18, 'The third section is the explicit target selected from the persistent outline.').join('\n\n')}
''';
