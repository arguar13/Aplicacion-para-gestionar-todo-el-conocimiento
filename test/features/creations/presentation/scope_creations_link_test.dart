import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/screens/creation_viewer_screen.dart';
import 'package:sinapsis/features/creations/presentation/widgets/scope_creations_section.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_entry_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebook_detail_screen.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import 'repasar_harness.dart';

/// Procesado y Cuadernos conectados con Repasar, en los dos sentidos (F43,
/// paso 16, M6): «En Repasar» en cada documento procesado —lo creado sobre él
/// y lo que lo usó como fuente, sus tarjetas para hoy y «Crear en Repasar»— y
/// en cada cuaderno; tocar una creación abre su visor y «atrás» vuelve adonde
/// se estaba; y de una creación, sus fuentes como chips que abren su pantalla.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;

  const doc = CreationScope.document('p-1');

  setUp(() async {
    harness = await RepasarHarness.create();
    await harness.processed('p-1', 'Éxodo — Comentario');
    await harness.processed('p-2', 'Génesis');
  });

  Finder sectionOf(CreationScope scope) =>
      find.byKey(ValueKey('scope-creations-${scope.storageKey}'));

  Finder tileOf(StudyCreation creation) =>
      find.byKey(ValueKey('creation-tile-${creation.id}'));

  Finder inSection(CreationScope scope, Finder finder) =>
      find.descendant(of: sectionOf(scope), matching: finder);

  /// La lista que desplaza la pantalla de arriba: la del documento o la del
  /// cuaderno.
  Finder scrollableOf(Type screen) => find
      .descendant(of: find.byType(screen), matching: find.byType(Scrollable))
      .first;

  Future<void> reveal(WidgetTester tester, Finder finder, Type screen) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: scrollableOf(screen),
    );
    await tester.pumpAndSettle();
  }

  /// Abre el documento procesado [id] encima de Procesado, como se llega
  /// tocándolo en la lista, y baja hasta «En Repasar».
  Future<void> openDocument(
    WidgetTester tester, {
    String id = 'p-1',
    Size size = const Size(420, 1600),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) async {
    await harness.openRepasar(
      tester,
      location: '/processed',
      size: size,
      theme: theme,
      textScale: textScale,
    );
    harness.library.pushTo('/processed/$id');
    await tester.pumpAndSettle();
    expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
    await reveal(
      tester,
      sectionOf(CreationScope.document(id)),
      ProcessedDocumentScreen,
    );
  }

  /// «Atrás», como el botón o el gesto del sistema: lo que decide el router.
  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<Notebook> notebookWith(List<String> itemIds) async {
    final notebooks = harness.container.read(notebookRepositoryProvider);
    final notebook = await notebooks.create(
      name: 'Pentateuco',
      mode: NotebookMode.manual,
    );
    if (itemIds.isNotEmpty) {
      await notebooks.addItems(notebookId: notebook.id, itemIds: itemIds);
    }
    return notebook;
  }

  Future<void> openNotebook(
    WidgetTester tester,
    Notebook notebook, {
    Size size = const Size(420, 1600),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) async {
    await harness.openRepasar(
      tester,
      location: '/notebooks/${notebook.id}',
      size: size,
      theme: theme,
      textScale: textScale,
    );
    expect(find.byType(NotebookDetailScreen), findsOneWidget);
  }

  group('«En Repasar» en un documento procesado', () {
    testWidgets('lo creado sobre él y lo que lo usó como fuente desde un '
        'cuaderno o un tema; nada de otros', (tester) async {
      final own = await harness.creation(
        StudyCreationKind.presentation,
        scope: doc,
        sources: ['p-1'],
        title: 'Sobre el Éxodo',
      );
      final notebook = await notebookWith(['p-1', 'p-2']);
      final viaNotebook = await harness.creation(
        StudyCreationKind.quiz,
        scope: CreationScope.notebook(notebook.id),
        sources: ['p-2', 'p-1'],
        title: 'Del cuaderno',
      );
      final viaTopic = await harness.creation(
        StudyCreationKind.infographic,
        scope: const CreationScope.topic('ley'),
        sources: ['p-1'],
        title: 'Del tema',
      );
      final other = await harness.creation(
        StudyCreationKind.summary,
        scope: CreationScope.notebook(notebook.id),
        sources: ['p-2'],
        title: 'Solo de Génesis',
      );
      await openDocument(tester);

      for (final c in [own, viaNotebook, viaTopic]) {
        expect(inSection(doc, tileOf(c)), findsOneWidget, reason: c.title);
      }
      expect(tileOf(other), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.byKey(ValueKey('scope-creations-count-${doc.storageKey}')),
            )
            .data,
        es.f43LinkCreatedCount(3),
      );
      // Con su «Crear en Repasar» arriba y sin el vacío.
      expect(
        inSection(
          doc,
          find.byKey(ValueKey('scope-creations-create-${doc.storageKey}')),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('scope-creations-empty-${doc.storageKey}')),
        findsNothing,
      );
    });

    testWidgets('se actualiza sola: aparece lo nuevo, con su avance, y se va '
        'lo que se manda a la papelera', (tester) async {
      await openDocument(tester);
      expect(
        find.byKey(ValueKey('scope-creations-empty-${doc.storageKey}')),
        findsOneWidget,
      );

      final generating = await harness.creation(
        StudyCreationKind.mindMap,
        scope: const CreationScope.notebook('n'),
        sources: ['p-1'],
        status: CreationStatus.generating,
        progress: 0.4,
      );
      await tester.pump();
      await tester.pump();
      expect(inSection(doc, tileOf(generating)), findsOneWidget);
      expect(
        find.byKey(ValueKey('scope-creations-empty-${doc.storageKey}')),
        findsNothing,
      );

      await harness.creations.trash(generating.id);
      await tester.pump();
      await tester.pump();
      expect(tileOf(generating), findsNothing);
      expect(
        find.byKey(ValueKey('scope-creations-empty-${doc.storageKey}')),
        findsOneWidget,
      );
    });

    testWidgets('tocar una creación abre su visor, y «atrás» vuelve al '
        'documento, no a Repasar', (tester) async {
      final own = await harness.creation(
        StudyCreationKind.report,
        scope: doc,
        sources: ['p-1'],
        title: 'Informe del Éxodo',
      );
      await openDocument(tester);

      await tester.tap(inSection(doc, find.text('Informe del Éxodo')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('creation-viewer-${own.id}')), findsOneWidget);

      await back(tester);
      expect(find.byType(CreationViewerScreen), findsNothing);
      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
      expect(find.byType(ReviewEntryScreen), findsNothing);
      expect(sectionOf(doc), findsOneWidget);
    });

    testWidgets('sus tarjetas para hoy: cuántas y «Empezar», que abre la '
        'sesión del documento; «atrás» vuelve al documento', (tester) async {
      await harness.processed('p-3', 'Levítico', cards: 3);
      await openDocument(tester, id: 'p-3');
      const scope = CreationScope.document('p-3');

      expect(
        tester
            .widget<Text>(
              find.byKey(ValueKey('scope-today-${scope.storageKey}')),
            )
            .data,
        es.f43LinkTodayCards(3),
      );
      await tester.tap(
        find.byKey(ValueKey('scope-today-start-${scope.storageKey}')),
      );
      await tester.pumpAndSettle();

      final session = tester.widget<ReviewScreen>(find.byType(ReviewScreen));
      expect(session.scope, const StudyScope.processed('document:p-3'));
      expect(session.scope, scope.studyScope);

      await back(tester);
      expect(find.byType(ReviewScreen), findsNothing);
      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
    });

    testWidgets('sin tarjetas para hoy, ni la franja', (tester) async {
      await openDocument(tester);
      expect(
        find.byKey(ValueKey('scope-today-${doc.storageKey}')),
        findsNothing,
      );
    });

    testWidgets('vacía, invita a crear con los íconos de lo que se puede '
        'hacer; «Crear en Repasar» abre Repasar con el documento elegido', (
      tester,
    ) async {
      await openDocument(tester);

      final empty = find.byKey(
        ValueKey('scope-creations-empty-${doc.storageKey}'),
      );
      expect(empty, findsOneWidget);
      expect(
        find.descendant(
          of: empty,
          matching: find.text(es.f43LinkEmptyDocumentTitle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: empty,
          matching: find.text(es.f43LinkEmptyDocument),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(ValueKey('scope-creations-create-${doc.storageKey}')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReviewEntryScreen), findsOneWidget);
      expect(harness.scope, doc);
      expect(
        tester.widget<Text>(find.byKey(const Key('repasar-scope-name'))).data,
        'Éxodo — Comentario',
      );
    });

    testWidgets('con muchas, las cinco más nuevas y «Ver las N en Repasar», '
        'que abre Repasar con el documento elegido, con todas', (tester) async {
      final made = <StudyCreation>[
        for (var i = 0; i < kScopeCreationsShown + 2; i++)
          await harness.creation(
            StudyCreationKind.quiz,
            scope: doc,
            sources: ['p-1'],
            title: 'Cuestionario $i',
          ),
      ];
      await openDocument(tester);

      final tiles = find.descendant(
        of: sectionOf(doc),
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('creation-tile-'),
        ),
      );
      expect(tiles, findsNWidgets(kScopeCreationsShown));

      final all = find.byKey(ValueKey('scope-creations-all-${doc.storageKey}'));
      await reveal(tester, all, ProcessedDocumentScreen);
      expect(
        find.descendant(
          of: all,
          matching: find.text(es.f43LinkSeeAll(made.length)),
        ),
        findsOneWidget,
      );
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(find.byType(ReviewEntryScreen), findsOneWidget);
      expect(harness.scope, doc);
      // En Repasar están todas.
      for (final c in made) {
        await tester.scrollUntilVisible(
          tileOf(c),
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('review-entry')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tileOf(c), findsOneWidget, reason: c.title);
      }
    });

    testWidgets('en la papelera no se estudia: ni la sección', (tester) async {
      await harness.creation(
        StudyCreationKind.report,
        scope: doc,
        sources: ['p-1'],
      );
      await harness.container.read(libraryRepositoryProvider).deleteMany([
        'p-1',
      ]);
      await harness.openRepasar(tester, location: '/processed');
      harness.library.pushTo('/processed/p-1');
      await tester.pumpAndSettle();

      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
      expect(sectionOf(doc), findsNothing);
    });
  });

  group('«En Repasar» en un cuaderno', () {
    testWidgets('lo creado con el cuaderno como recorte, arriba de sus '
        'documentos; lo de un documento suyo queda en el documento', (
      tester,
    ) async {
      final notebook = await notebookWith(['p-1', 'p-2']);
      final scope = CreationScope.notebook(notebook.id);
      final onNotebook = await harness.creation(
        StudyCreationKind.presentation,
        scope: scope,
        sources: ['p-1', 'p-2'],
        title: 'Del Pentateuco',
      );
      final onDocument = await harness.creation(
        StudyCreationKind.quiz,
        scope: doc,
        sources: ['p-1'],
        title: 'Solo del Éxodo',
      );
      await openNotebook(tester, notebook);

      expect(inSection(scope, tileOf(onNotebook)), findsOneWidget);
      expect(tileOf(onDocument), findsNothing);
      // Arriba de los documentos.
      expect(
        tester.getBottomLeft(sectionOf(scope)).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('notebook-item-p-1'))).dy,
        ),
      );
    });

    testWidgets('«Crear en Repasar» abre Repasar con el cuaderno elegido', (
      tester,
    ) async {
      final notebook = await notebookWith(['p-1']);
      final scope = CreationScope.notebook(notebook.id);
      await openNotebook(tester, notebook);

      expect(
        find.descendant(
          of: find.byKey(ValueKey('scope-creations-empty-${scope.storageKey}')),
          matching: find.text(es.f43LinkEmptyNotebookTitle),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(ValueKey('scope-creations-create-${scope.storageKey}')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReviewEntryScreen), findsOneWidget);
      expect(harness.scope, scope);
      expect(
        tester.widget<Text>(find.byKey(const Key('repasar-scope-name'))).data,
        'Pentateuco',
      );
    });

    testWidgets('sus tarjetas para hoy, las de todos sus documentos, con '
        '«Empezar» a la sesión del cuaderno', (tester) async {
      await harness.processed('p-3', 'Levítico', cards: 2);
      await harness.processed('p-4', 'Números', cards: 1);
      final notebook = await notebookWith(['p-3', 'p-4']);
      final scope = CreationScope.notebook(notebook.id);
      await openNotebook(tester, notebook);

      expect(
        tester
            .widget<Text>(
              find.byKey(ValueKey('scope-today-${scope.storageKey}')),
            )
            .data,
        es.f43LinkTodayCards(3),
      );
      await tester.tap(
        find.byKey(ValueKey('scope-today-start-${scope.storageKey}')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReviewScreen>(find.byType(ReviewScreen)).scope,
        scope.studyScope,
      );

      await back(tester);
      expect(find.byType(NotebookDetailScreen), findsOneWidget);
    });

    testWidgets('tocar una creación abre su visor y «atrás» vuelve al '
        'cuaderno', (tester) async {
      final notebook = await notebookWith(['p-1']);
      final scope = CreationScope.notebook(notebook.id);
      final made = await harness.creation(
        StudyCreationKind.report,
        scope: scope,
        sources: ['p-1'],
        title: 'Informe del cuaderno',
      );
      await openNotebook(tester, notebook);

      await tester.tap(inSection(scope, find.text('Informe del cuaderno')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('creation-viewer-${made.id}')),
        findsOneWidget,
      );

      await back(tester);
      expect(find.byType(NotebookDetailScreen), findsOneWidget);
      expect(sectionOf(scope), findsOneWidget);
    });

    testWidgets('vacío y sin nada creado, solo el vacío del cuaderno; con algo '
        'creado, la sección no lo esconde', (tester) async {
      final notebook = await notebookWith(const []);
      final scope = CreationScope.notebook(notebook.id);
      await openNotebook(tester, notebook);
      expect(sectionOf(scope), findsNothing);
      expect(find.byKey(const Key('notebook-detail-empty')), findsOneWidget);

      final made = await harness.creation(
        StudyCreationKind.mindMap,
        scope: scope,
        sources: ['p-1'],
      );
      await tester.pump();
      await tester.pump();
      expect(inSection(scope, tileOf(made)), findsOneWidget);
      expect(find.byKey(const Key('notebook-detail-empty')), findsOneWidget);
    });
  });

  group('de Repasar a Procesado y Cuadernos: las fuentes como chips', () {
    testWidgets('en el visor, el documento abre su pantalla y «atrás» vuelve '
        'al visor', (tester) async {
      final made = await harness.creation(
        StudyCreationKind.report,
        sources: ['p-2'],
      );
      await harness.openRepasar(tester);
      harness.library.pushTo('/creations/${made.id}');
      await tester.pumpAndSettle();

      final chip = find.byKey(const ValueKey('creation-source-p-2'));
      expect(
        find.descendant(of: chip, matching: find.text('Génesis')),
        findsOneWidget,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);

      await back(tester);
      expect(
        find.byKey(ValueKey('creation-viewer-${made.id}')),
        findsOneWidget,
      );
    });

    testWidgets('en el visor, el cuaderno sobre el que se creó abre el '
        'cuaderno', (tester) async {
      final notebook = await notebookWith(['p-1']);
      final scope = CreationScope.notebook(notebook.id);
      final made = await harness.creation(
        StudyCreationKind.mindMap,
        scope: scope,
        sources: ['p-1'],
      );
      await harness.openRepasar(tester);
      harness.library.pushTo('/creations/${made.id}');
      await tester.pumpAndSettle();

      final chip = find.byKey(
        ValueKey('creation-scope-chip-${scope.storageKey}'),
      );
      expect(
        find.descendant(of: chip, matching: find.text('Pentateuco')),
        findsOneWidget,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byType(NotebookDetailScreen), findsOneWidget);
    });

    testWidgets('un cuaderno o un documento que se borró dice «Fuente '
        'borrada», en el visor y en «Ver petición y fuentes», y no abre nada', (
      tester,
    ) async {
      final notebook = await notebookWith(['p-1']);
      final scope = CreationScope.notebook(notebook.id);
      final made = await harness.creation(
        StudyCreationKind.mindMap,
        scope: scope,
        sources: ['p-1', 'ya-no-esta'],
      );
      await harness.container
          .read(notebookRepositoryProvider)
          .delete(notebook.id);
      await harness.openRepasar(tester);

      // En «Lo creado», mantener apretada la fila: «Ver petición y fuentes».
      await tester.ensureVisible(tileOf(made));
      await tester.pumpAndSettle();
      await tester.longPress(tileOf(made));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('creation-action-details')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('creation-details-sheet'));
      for (final key in [
        'creation-scope-chip-${scope.storageKey}',
        'creation-source-ya-no-esta',
      ]) {
        expect(
          find.descendant(
            of: find.descendant(of: sheet, matching: find.byKey(ValueKey(key))),
            matching: find.text(es.f43StudioSourceDeleted),
          ),
          findsOneWidget,
          reason: key,
        );
      }
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // En el visor, lo mismo, y tocarlo no lleva a ninguna parte.
      harness.library.pushTo('/creations/${made.id}');
      await tester.pumpAndSettle();
      final gone = find.byKey(
        ValueKey('creation-scope-chip-${scope.storageKey}'),
      );
      expect(
        find.descendant(
          of: gone,
          matching: find.text(es.f43StudioSourceDeleted),
        ),
        findsOneWidget,
      );
      await tester.tap(gone);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('creation-viewer-${made.id}')),
        findsOneWidget,
      );
      expect(find.byType(NotebookDetailScreen), findsNothing);
    });

    testWidgets('las direcciones directas siguen andando: el documento, el '
        'visor y Repasar con un recorte', (tester) async {
      final made = await harness.creation(
        StudyCreationKind.report,
        scope: doc,
        sources: ['p-1'],
      );
      await harness.openRepasar(tester, location: '/processed/p-1');
      expect(find.byType(ProcessedDocumentScreen), findsOneWidget);

      harness.library.goTo('/creations/${made.id}');
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('creation-viewer-${made.id}')),
        findsOneWidget,
      );

      harness.library.goTo('/review?scope=${doc.storageKey}');
      await tester.pumpAndSettle();
      expect(find.byType(ReviewEntryScreen), findsOneWidget);
      expect(harness.scope, doc);
    });
  });

  group('en un teléfono de 360 dp con la letra al doble', () {
    Future<void> seed() async {
      await harness.processed(
        'p-9',
        'Declaración de los Derechos del Hombre y del Ciudadano, comentada',
        cards: 2,
      );
      await harness.creation(
        StudyCreationKind.presentation,
        scope: const CreationScope.document('p-9'),
        sources: ['p-9'],
        title: 'Análisis exegético de la Declaración: libertad e igualdad',
      );
      await harness.creation(
        StudyCreationKind.quiz,
        scope: const CreationScope.document('p-9'),
        sources: ['p-9'],
        status: CreationStatus.generating,
        progress: 0.3,
      );
      await harness.creation(
        StudyCreationKind.infographic,
        scope: const CreationScope.document('p-9'),
        sources: ['p-9'],
        status: CreationStatus.failed,
        failure: CreationFailure.error,
      );
    }

    for (final theme in AppThemeChoice.values) {
      testWidgets('tema ${theme.name}: el documento y el cuaderno, llenos y '
          'vacíos, sin desbordes', (tester) async {
        await seed();
        final notebook = await notebookWith(['p-9']);
        const size = Size(360, 800);

        await openDocument(
          tester,
          id: 'p-9',
          size: size,
          theme: theme,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        await reveal(
          tester,
          find.byKey(const ValueKey('scope-today-start-document:p-9')),
          ProcessedDocumentScreen,
        );
        expect(tester.takeException(), isNull);

        // Un documento vacío de lo creado.
        await openDocument(
          tester,
          id: 'p-2',
          size: size,
          theme: theme,
          textScale: 2,
        );
        await reveal(
          tester,
          find.byKey(const ValueKey('scope-creations-create-document:p-2')),
          ProcessedDocumentScreen,
        );
        expect(tester.takeException(), isNull);

        await openNotebook(
          tester,
          notebook,
          size: size,
          theme: theme,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(sectionOf(CreationScope.notebook(notebook.id)), findsOneWidget);
      });
    }
  });
}
