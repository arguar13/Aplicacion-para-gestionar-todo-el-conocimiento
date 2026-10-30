import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/creations/data/repositories/creation_scope_resolver_impl.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_catalog.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_scope_resolver.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/processed_rows.dart';
import 'repasar_harness.dart';

/// El recorte de verdad, contando qué se le pide: así se ve que la hoja lee
/// en lote y no una vez por fila.
class _CountingScopes implements CreationScopeResolver {
  _CountingScopes(this._inner);

  final CreationScopeResolver _inner;
  final summaries = <CreationScope>[];
  final catalogs = <Set<CreationScope>>[];
  int sources = 0;

  @override
  Future<Either<Failure, List<String>>> documentIds(CreationScope scope) =>
      _inner.documentIds(scope);

  @override
  Future<Either<Failure, Set<String>?>> studyItemIds(String scopeKey) =>
      _inner.studyItemIds(scopeKey);

  @override
  Future<Either<Failure, List<CreationSource>>> sourcesOf(
    List<String> documentIds,
  ) {
    sources++;
    return _inner.sourcesOf(documentIds);
  }

  @override
  Stream<CreationScopeSummary> watchSummary(CreationScope scope) {
    summaries.add(scope);
    return _inner.watchSummary(scope);
  }

  @override
  Stream<CreationScopeCatalog> watchCatalog(Set<CreationScope> topics) {
    catalogs.add(topics);
    return _inner.watchCatalog(topics);
  }
}

/// El selector de Repasar (F43, M11): arriba el buscador y las pestañas;
/// debajo una sola lista —«Recientes» y «Todos», sin repetir—, cada fila con
/// la misma línea en todos lados; la búsqueda en una sola lista; fluido con
/// miles de documentos; en 360 dp con la letra al doble y con el lector de
/// pantalla.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;
  late _CountingScopes scopes;

  setUp(() async {
    harness = await RepasarHarness.create(
      overrides: [
        creationScopeResolverProvider.overrideWith(
          (ref) => scopes = _CountingScopes(
            CreationScopeResolverImpl(
              database: ref.watch(appDatabaseProvider),
              processed: ref.watch(processedRepositoryProvider),
              notebooks: ref.watch(notebookRepositoryProvider),
              telemetry: ref.watch(telemetryServiceProvider),
            ),
          ),
        ),
      ],
    );
  });

  Finder option(CreationScope scope) =>
      find.byKey(ValueKey('creation-scope-option-${scope.storageKey}'));

  Finder recent(CreationScope scope) =>
      find.byKey(ValueKey('creation-scope-recent-${scope.storageKey}'));

  /// Los textos de la fila de [scope], en orden.
  List<String> textsOf(WidgetTester tester, CreationScope scope) => [
    for (final text in tester.widgetList<Text>(
      find.descendant(of: option(scope), matching: find.byType(Text)),
    ))
      text.data!,
  ];

  Future<void> openPicker(
    WidgetTester tester, {
    Size size = const Size(420, 1600),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) async {
    await harness.openRepasar(
      tester,
      size: size,
      theme: theme,
      textScale: textScale,
    );
    await tester.tap(find.byKey(const Key('repasar-scope')));
    await tester.pumpAndSettle();
  }

  Future<void> closePicker(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('creation-scope-close')));
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String name) async {
    final chip = find.byKey(Key('creation-scope-tab-$name'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  /// Un documento procesado con [cards] tarjetas y, si se pide, su resumen y
  /// su síntesis marcados.
  Future<void> document(
    String id,
    String title, {
    int cards = 0,
    bool summary = false,
    bool synthesis = false,
  }) async {
    await insertProcessedRows(
      harness.library.database,
      id: id,
      title: title,
      parts: {
        ProcessedSection.notes: const ['Una nota.'],
        if (summary) ProcessedSection.summary: const ['El resumen.'],
        if (synthesis) ProcessedSection.synthesis: const ['La síntesis.'],
      },
    );
    for (var i = 0; i < cards; i++) {
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: id, front: '¿$title $i?', back: 'R $i');
    }
  }

  void remember(List<CreationScope> chosen) {
    final recents = harness.container.read(
      recentCreationScopesProvider.notifier,
    );
    for (final scope in chosen.reversed) {
      recents.remember(scope);
    }
  }

  group('una sola lista', () {
    testWidgets('arriba el buscador y las pestañas; debajo «Todo lo '
        'procesado», «Recientes» y «Todos» de la A a la Z, sin repetir', (
      tester,
    ) async {
      await document('p-exo', 'Éxodo', cards: 2);
      await document('p-gen', 'Génesis');
      await document('p-dan', 'Daniel');
      remember([const CreationScope.document('p-gen')]);
      await openPicker(tester);

      double top(Finder finder) => tester.getTopLeft(finder).dy;
      final search = top(find.byKey(const Key('creation-scope-search')));
      final tabs = top(find.byKey(const Key('creation-scope-tabs')));
      final all = top(option(const CreationScope.allProcessed()));
      final recentLabel = top(find.text(es.f43StudioPickerRecent));
      final genesis = top(recent(const CreationScope.document('p-gen')));
      final everything = top(find.text(es.f43S18Everything));
      final daniel = top(option(const CreationScope.document('p-dan')));
      final exodo = top(option(const CreationScope.document('p-exo')));
      expect(
        [search, tabs, all, recentLabel, genesis, everything, daniel, exodo],
        orderedEquals(
          [search, tabs, all, recentLabel, genesis, everything, daniel, exodo]
            ..sort(),
        ),
      );
      expect(search, lessThan(tabs));
      expect(everything, lessThan(daniel));
      // El reciente no se repite abajo.
      expect(option(const CreationScope.document('p-gen')), findsOneWidget);
      for (final name in [
        es.f43S18TabAll,
        es.f43S18TabDocuments,
        es.f43S18TabNotebooks,
        es.f43S18TabTopics,
      ]) {
        expect(
          find.descendant(
            of: find.byKey(const Key('creation-scope-tabs')),
            matching: find.text(name),
          ),
          findsOneWidget,
        );
      }
      expect(textsOf(tester, const CreationScope.allProcessed()), [
        es.f43StudioScopeAll,
        es.f43StudioDocuments(3),
        es.f43StudioCards(2),
      ]);
    });

    testWidgets('cada pestaña, con sus recientes —como mucho tres— y lo '
        'demás', (tester) async {
      for (final (id, title) in [
        ('p-a', 'Amós'),
        ('p-b', 'Baruc'),
        ('p-c', 'Crónicas'),
        ('p-d', 'Daniel'),
      ]) {
        await document(id, title);
      }
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Profetas', mode: NotebookMode.manual);
      remember([
        CreationScope.notebook(notebook.id),
        const CreationScope.document('p-d'),
        const CreationScope.document('p-c'),
        const CreationScope.document('p-b'),
      ]);
      await openPicker(tester);

      expect(recent(CreationScope.notebook(notebook.id)), findsOneWidget);
      expect(recent(const CreationScope.document('p-b')), findsNothing);

      await tab(tester, 'document');
      expect(recent(const CreationScope.document('p-d')), findsOneWidget);
      expect(recent(const CreationScope.document('p-c')), findsOneWidget);
      expect(recent(const CreationScope.document('p-b')), findsOneWidget);
      expect(option(const CreationScope.document('p-a')), findsOneWidget);
      expect(recent(CreationScope.notebook(notebook.id)), findsNothing);
      expect(option(CreationScope.notebook(notebook.id)), findsNothing);
      expect(option(const CreationScope.allProcessed()), findsNothing);

      await tab(tester, 'notebook');
      expect(recent(CreationScope.notebook(notebook.id)), findsOneWidget);
      expect(find.text(es.f43S18Everything), findsNothing);
    });

    testWidgets('un tema con su rama: «Roma › Imperio», junto a «Roma»', (
      tester,
    ) async {
      await document('p-1', 'Augusto');
      await document('p-2', 'Cicerón');
      final db = harness.library.database;
      final tema = await temaDefinitionId(db);
      for (final (id, value) in [('roma', 'Roma'), ('imp', 'Imperio')]) {
        await db.customStatement(
          'INSERT INTO property_values (id, definition_id, value, created_at) '
          'VALUES (?, ?, ?, 0)',
          [id, tema, value],
        );
      }
      await db.customUpdate(
        "UPDATE property_values SET parent_id = 'roma' WHERE id = 'imp'",
      );
      await db.customStatement(
        'INSERT INTO item_property_values (item_id, property_value_id) '
        "VALUES ('p-1', 'imp'), ('p-2', 'roma')",
      );
      await openPicker(tester);
      await tab(tester, 'topic');

      expect(textsOf(tester, const CreationScope.topic('roma')).first, 'Roma');
      expect(
        textsOf(tester, const CreationScope.topic('imp')).first,
        'Roma › Imperio',
      );
      expect(
        textsOf(tester, const CreationScope.topic('roma'))[1],
        es.f43StudioDocuments(2),
        reason: 'con su rama, como el Atlas',
      );
      await tester.tap(option(const CreationScope.topic('imp')));
      await tester.pumpAndSettle();
      expect(harness.scope, const CreationScope.topic('imp'));
    });
  });

  group('cada fila', () {
    testWidgets('la misma línea en «Recientes» y en «Todos», cada dato con '
        'el ícono y el color de su tipo', (tester) async {
      await document(
        'p-exo',
        'Éxodo',
        cards: 12,
        summary: true,
        synthesis: true,
      );
      await harness.creation(
        StudyCreationKind.quiz,
        scope: const CreationScope.document('p-exo'),
        sources: ['p-exo'],
      );
      const exodo = CreationScope.document('p-exo');
      final line = [
        'Éxodo',
        es.f43StudioCards(12),
        es.f43StudioCreations(1),
        es.f43S18Summary,
        es.f43S18Synthesis,
      ];
      await openPicker(tester);
      await tab(tester, 'document');
      expect(recent(exodo), findsNothing);
      expect(textsOf(tester, exodo), line);

      // Los íconos: el de las tarjetas, el resumen y la síntesis con el color
      // de su tipo, como en la grilla.
      final kinds = harness.container.read(creationKindRegistryProvider);
      final context = tester.element(option(exodo));
      final theme = Theme.of(context);
      final background = theme.colorScheme.surfaceContainerLow;
      final icons = tester.widgetList<Icon>(
        find.descendant(of: option(exodo), matching: find.byType(Icon)),
      );
      for (final kind in [
        StudyCreationKind.flashcards,
        StudyCreationKind.summary,
        StudyCreationKind.synthesis,
      ]) {
        final spec = kinds.of(kind);
        final icon = icons.singleWhere((i) => i.icon == spec.iconData);
        expect(
          icon.color,
          spec.accent.resolve(theme.brightness, background),
          reason: kind.storageKey,
        );
      }

      await closePicker(tester);
      remember([exodo]);
      await tester.tap(find.byKey(const Key('repasar-scope')));
      await tester.pumpAndSettle();
      await tab(tester, 'document');
      expect(recent(exodo), findsOneWidget);
      expect(textsOf(tester, exodo), line);
    });

    testWidgets('lo elegido lleva ✓ y va resaltado; lo demás no', (
      tester,
    ) async {
      await document('p-exo', 'Éxodo', cards: 1);
      await document('p-gen', 'Génesis');
      harness.container.read(repasarScopeProvider.notifier).state =
          const CreationScope.document('p-exo');
      await openPicker(tester);

      // Abre en su pestaña.
      expect(option(const CreationScope.allProcessed()), findsNothing);
      Finder check(CreationScope scope) => find.descendant(
        of: option(scope),
        matching: find.byIcon(Icons.check_circle),
      );
      Color colorOf(CreationScope scope) => tester
          .widget<Material>(
            find
                .descendant(of: option(scope), matching: find.byType(Material))
                .first,
          )
          .color!;
      final scheme = Theme.of(
        tester.element(option(const CreationScope.document('p-exo'))),
      ).colorScheme;
      expect(check(const CreationScope.document('p-exo')), findsOneWidget);
      expect(check(const CreationScope.document('p-gen')), findsNothing);
      expect(
        colorOf(const CreationScope.document('p-exo')),
        scheme.secondaryContainer,
      );
      expect(
        colorOf(const CreationScope.document('p-gen')),
        isNot(scheme.secondaryContainer),
      );
    });

    testWidgets('el lector de pantalla lee cada fila entera', (tester) async {
      final semantics = tester.ensureSemantics();
      await document('p-exo', 'Éxodo', cards: 12, summary: true);
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Examen', mode: NotebookMode.manual);
      await harness.container
          .read(notebookRepositoryProvider)
          .addItems(notebookId: notebook.id, itemIds: ['p-exo']);
      harness.container.read(repasarScopeProvider.notifier).state =
          CreationScope.notebook(notebook.id);
      await openPicker(tester);
      await tab(tester, 'all');

      expect(
        tester.getSemantics(option(const CreationScope.document('p-exo'))),
        isSemantics(
          label:
              'Éxodo, ${es.f43StudioPickerTabDocument}. '
              '${es.f43StudioCards(12)}, ${es.f43S18Summary}',
          isButton: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(option(CreationScope.notebook(notebook.id))),
        isSemantics(
          label:
              'Examen, ${es.f43StudioPickerTabNotebook}. '
              '${es.f43StudioDocuments(1)}, ${es.f43StudioCards(12)}. '
              '${es.f43StudioPickerChosen}',
          isButton: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });
  });

  group('el buscador', () {
    testWidgets('filtra todo, sin acentos, en una sola lista de resultados', (
      tester,
    ) async {
      await document('p-exo', 'Éxodo');
      await document('p-gen', 'Génesis');
      await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Repaso del éxodo', mode: NotebookMode.manual);
      remember([const CreationScope.document('p-exo')]);
      await openPicker(tester);

      await tester.enterText(
        find.byKey(const Key('creation-scope-search')),
        'EXODO',
      );
      await tester.pumpAndSettle();

      expect(find.text(es.f43S18Results(2)), findsOneWidget);
      expect(find.text('Éxodo'), findsOneWidget);
      expect(find.text('Repaso del éxodo'), findsOneWidget);
      expect(find.text('Génesis'), findsNothing);
      expect(find.text(es.f43StudioPickerRecent), findsNothing);
      expect(find.text(es.f43S18Everything), findsNothing);
      expect(option(const CreationScope.allProcessed()), findsNothing);

      // En una pestaña, solo lo suyo.
      await tab(tester, 'notebook');
      expect(find.text(es.f43S18Results(1)), findsOneWidget);
      expect(find.text('Éxodo'), findsNothing);

      await tester.tap(find.text('Repaso del éxodo'));
      await tester.pumpAndSettle();
      expect(harness.scope, isA<NotebookScope>());
    });
  });

  testWidgets('el buscador también encuentra lo que está en el texto, '
      'después de lo que lo tiene en el nombre', (tester) async {
    await insertProcessedRows(
      harness.library.database,
      id: 'p-gen',
      title: 'Génesis',
      parts: {
        ProcessedSection.notes: const ['José y el faraón de Egipto.'],
      },
    );
    await document('p-far', 'Los faraones');
    await document('p-dan', 'Daniel');
    await openPicker(tester);
    await tester.enterText(
      find.byKey(const Key('creation-scope-search')),
      'faraón',
    );
    await tester.pumpAndSettle();

    expect(find.text(es.f43S18Results(2)), findsOneWidget);
    expect(
      tester.getTopLeft(option(const CreationScope.document('p-far'))).dy,
      lessThan(
        tester.getTopLeft(option(const CreationScope.document('p-gen'))).dy,
      ),
    );
    expect(option(const CreationScope.document('p-dan')), findsNothing);
  });

  group('con miles de documentos', () {
    testWidgets('lee todo en lote, sin una consulta por fila, y la lista se '
        'arma de a lo que se ve', (tester) async {
      final db = harness.library.database;
      await db.transaction(() async {
        for (var i = 0; i < 1500; i++) {
          final id = 'd-${'$i'.padLeft(4, '0')}';
          await insertProcessedRows(db, id: id, title: 'Doc $id');
        }
      });
      remember([
        const CreationScope.document('d-0007'),
        const CreationScope.document('d-1200'),
      ]);
      await openPicker(tester);
      await tab(tester, 'document');

      expect(scopes.catalogs, hasLength(1), reason: 'una sola lectura en lote');
      expect(scopes.sources, 0);
      expect(scopes.summaries.toSet(), {
        const CreationScope.allProcessed(),
      }, reason: 'solo la píldora pide lo suyo');
      final built = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'creation-scope-option-',
            ),
      );
      expect(built.evaluate().length, lessThan(60));

      // Hasta el final, de la A a la Z, sin pedir nada más.
      final last = option(const CreationScope.document('d-1499'));
      await tester.scrollUntilVisible(
        last,
        4000,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('creation-scope-list')),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 200,
      );
      expect(last, findsOneWidget);
      expect(built.evaluate().length, lessThan(60));
      expect(scopes.catalogs, hasLength(1));
      expect(scopes.summaries.toSet(), {const CreationScope.allProcessed()});

      // Escribir no vuelve a leer.
      await tester.enterText(
        find.byKey(const Key('creation-scope-search')),
        'd-12',
      );
      await tester.pumpAndSettle();
      expect(find.text(es.f43S18Results(100)), findsOneWidget);
      expect(scopes.catalogs, hasLength(1));
    });
  });

  testWidgets('un reciente que ya no existe se olvida', (tester) async {
    await document('p-exo', 'Éxodo');
    await document('p-gen', 'Génesis');
    remember([
      const CreationScope.document('p-gen'),
      const CreationScope.document('p-exo'),
    ]);
    await harness.library.database.customUpdate(
      'UPDATE item SET deleted_at = 1 WHERE id = ?',
      variables: [Variable.withString('p-gen')],
    );
    await openPicker(tester);

    expect(recent(const CreationScope.document('p-exo')), findsOneWidget);
    expect(recent(const CreationScope.document('p-gen')), findsNothing);
    expect(harness.container.read(recentCreationScopesProvider), [
      const CreationScope.document('p-exo'),
    ]);
  });

  for (final theme in [AppThemeChoice.light, AppThemeChoice.dark]) {
    testWidgets('360 dp, letra al doble, tema ${theme.name}: nada se '
        'desborda', (tester) async {
      await document(
        'p-1',
        'Declaración de los Derechos del Hombre y del Ciudadano, comentada '
            'párrafo por párrafo',
        cards: 12,
        summary: true,
        synthesis: true,
      );
      await harness.creation(
        StudyCreationKind.report,
        scope: const CreationScope.document('p-1'),
        sources: ['p-1'],
      );
      await document('p-2', 'Génesis');
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(
            name: 'Un cuaderno con un nombre larguísimo para el examen final',
            mode: NotebookMode.manual,
          );
      remember([
        const CreationScope.document('p-1'),
        CreationScope.notebook(notebook.id),
      ]);
      harness.container.read(repasarScopeProvider.notifier).state =
          const CreationScope.document('p-1');
      await openPicker(
        tester,
        size: const Size(360, 800),
        theme: theme,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);

      for (final name in ['all', 'document', 'notebook', 'topic', 'all']) {
        final chip = find.byKey(Key('creation-scope-tab-$name'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
      }
      await tester.enterText(
        find.byKey(const Key('creation-scope-search')),
        'cuaderno',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
