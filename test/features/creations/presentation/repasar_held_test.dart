import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/screens/creation_viewer_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/processed_rows.dart';
import 'repasar_harness.dart';

/// Repasar con lo que el recorte ya tenía (F43, M10) y su orden nuevo (M14):
/// las tarjetas, el resumen y la síntesis marcados tienen su fila arriba de
/// lo creado —y «Todavía no creaste nada» solo se ve sin nada de nada—, y
/// «Para hoy» va debajo de «Lo creado».
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;

  setUp(() async {
    harness = await RepasarHarness.create();
  });

  /// Un documento procesado con [summary] y [synthesis] marcados en el
  /// original —lo marcado vive en sus secciones— y [cards] tarjetas.
  Future<void> document(
    String id,
    String title, {
    bool summary = false,
    bool synthesis = false,
    int cards = 0,
  }) async {
    await insertProcessedRows(
      harness.library.database,
      id: id,
      title: title,
      parts: {
        ProcessedSection.notes: ['Una nota.'],
        if (summary) ProcessedSection.summary: ['Moisés guía al pueblo.'],
        if (synthesis) ProcessedSection.synthesis: ['El mar se abre.'],
      },
    );
    for (var i = 0; i < cards; i++) {
      await harness.container
          .read(flashcardRepositoryProvider)
          .create(itemId: id, front: '¿$title $i?', back: 'R $i');
    }
  }

  /// Marca [section] en [id] con la app abierta, como «Marcar» en el original.
  Future<void> mark(String id, ProcessedSection section) async {
    final db = harness.library.database;
    final at = DateTime(2026, 10, 29);
    await db
        .into(db.processedParts)
        .insert(
          ProcessedPartsCompanion.insert(
            id: '$id-${section.name}-nueva',
            documentId: id,
            section: section,
            position: 0,
            content: 'Llegan al Sinaí.',
            origin: ProcessedPartOrigin.copied,
            sourceStart: const Value(0),
            sourceEnd: const Value(16),
            createdAt: at,
            updatedAt: at,
          ),
        );
  }

  /// Deja trabajar a la base —que avanza con el reloj de verdad, no con el de
  /// la prueba— hasta que [done], sin `pumpAndSettle` a ciegas.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200; i++) {
      if (done()) {
        await tester.pumpAndSettle();
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    fail('No llegó a pasar.');
  }

  Future<void> openWith(WidgetTester tester, CreationScope scope) async {
    harness.container.read(repasarScopeProvider.notifier).state = scope;
    await harness.openRepasar(tester, size: const Size(800, 2400));
  }

  Finder held(String name) => find.byKey(ValueKey('scope-holding-$name'));

  String detailOf(WidgetTester tester, String name) => tester
      .widget<Text>(find.byKey(ValueKey('scope-holding-detail-$name')))
      .data!;

  final empty = find.byKey(const Key('repasar-created-empty'));

  group('las tarjetas del recorte', () {
    testWidgets('un documento con tarjetas y sin nada creado: «Tarjetas de '
        'repaso · N tarjetas», y no el vacío', (tester) async {
      await document('p-1', 'Lazarillo', cards: 3);
      await openWith(tester, const CreationScope.document('p-1'));

      expect(held('cards'), findsOneWidget);
      expect(
        find.descendant(
          of: held('cards'),
          matching: find.text(es.f43S17HeldCards),
        ),
        findsOneWidget,
      );
      expect(detailOf(tester, 'cards'), es.f43StudioCards(3));
      expect(empty, findsNothing);
      // Sin nada marcado, ni resumen ni síntesis.
      expect(held('summary'), findsNothing);
      expect(held('synthesis'), findsNothing);
    });

    testWidgets('tocarla abre la sesión de esas tarjetas, solo esas', (
      tester,
    ) async {
      await document('p-1', 'Lazarillo', cards: 3);
      await document('p-2', 'Quijote', cards: 2);
      await openWith(tester, const CreationScope.document('p-1'));

      await tester.tap(held('cards'));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text(es.reviewRemaining(3)), findsOneWidget);
    });

    testWidgets('con una sola tarjeta también está', (tester) async {
      await document('p-1', 'Lazarillo', cards: 1);
      await openWith(tester, const CreationScope.document('p-1'));

      expect(detailOf(tester, 'cards'), es.f43StudioCards(1));
    });
  });

  group('el resumen y la síntesis marcados', () {
    testWidgets('un documento con los dos: «Marcado en el documento», '
        'arriba de lo creado', (tester) async {
      await document('p-1', 'Lazarillo', summary: true, synthesis: true);
      final made = await harness.creation(
        StudyCreationKind.report,
        scope: const CreationScope.document('p-1'),
        sources: ['p-1'],
        title: 'Informe',
      );
      await openWith(tester, const CreationScope.document('p-1'));

      expect(detailOf(tester, 'summary'), es.f43S17HeldMarkedAll(1));
      expect(detailOf(tester, 'synthesis'), es.f43S17HeldMarkedAll(1));
      final tile = find.byKey(ValueKey('creation-tile-${made.id}'));
      expect(
        tester.getTopLeft(held('summary')).dy,
        lessThan(tester.getTopLeft(held('synthesis')).dy),
      );
      expect(
        tester.getTopLeft(held('synthesis')).dy,
        lessThan(tester.getTopLeft(tile).dy),
      );
    });

    testWidgets('«Resumen» la crea sin IA con los documentos que lo tienen '
        'marcado, la abre, y después queda como su fila', (tester) async {
      await document('p-a', 'Lazarillo', summary: true);
      await document('p-b', 'Quijote');
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Picaresca', mode: NotebookMode.manual);
      await harness.container
          .read(notebookRepositoryProvider)
          .addItems(notebookId: notebook.id, itemIds: ['p-a', 'p-b']);
      final scope = CreationScope.notebook(notebook.id);
      await openWith(tester, scope);

      expect(detailOf(tester, 'summary'), es.f43S17HeldMarkedSome(1, 2));
      expect(held('synthesis'), findsNothing);

      await tester.tap(held('summary'));
      await until(
        tester,
        () => find.byType(CreationViewerScreen).evaluate().isNotEmpty,
      );

      final request = harness.queue.requests.single;
      expect(request.kind, StudyCreationKind.summary);
      expect(request.scope, scope);
      expect(request.sourceIds, ['p-a'], reason: 'solo el que está marcado');
      expect(
        request.options,
        harness.container
            .read(creationKindRegistryProvider)
            .of(StudyCreationKind.summary)
            .withDefaults(const {}),
      );
      expect(find.byType(CreationViewerScreen), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();

      // Ya es una creación del cuaderno: no se repite arriba.
      await until(tester, () => held('summary').evaluate().isEmpty);
      final created = (await tester.runAsync(
        () => harness.creations.watchByScope(scope).first,
      ))!;
      expect(created.single.kind, StudyCreationKind.summary);
      expect(
        find.byKey(ValueKey('creation-tile-${created.single.id}')),
        findsOneWidget,
      );
    });

    testWidgets('un resumen creado desde otro recorte no la esconde', (
      tester,
    ) async {
      await document('p-1', 'Lazarillo', summary: true);
      await harness.creation(
        StudyCreationKind.summary,
        scope: const CreationScope.notebook('otro'),
        sources: ['p-1'],
      );
      await openWith(tester, const CreationScope.document('p-1'));

      expect(held('summary'), findsOneWidget);
    });

    testWidgets('«Síntesis» crea la de síntesis', (tester) async {
      await document('p-1', 'Lazarillo', synthesis: true);
      await openWith(tester, const CreationScope.document('p-1'));

      expect(held('summary'), findsNothing);
      await tester.tap(held('synthesis'));
      await until(
        tester,
        () => find.byType(CreationViewerScreen).evaluate().isNotEmpty,
      );

      final request = harness.queue.requests.single;
      expect(request.kind, StudyCreationKind.synthesis);
      expect(request.sourceIds, ['p-1']);
    });
  });

  group('al día, y el vacío solo sin nada de nada', () {
    testWidgets('al marcar el resumen en el original y al sumar una tarjeta, '
        'aparecen solas', (tester) async {
      await document('p-1', 'Lazarillo');
      await openWith(tester, const CreationScope.document('p-1'));

      expect(empty, findsOneWidget);
      expect(find.text(es.f43StudioCreatedEmpty), findsOneWidget);

      await tester.runAsync(() => mark('p-1', ProcessedSection.summary));
      await until(tester, () => held('summary').evaluate().isNotEmpty);
      expect(empty, findsNothing);

      await tester.runAsync(
        () => harness.container
            .read(flashcardRepositoryProvider)
            .create(itemId: 'p-1', front: '¿Quién?', back: 'Lázaro'),
      );
      await until(tester, () => held('cards').evaluate().isNotEmpty);
      expect(detailOf(tester, 'cards'), es.f43StudioCards(1));
    });
  });

  group('el orden de Repasar (M14)', () {
    testWidgets('el selector, las tarjetas de crear, «Lo creado» y, después, '
        '«Para hoy» con «Mis tarjetas»', (tester) async {
      await harness.container
          .read(studyLimitsProvider.notifier)
          .setNewPerDay(1);
      await document('p-1', 'Lazarillo', cards: 2);
      await openWith(tester, const CreationScope.document('p-1'));

      double top(Finder finder) => tester.getTopLeft(finder).dy;
      final pill = find.byKey(const Key('repasar-scope'));
      final grid = find.byKey(
        ValueKey('creation-kind-${StudyCreationKind.fullText.storageKey}'),
      );
      final createdHeader = find.text(es.f43StudioCreatedTitle);
      final today = find.byKey(const Key('review-entry-today'));

      expect(top(pill), lessThan(top(grid)));
      expect(top(grid), lessThan(top(createdHeader)));
      expect(top(createdHeader), lessThan(top(held('cards'))));
      expect(top(held('cards')), lessThan(top(today)));
      expect(
        find.descendant(
          of: today,
          matching: find.byKey(const Key('review-entry-cards')),
        ),
        findsOneWidget,
      );
      // «N nuevas más esperan…» sigue en la franja, con «Empezar».
      expect(
        find.descendant(
          of: today,
          matching: find.text(es.reviewEntryNewBeyond(1)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: today,
          matching: find.byKey(const Key('review-entry-start')),
        ),
        findsOneWidget,
      );
    });
  });
}
