import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/navigation/nav_destinations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Los pasos de la barra del celular (F34, F43): qué destinos van en cada
/// uno, en qué orden, y cómo se ve un paso con lista.
void main() {
  final es = AppLocalizationsEs();

  List<NavDestinationSpec> destinations({
    int pendingInboxCount = 0,
    int dueFlashcardCount = 0,
    bool includeChat = true,
  }) => buildNavDestinations(
    l10n: es,
    dueFlashcardCount: dueFlashcardCount,
    pendingInboxCount: pendingInboxCount,
    includeChat: includeChat,
  );

  List<NavStepGroup> groups({
    int pendingInboxCount = 0,
    int dueFlashcardCount = 0,
    bool includeChat = true,
  }) => buildNavStepGroups(
    l10n: es,
    destinations: destinations(
      dueFlashcardCount: dueFlashcardCount,
      pendingInboxCount: pendingInboxCount,
      includeChat: includeChat,
    ),
  );

  NavStepGroup stepOf(List<NavStepGroup> result, NavStep step) =>
      result.singleWhere((g) => g.step == step);

  Badge badgeOf(Widget icon) => icon as Badge;

  IconData? iconOf(Widget icon) =>
      icon is Icon ? icon.icon : ((icon as Badge).child! as Icon).icon;

  /// Las ramas de [branches], como índices.
  List<int> at(List<ShellBranch> branches) => [
    for (final b in branches) b.index,
  ];

  test('cinco pasos en orden de uso —Biblioteca, Organizar, Estudiar, Chat y '
      'Ajustes (F43)—, cada destino en el suyo y en orden', () {
    final result = groups();

    // Escrito a mano y no `NavStep.values`: el orden del enum ES el de la
    // barra, y compararlo consigo mismo no probaría nada.
    expect(
      [for (final g in result) g.step],
      [
        NavStep.save,
        NavStep.organize,
        NavStep.study,
        NavStep.ask,
        NavStep.settings,
      ],
    );
    expect(
      [
        for (final g in result) [for (final d in g.destinations) d.branchIndex],
      ],
      [
        at([ShellBranch.library]),
        at([ShellBranch.inbox, ShellBranch.atlas]),
        at([
          ShellBranch.processed,
          ShellBranch.notebooks,
          ShellBranch.timeline,
          ShellBranch.graph,
          ShellBranch.review,
        ]),
        at([ShellBranch.chat]),
        at([ShellBranch.settings]),
      ],
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

  test('el riel sigue el mismo orden que la barra: los destinos de cada paso, '
      'paso tras paso', () {
    expect(
      [for (final d in destinations()) d.label],
      [
        es.navLibrary,
        es.navInbox,
        es.navAtlas,
        es.navProcessed,
        es.navNotebooks,
        es.navTimeline,
        es.navMap,
        es.navReview,
        es.navChat,
        es.navSettings,
      ],
    );
    expect(
      [
        for (final g in groups())
          for (final d in g.destinations) d.branchIndex,
      ],
      [for (final d in destinations()) d.branchIndex],
    );
  });

  test('las ramas no se movieron: mudar destinos de paso (F43) no corre el '
      'índice de ninguna', () {
    expect(
      [for (final b in ShellBranch.values) b.name],
      [
        'library',
        'inbox',
        'graph',
        'chat',
        'review',
        'settings',
        'atlas',
        'notebooks',
        'timeline',
        'processed',
      ],
    );
  });

  test('un paso de un solo destino se ve como ese destino', () {
    final save = stepOf(groups(), NavStep.save);
    final only = save.destinations.single;

    expect(save.label, es.navLibrary);
    expect(save.icon, same(only.icon));
    expect(save.selectedIcon, same(only.selectedIcon));
  });

  test('«Preguntar» es el chat solo, a la derecha de «Estudiar»: se ve como el '
      'chat y lo abre directo', () {
    final result = groups();
    final ask = result[3];
    final chat = ask.destinations.single;

    expect(result[2].step, NavStep.study);
    expect(ask.step, NavStep.ask);
    expect(ask.hasList, isFalse);
    expect(chat.branchIndex, ShellBranch.chat.index);
    expect(ask.label, es.navChat);
    expect(ask.icon, same(chat.icon));
    expect(ask.selectedIcon, same(chat.selectedIcon));
  });

  test('«Organizar» tiene su nombre y su ícono propios', () {
    final organize = stepOf(groups(), NavStep.organize);

    expect(organize.label, es.navStepOrganize);
    expect(iconOf(organize.icon), Icons.workspaces_outlined);
    expect(iconOf(organize.selectedIcon), Icons.workspaces);
  });

  test('«Estudiar» (F43) tiene su nombre y un ícono propio, que no usa ningún '
      'destino ni el otro paso con lista', () {
    final result = groups();
    final study = stepOf(result, NavStep.study);

    expect(study.label, 'Estudiar');
    expect(study.label, es.f43NavStepStudy);
    expect(iconOf(study.icon), Icons.history_edu_outlined);
    expect(iconOf(study.selectedIcon), Icons.history_edu);

    final others = {
      for (final g in result)
        if (g.step != NavStep.study) ...[
          iconOf(g.icon),
          iconOf(g.selectedIcon),
        ],
      for (final d in destinations()) ...[
        iconOf(d.icon),
        iconOf(d.selectedIcon),
      ],
    };
    expect(others, isNot(contains(Icons.history_edu_outlined)));
    expect(others, isNot(contains(Icons.history_edu)));
  });

  test('«Organizar» se queda con lo que ordena: la Bandeja y el Atlas', () {
    final organize = stepOf(groups(), NavStep.organize);

    expect(
      [for (final d in organize.destinations) d.label],
      [es.navInbox, es.navAtlas],
    );
    expect(
      [for (final d in organize.destinations) d.hint],
      [es.navInboxHint, es.navAtlasHint],
    );
  });

  test('«Estudiar» abre Procesado, Cuadernos, Línea de tiempo, Mapa y '
      'Repasar, en ese orden y con para qué sirve cada uno', () {
    final study = stepOf(groups(), NavStep.study);

    expect(
      [for (final d in study.destinations) (d.label, d.hint)],
      [
        (es.navProcessed, es.navProcessedHint),
        (es.navNotebooks, es.navNotebooksHint),
        (es.navTimeline, es.navTimelineHint),
        (es.navMap, es.navMapHint),
        (es.navReview, es.navReviewHint),
      ],
    );
    for (final d in study.destinations) {
      expect(d.step, NavStep.study, reason: d.label);
    }
  });

  test('Repasar conserva su nombre, y su línea dice que además crea sobre lo '
      'procesado (F43)', () {
    final review = destinations().singleWhere(
      (d) => d.branchIndex == ShellBranch.review.index,
    );

    expect(review.label, 'Repasar');
    expect(
      review.hint,
      'Tus tarjetas, y presentaciones, resúmenes y cuestionarios de lo '
      'procesado',
    );
    expect(iconOf(review.icon), Icons.style_outlined);
  });

  test('la línea de tiempo (F40) mantiene su nombre y su ícono', () {
    final timeline = stepOf(groups(), NavStep.study).destinations.singleWhere(
      (d) => d.branchIndex == ShellBranch.timeline.index,
    );

    expect((timeline.icon as Icon).icon, Icons.timeline);
    expect(timeline.label, es.navTimeline);
  });

  test('las ramas de la línea de tiempo y de Procesado están al final: '
      'sumarlas no corrió el índice de ninguna de las de antes', () {
    expect(ShellBranch.processed.index, ShellBranch.values.length - 1);
    expect(ShellBranch.timeline.index, ShellBranch.processed.index - 1);
    expect(ShellBranch.notebooks.index, ShellBranch.timeline.index - 1);
  });

  test('Procesado (F41) es el primero de «Estudiar», con su línea y un ícono '
      'que no usa otro destino', () {
    final processed = stepOf(groups(), NavStep.study).destinations.first;

    expect(processed.branchIndex, ShellBranch.processed.index);
    expect(processed.label, es.navProcessed);
    expect(processed.hint, 'La información que sacaste de cada fuente');
    expect((processed.icon as Icon).icon, Icons.summarize_outlined);
    expect((processed.selectedIcon as Icon).icon, Icons.summarize);

    for (final other in destinations()) {
      if (other.branchIndex == ShellBranch.processed.index) continue;
      expect(iconOf(other.icon), isNot(Icons.summarize_outlined));
      expect(iconOf(other.selectedIcon), isNot(Icons.summarize));
    }
  });

  test('los cuadernos van segundos en «Estudiar», debajo de Procesado', () {
    final notebooks = stepOf(groups(), NavStep.study).destinations[1];

    expect(notebooks.branchIndex, ShellBranch.notebooks.index);
    expect(notebooks.label, es.navNotebooks);
    expect(notebooks.hint, es.navNotebooksHint);
  });

  group('insignias', () {
    test('los pendientes de la Bandeja se ven en «Organizar», y no en '
        '«Estudiar»', () {
      final result = groups(pendingInboxCount: 3);
      final organize = stepOf(result, NavStep.organize);

      for (final icon in [organize.icon, organize.selectedIcon]) {
        final badge = badgeOf(icon);
        expect(badge.isLabelVisible, isTrue);
        expect((badge.label! as Text).data, '3');
      }
      expect(
        badgeOf(stepOf(result, NavStep.study).icon).isLabelVisible,
        isFalse,
      );
    });

    test('las tarjetas para hoy se ven en «Estudiar» (F43), y no en '
        '«Organizar»', () {
      final result = groups(dueFlashcardCount: 7);
      final study = stepOf(result, NavStep.study);

      for (final icon in [study.icon, study.selectedIcon]) {
        final badge = badgeOf(icon);
        expect(badge.isLabelVisible, isTrue);
        expect((badge.label! as Text).data, '7');
      }
      expect(
        badgeOf(stepOf(result, NavStep.organize).icon).isLabelVisible,
        isFalse,
      );
    });

    test('Repasar guarda su propia insignia, para el riel y la lista', () {
      final review = destinations(
        dueFlashcardCount: 5,
      ).singleWhere((d) => d.branchIndex == ShellBranch.review.index);

      expect(review.badgeCount, 5);
      expect((badgeOf(review.icon).label! as Text).data, '5');
      expect((badgeOf(review.selectedIcon).label! as Text).data, '5');
    });

    test('sin pendientes, ningún paso muestra insignia', () {
      final result = groups();

      for (final step in [NavStep.organize, NavStep.study]) {
        final group = stepOf(result, step);
        expect(badgeOf(group.icon).isLabelVisible, isFalse, reason: '$step');
        expect(
          badgeOf(group.selectedIcon).isLabelVisible,
          isFalse,
          reason: '$step',
        );
      }
    });
  });

  test('sin chat (la web) no hay «Preguntar», y «Estudiar» sigue entero con '
      'su insignia', () {
    final result = groups(includeChat: false, dueFlashcardCount: 2);

    expect(
      [for (final g in result) g.step],
      [NavStep.save, NavStep.organize, NavStep.study, NavStep.settings],
    );
    final study = stepOf(result, NavStep.study);
    expect(
      [for (final d in study.destinations) d.branchIndex],
      at([
        ShellBranch.processed,
        ShellBranch.notebooks,
        ShellBranch.timeline,
        ShellBranch.graph,
        ShellBranch.review,
      ]),
    );
    expect((badgeOf(study.icon).label! as Text).data, '2');
    expect([
      for (final d in destinations(includeChat: false)) d.branchIndex,
    ], isNot(contains(ShellBranch.chat.index)));
  });

  test('cada destino dice para qué sirve', () {
    expect(
      {for (final d in destinations()) d.branchIndex: d.hint},
      {
        ShellBranch.library.index: es.navLibraryHint,
        ShellBranch.inbox.index: es.navInboxHint,
        ShellBranch.processed.index: es.navProcessedHint,
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
