import 'package:flutter_test/flutter_test.dart';
import 'package:mana_familiar/semantic_navigation.dart';
import 'package:mana_familiar/mana_inspect.dart';

void main() {
  test('semantic routes preserve work, section, and artifact context', () {
    final state = ObservatoryNavigationState();
    const detail = ObservatoryRoute(
      destination: ObservatoryDestination.work,
      workItemId: 'feature:NEXI-4217',
      section: ManaSectionId.decisions,
      artifactId: 'file:.mana/features/NEXI-4217/decisions/retry.md',
    );
    state.navigate(detail);
    expect(
      observatoryBreadcrumbs(detail, artifactLabel: 'Retry retention policy'),
      [
        'Project',
        'Work',
        'feature:NEXI-4217',
        'Decisions',
        'Retry retention policy',
      ],
    );
    expect(state.back()?.destination, ObservatoryDestination.overview);
    expect(state.forward(), detail);
  });

  test('artifact routes do not become Activity and restore exactly', () {
    final state = ObservatoryNavigationState(
      const ObservatoryRoute(destination: ObservatoryDestination.reviews),
    );
    const artifact = ObservatoryRoute(
      destination: ObservatoryDestination.reviews,
      workItemId: 'feature:one',
      artifactId: 'verification:one',
    );
    state.navigate(artifact);
    expect(state.current.destination, ObservatoryDestination.reviews);
    expect(state.back()?.destination, ObservatoryDestination.reviews);
    expect(state.forward(), artifact);
  });

  test('restore is a deep link state boundary', () {
    final state = ObservatoryNavigationState();
    const route = ObservatoryRoute(
      destination: ObservatoryDestination.knowledge,
      category: 'architecture',
    );
    state.restore(route);
    expect(state.current, route);
    expect(state.canGoBack, isFalse);
    expect(observatoryBreadcrumbs(route), [
      'Project',
      'Knowledge',
      'architecture',
    ]);
  });
}
