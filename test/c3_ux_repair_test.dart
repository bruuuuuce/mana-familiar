import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/mana_inspect.dart';
import 'package:mana_familiar/presentation/artifact_detail_view.dart';

void main() {
  testWidgets('dossier document mode de-emphasizes artifact plumbing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArtifactDetailView(
          documentPresentation: true,
          contextualTitle: 'Overview document',
          artifact: ManaInspectArtifactSummary.fromJson({
            'artifact_id': 'file:.mana/features/PROJ-1/index.md',
            'path': '.mana/features/PROJ-1/index.md',
            'family': 'semantic',
            'kind': 'markdown',
            'status': 'available',
          }),
          detail: ManaInspectArtifactDetail.fromJson({
            'schema': inspectArtifactSchema,
            'artifact': {
              'artifact_id': 'file:.mana/features/PROJ-1/index.md',
              'path': '.mana/features/PROJ-1/index.md',
              'family': 'semantic',
              'kind': 'markdown',
              'status': 'available',
            },
            'payload': {
              'content_type': 'text/markdown',
              'content': '# Project context\n\nReadable document content.',
            },
            'relations': [],
          }),
        ),
      ),
    );

    expect(find.text('Overview document'), findsOneWidget);
    expect(find.text('Project context'), findsAtLeastNWidgets(1));
    expect(find.text('Artifact detail'), findsNothing);
    expect(find.text('Payload'), findsNothing);
    expect(find.text('Reader'), findsOneWidget);
    expect(find.text('Metadata'), findsOneWidget);
  });
}
