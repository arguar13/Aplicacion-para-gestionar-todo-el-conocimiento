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
          ShellBranch.timeline,
          ShellBranch.graph,
          ShellBranch.notebooks,
        ]),
        NavStep.ask: at([ShellBranch.chat]),
        NavStep.review: at([ShellBranch.review]),
        NavStep.settings: at([ShellBranch.settings]),
      },
    );
    expect(
      [for (final g in result) g.hasList],
      [false, true, false, false, false],
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

  test('«Preguntar» es el chat solo: se ve como el chat y lo abre directo', () {
    final ask = groups()[2];
    final chat = ask.destinations.single;

    expect(ask.hasList, isFalse);
    expect(chat.branchIndex, ShellBranch.chat.index);
    expect(ask.label, es.navChat);
    expect(ask.icon, same(chat.icon));
    expect(ask.selectedIcon, same(chat.selectedIcon));
  });

  test('un paso con lista tiene su nombre y su ícono propios', () {
    final organize = groups()[1];

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
  });

  test('la línea de tiempo (F40) va en «Organizar», debajo del Atlas (pedido '
      'del dueño), con su nombre y su ícono', () {
    final organize = groups()[1];
    final labels = [for (final d in organize.destinations) d.label];
    final timeline = organize.destinations.singleWhere(
      (d) => d.branchIndex == ShellBranch.timeline.index,
    );

    expect(labels, [
      es.navInbox,
      es.navAtlas,
      es.navTimeline,
      es.navMap,
      es.navNotebooks,
    ]);
    expect(timeline.step, NavStep.organize);
    expect((timeline.icon as Icon).icon, Icons.timeline);
    expect(timeline.hint, es.navTimelineHint);
  });

  test('la rama de la línea de tiempo está al final: sumarla no corrió el '
      'índice de ninguna de las de antes', () {
    expect(ShellBranch.timeline.index, ShellBranch.values.length - 1);
    expect(ShellBranch.notebooks.index, ShellBranch.timeline.index - 1);
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

  test('los cuadernos van al final de «Organizar», debajo del Mapa', () {
    final notebooks = groups()[1].destinations.last;

    expect(notebooks.branchIndex, ShellBranch.notebooks.index);
    expect(notebooks.step, NavStep.organize);
    expect(notebooks.label, es.navNotebooks);
    expect(notebooks.hint, es.navNotebooksHint);
  });

  test('sin chat (la web) no hay «Preguntar», y los cuadernos siguen en '
      '«Organizar»', () {
    final result = groups(includeChat: false);

    expect(
      [for (final g in result) g.step],
      [NavStep.save, NavStep.organize, NavStep.review, NavStep.settings],
    );
    expect(
      result[1].destinations.last.branchIndex,
      ShellBranch.notebooks.index,
    );
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
        ShellBranch.timeline.index: es.navTimelineHint,
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
