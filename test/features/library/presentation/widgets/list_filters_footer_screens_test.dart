import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_status_presentation.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_item_card.dart';
import 'package:sinapsis/features/library/presentation/widgets/list_controls.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_document_card.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_presentation.dart';
import 'package:sinapsis/features/processed/presentation/widgets/retriage/retriage_picker.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';
import '../../../processed/presentation/processed_ui_fixture.dart';

/// El pie «Ver N resultados» del panel de filtros (F47, mejora 21) en cada
/// pantalla que lo usa —la Biblioteca, Procesado, «Volver a triar» y el
/// Explorador—, contando contra la base real del arnés: la cifra sigue a
/// cada filtro, sin filtros dice «Ver todo», con cero se apaga, y tocarlo
/// cierra el panel con la lista ya filtrada, desde arriba. En un teléfono de
/// 360 con la letra al doble, en claro y en oscuro.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  final footer = find.byKey(ListFiltersSheet.showResultsKey);

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// Una prueba con el árbol del lector de pantalla armado: lo que dice el
  /// pie se lee de ahí.
  void testWithSemantics(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) => testWidgets(description, (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      semantics.dispose();
    }
  });

  /// La app con su router de verdad y la bóveda abierta, como
  /// `wrapWithAppRouter`, en un teléfono de 360 con la letra al doble y en
  /// [brightness]; en [location].
  Future<void> pumpPhone(
    WidgetTester tester,
    String location, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view
      ..physicalSize = const Size(360, 780)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    harness.container
        .read(vaultSessionControllerProvider.notifier)
        .markUnlocked();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: ref.watch(goRouterProvider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await goAndSettle(tester, harness, location);
  }

  /// Lo que dice el pie, como lo oye el lector de pantalla.
  String footerLabel(WidgetTester tester) => tester.getSemantics(footer).label;

  bool footerEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(footer).onPressed != null;

  Future<void> openFilters(WidgetTester tester, {Finder? within}) async {
    final button = find.byTooltip(es.libraryFiltersTooltip);
    await tester.tap(
      within == null ? button : find.descendant(of: within, matching: button),
    );
    await tester.pumpAndSettle();
    expect(footer, findsOneWidget);
  }

  /// Toca el chip [label] del panel, desplazándolo antes hasta verlo: con la
  /// letra al doble, las últimas secciones quedan debajo del pie.
  Future<void> tapChip(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(FilterChip, label);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  Future<void> tapClear(WidgetTester tester) async {
    final clear = find.descendant(
      of: find.byType(ListFiltersSheet),
      matching: find.text(es.libraryClearFilters),
    );
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();
  }

  /// Toca el pie: el panel se cierra.
  Future<void> showResults(WidgetTester tester) async {
    await tester.tap(footer);
    await tester.pumpAndSettle();
    expect(footer, findsNothing);
    expect(tester.takeException(), isNull);
  }

  for (final brightness in Brightness.values) {
    group('en ${brightness.name}', () {
      group('la Biblioteca', () {
        setUp(() async {
          await insertItemRows(harness.database, id: 'a', title: 'Uno');
          await insertItemRows(harness.database, id: 'b', title: 'Dos');
          await insertItemRows(
            harness.database,
            id: 'c',
            title: 'Un video',
            kind: SourceKind.youtube,
          );
        });

        List<String> titles(WidgetTester tester) => [
          for (final card in tester.widgetList<LibraryItemCard>(
            find.byType(LibraryItemCard),
          ))
            card.item.title,
        ];

        testWithSemantics('la cifra sigue a cada filtro; con cero se apaga y '
            '«Limpiar filtros» sigue arriba; tocarlo cierra con la lista '
            'filtrada', (tester) async {
          await pumpPhone(tester, RoutePaths.library, brightness: brightness);
          await openFilters(tester);
          expect(tester.takeException(), isNull);

          expect(footerLabel(tester), es.f47P0FiltersShowAll(3));
          expect(footerLabel(tester), 'Ver todo (3)');

          await tapChip(tester, SourceKind.youtube.label(es));
          expect(footerLabel(tester), 'Ver 1 resultado');
          expect(footerEnabled(tester), isTrue);

          // Un tipo de video que se descartó: no hay ninguno.
          await tapChip(tester, InboxStatus.discarded.filterLabel(es));
          expect(footerLabel(tester), es.f47P0FiltersNoResults);
          expect(footerEnabled(tester), isFalse);
          expect(tester.takeException(), isNull);

          await tapClear(tester);
          expect(footerLabel(tester), 'Ver todo (3)');

          await tapChip(tester, SourceKind.webPage.label(es));
          expect(footerLabel(tester), 'Ver 2 resultados');

          await showResults(tester);
          expect(titles(tester).toSet(), {'Uno', 'Dos'});
        });

        testWithSemantics(
          'con lo buscado y sin filtros, cuántos encontró, no «Ver '
          'todo»',
          (tester) async {
            await pumpPhone(tester, RoutePaths.library, brightness: brightness);
            await tester.enterText(find.byType(TextField).first, 'video');
            await tester.pumpAndSettle();

            await openFilters(tester);
            expect(footerLabel(tester), 'Ver 1 resultado');
          },
        );
      });

      group('Procesado', () {
        setUp(() async {
          await harness.saveTextSource('roma', title: 'Roma');
          await harness.saveTextSource('grecia', title: 'Grecia');
          await harness.processTextAndNotes('roma', notes: ['Una idea mía']);
          await harness.processTextAndNotes('grecia');
        });

        List<String> rows(WidgetTester tester) => [
          for (final card in tester.widgetList<ProcessedDocumentCard>(
            find.byType(ProcessedDocumentCard),
          ))
            card.document.title,
        ];

        testWithSemantics(
          'el mismo pie, con su cuenta: las partes, el cero y el '
          'cierre',
          (tester) async {
            await pumpPhone(
              tester,
              RoutePaths.processed,
              brightness: brightness,
            );
            await openFilters(tester);
            expect(tester.takeException(), isNull);
            expect(footerLabel(tester), 'Ver todo (2)');

            await tapChip(tester, ProcessedSection.notes.label(es));
            expect(footerLabel(tester), 'Ver 1 resultado');

            // De un video no salió ninguno.
            await tapChip(tester, SourceKind.youtube.label(es));
            expect(footerLabel(tester), es.f47P0FiltersNoResults);
            expect(footerEnabled(tester), isFalse);

            await tapChip(tester, SourceKind.youtube.label(es));
            expect(footerLabel(tester), 'Ver 1 resultado');

            await showResults(tester);
            expect(rows(tester), ['Roma']);
          },
        );
      });

      group('«Volver a triar»', () {
        setUp(() async {
          await harness.saveTextSource('roma', title: 'Roma');
          await harness.saveTextSource('grecia', title: 'Grecia');
          await harness.processTextAndNotes('roma');
          await harness.markTriaged('roma');
          // Una nota propia no es una fuente: ni se lista ni se cuenta.
          await insertItemRows(
            harness.database,
            id: 'nota',
            title: 'Mi nota',
            kind: SourceKind.manualNote,
          );
        });

        final picker = find.byKey(const Key('retriage-picker'));

        List<String> candidates(WidgetTester tester) => [
          for (final tile in tester.widgetList<RetriageCandidateTile>(
            find.byType(RetriageCandidateTile),
          ))
            tile.item.title,
        ];

        testWithSemantics('el mismo pie, con lo que cuenta el selector: solo '
            'fuentes; tocarlo cierra los filtros y deja el selector', (
          tester,
        ) async {
          await pumpPhone(tester, RoutePaths.inbox, brightness: brightness);
          await tester.tap(find.byKey(const Key('inbox-retriage')));
          await tester.pumpAndSettle();
          expect(picker, findsOneWidget);

          await openFilters(tester, within: picker);
          expect(tester.takeException(), isNull);
          expect(footerLabel(tester), 'Ver todo (2)');

          await tapChip(tester, InboxStatus.triaged.filterLabel(es));
          expect(footerLabel(tester), 'Ver 1 resultado');

          await tapChip(tester, InboxStatus.discarded.filterLabel(es));
          expect(footerLabel(tester), 'Ver 1 resultado');

          await tapChip(tester, InboxStatus.triaged.filterLabel(es));
          expect(footerLabel(tester), es.f47P0FiltersNoResults);
          expect(footerEnabled(tester), isFalse);

          await tapClear(tester);
          await tapChip(tester, InboxStatus.triaged.filterLabel(es));

          await showResults(tester);
          expect(picker, findsOneWidget);
          // Con la letra al doble, la explicación de arriba ocupa lo que se
          // ve: la fila elegida está más abajo.
          await tester.scrollUntilVisible(
            find.byType(RetriageCandidateTile),
            200,
            scrollable: find
                .descendant(of: picker, matching: find.byType(Scrollable))
                .last,
          );
          expect(candidates(tester), ['Roma']);
        });
      });

      group('el Explorador', () {
        setUp(() async {
          await insertProcessedDocument(
            harness.database,
            id: 'p1',
            title: 'Una página',
          );
          await insertProcessedDocument(
            harness.database,
            id: 'p2',
            title: 'Un libro',
            sourceKind: SourceKind.document,
          );
        });

        testWithSemantics('el mismo marco y el mismo pie', (tester) async {
          tester.view
            ..physicalSize = const Size(360, 780)
            ..devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: harness.container,
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: brightness == Brightness.dark
                    ? ThemeMode.dark
                    : ThemeMode.light,
                locale: const Locale('es'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const ExplorerScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await openFilters(tester);
          expect(tester.takeException(), isNull);
          expect(footerLabel(tester), 'Ver todo (2)');

          await tapChip(tester, SourceKind.document.label(es));
          expect(footerLabel(tester), 'Ver 1 resultado');

          await showResults(tester);
          expect(find.text('Un libro'), findsOneWidget);
          expect(find.text('Una página'), findsNothing);
        });
      });
    });
  }

  group('desde arriba', () {
    /// Lo que la lista de [within] se desplazó.
    double offsetOf(WidgetTester tester, Finder list) => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position
        .pixels;

    testWithSemantics('la Biblioteca: tocarlo deja la lista desde el primero, '
        'aunque no haya cambiado ningún filtro', (tester) async {
      for (var i = 0; i < 30; i++) {
        await insertItemRows(
          harness.database,
          id: 'e$i',
          title: 'Elemento $i',
          createdAt: DateTime(2026, 9, 2).add(Duration(minutes: i)),
        );
      }
      await pumpPhone(tester, RoutePaths.library);
      final list = find.byType(ListView);
      await tester.drag(list.first, const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(offsetOf(tester, list.first), greaterThan(0));

      await openFilters(tester);
      expect(footerLabel(tester), 'Ver todo (30)');
      await showResults(tester);

      expect(offsetOf(tester, list.first), 0);
    });

    testWithSemantics('Procesado, igual', (tester) async {
      for (var i = 0; i < 20; i++) {
        await insertProcessedDocument(
          harness.database,
          id: 'p$i',
          title: 'Documento $i',
          createdAt: DateTime(2026, 9, 2).add(Duration(minutes: i)),
        );
      }
      await pumpPhone(tester, RoutePaths.processed);
      final list = find.byType(ListView);
      await tester.drag(list.first, const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(offsetOf(tester, list.first), greaterThan(0));

      await openFilters(tester);
      await showResults(tester);

      expect(offsetOf(tester, list.first), 0);
    });

    testWithSemantics('cerrado de otra forma, la lista queda donde estaba', (
      tester,
    ) async {
      for (var i = 0; i < 30; i++) {
        await insertItemRows(
          harness.database,
          id: 'e$i',
          title: 'Elemento $i',
          createdAt: DateTime(2026, 9, 2).add(Duration(minutes: i)),
        );
      }
      await pumpPhone(tester, RoutePaths.library);
      final list = find.byType(ListView);
      await tester.drag(list.first, const Offset(0, -1500));
      await tester.pumpAndSettle();
      final scrolled = offsetOf(tester, list.first);

      await openFilters(tester);
      Navigator.of(tester.element(footer)).pop();
      await tester.pumpAndSettle();

      expect(offsetOf(tester, list.first), scrolled);
    });
  });

  testWithSemantics('la Biblioteca, en la tabla: también desde arriba', (
    tester,
  ) async {
    // La tabla es la otra vista que se recorre de arriba abajo; el tablero y
    // el calendario no tienen un «arriba» que recuperar.
    for (var i = 0; i < 30; i++) {
      await insertItemRows(
        harness.database,
        id: 'e$i',
        title: 'Elemento $i',
        createdAt: DateTime(2026, 9, 2).add(Duration(minutes: i)),
      );
    }
    await pumpPhone(tester, RoutePaths.library);
    expect(find.byType(LibraryScreen), findsOneWidget);
    await tester.tap(find.byTooltip(es.libraryViewList));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.libraryViewTable).last);
    await tester.pumpAndSettle();

    final table = find.byType(DataTable);
    final vertical = find
        .ancestor(of: table, matching: find.byType(Scrollable))
        .first;
    // En el medio de lo que se ve: la tabla es más ancha que la pantalla.
    await tester.dragFrom(const Offset(180, 450), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(vertical).position.pixels,
      greaterThan(0),
    );

    await openFilters(tester);
    await showResults(tester);

    expect(tester.state<ScrollableState>(vertical).position.pixels, 0);
  });
}
