import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/navigation/nav_destinations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Los pasos de la barra del celular (F34): qué destinos van en cada uno,
/// en qué orden, y cómo se ve un paso con lista.
void main() {
  final es = AppLocalizationsEs();

  List<NavStepGroup> groups({
    int pendingInboxCount = 0,
    int dueFlashcardCount = 0,
    bool includeChat = true,
  }) => buildNavStepGroups(
    l10n: es,
    destinations: buildNavDestinations(
      l10n: es,
      dueFlashcardCount: dueFlashcardCount,
      pendingInboxCount: pendingInboxCount,
      includeChat: includeChat,
    ),
  );

  Badge badgeOf(Widget icon) => icon as Badge;

  /// Las ramas de [branches], como índices.
  List<int> at(List<ShellBranch> branches) => [
    for (final b in branches) b.index,
  ];

  test('cinco pasos en orden de uso, cada destino en el suyo y en orden', () {
    final result = groups();

    expect([for (final g in result) g.step], NavStep.values);
    expect(
      {
        for (final g in result)
          g.step: [for (final d in g.destinations) d.branchIndex],
      },
      {
        NavStep.save: at([ShellBranch.library]),
        NavStep.organize: at([
          ShellBranch.inbox,
          ShellBranch.atlas,
          ShellBranch.graph,
        ]),
        NavStep.ask: at([ShellBranch.chat, ShellBranch.notebooks]),
        NavStep.review: at([ShellBranch.review]),
        NavStep.settings: at([ShellBranch.settings]),
      },
    );
    expect(
      [for (final g in result) g.hasList],
      [false, true, true, false, false],
    );
  });

  test('ninguna rama queda afuera ni en dos pasos', () {
    final branches = [
      for (final g in groups())
        for (final d in g.destinations) d.branchIndex,
    ];

    expect(branches.toSet(), at(ShellBranch.values).toSet());
    expect(branches, hasLength(ShellBranch.values.length));
  });

  test('un paso de un solo destino se ve como ese destino', () {
    final review = groups(dueFlashcardCount: 4)[3];
    final only = review.destinations.single;

    expect(review.label, es.navReview);
    expect(review.icon, same(only.icon));
    expect(review.selectedIcon, same(only.selectedIcon));
  });

  test('un paso con lista tiene su nombre y su ícono propios', () {
    final [_, organize, ask, _, _] = groups();

    expect(organize.label, es.navStepOrganize);
    expect(badgeOf(organize.icon).child, isA<Icon>());
    expect(
      (badgeOf(organize.icon).child! as Icon).icon,
      Icons.workspaces_outlined,
    );
    expect(
      (badgeOf(organize.selectedIcon).child! as Icon).icon,
      Icons.workspaces,
    );
    expect(ask.label, es.navStepAsk);
    expect(
      (badgeOf(ask.icon).child! as Icon).icon,
      Icons.question_answer_outlined,
    );
    expect(
      (badgeOf(ask.selectedIcon).child! as Icon).icon,
      Icons.question_answer,
    );
  });

  test('los pendientes de la Bandeja se ven en «Organizar»', () {
    final organize = groups(pendingInboxCount: 3)[1];

    for (final icon in [organize.icon, organize.selectedIcon]) {
      final badge = badgeOf(icon);
      expect(badge.isLabelVisible, isTrue);
      expect((badge.label! as Text).data, '3');
    }
  });

  test('sin pendientes, «Organizar» no muestra insignia', () {
    final organize = groups()[1];

    expect(badgeOf(organize.icon).isLabelVisible, isFalse);
    expect(badgeOf(organize.selectedIcon).isLabelVisible, isFalse);
  });

  test('las tarjetas para hoy no cuentan en «Organizar»', () {
    final organize = groups(dueFlashcardCount: 7)[1];

    expect(badgeOf(organize.icon).isLabelVisible, isFalse);
  });

  test('sin chat (la web), «Preguntar» es Cuadernos, directo', () {
    final result = groups(includeChat: false);
    final ask = result.firstWhere((g) => g.step == NavStep.ask);

    expect(result, hasLength(5));
    expect(ask.hasList, isFalse);
    expect(ask.label, es.navNotebooks);
    expect(ask.destinations.single.branchIndex, ShellBranch.notebooks.index);
  });

  test('cada destino dice para qué sirve', () {
    final destinations = buildNavDestinations(
      l10n: es,
      dueFlashcardCount: 0,
      pendingInboxCount: 0,
      includeChat: true,
    );

    expect(
      {for (final d in destinations) d.branchIndex: d.hint},
      {
        ShellBranch.library.index: es.navLibraryHint,
        ShellBranch.inbox.index: es.navInboxHint,
        ShellBranch.atlas.index: es.navAtlasHint,
        ShellBranch.graph.index: es.navMapHint,
        ShellBranch.chat.index: es.navChatHint,
        ShellBranch.notebooks.index: es.navNotebooksHint,
        ShellBranch.review.index: es.navReviewHint,
        ShellBranch.settings.index: es.navSettingsHint,
      },
    );
  });

  test('un segundo destino en un paso sin aspecto propio no pasa callado', () {
    const library = NavDestinationSpec(
      branchIndex: 0,
      step: NavStep.save,
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: 'Biblioteca',
      hint: '',
    );
    const other = NavDestinationSpec(
      branchIndex: 9,
      step: NavStep.save,
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: 'Otro',
      hint: '',
    );

    expect(
      () => buildNavStepGroups(l10n: es, destinations: [library, other]),
      throwsStateError,
    );
  });

  test('un paso sin destinos no tiene botón', () {
    const library = NavDestinationSpec(
      branchIndex: 0,
      step: NavStep.save,
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: 'Biblioteca',
      hint: '',
    );

    final result = buildNavStepGroups(l10n: es, destinations: [library]);

    expect([for (final g in result) g.step], [NavStep.save]);
  });
}
