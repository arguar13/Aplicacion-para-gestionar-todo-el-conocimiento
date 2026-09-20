import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La vista de lectura para destilar: el texto de una fuente, la barra de
/// extracción, la cuenta de notas y el salto al fragmento.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  var counter = 0;

  final now = DateTime(2026, 9, 18, 10);

  /// Sesenta párrafos: más que una pantalla, para poder comprobar el
  /// desplazamiento.
  String paragraph(int i) =>
      'Párrafo número $i: el imperio romano de occidente cayó en el año 476 y '
      'con él terminó una era.';
  final essay = [for (var i = 0; i < 60; i++) paragraph(i)].join('\n\n');

  setUp(() async {
    harness = await LibraryHarness.create();
    counter = 0;
  });

  Future<String> seedSource({
    String title = 'Un ensayo',
    String? text,
    bool withText = true,
  }) async {
    final n = counter++;
    final id = 'src-item-$n';
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: title,
            source: Source(
              id: 'src-$n',
              kind: SourceKind.webPage,
              capturedAt: now,
              url: 'https://ejemplo.org/$n',
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              if (withText)
                Rendition.text(
                  id: 'rend-$n',
                  itemId: id,
                  kind: RenditionKind.plainText,
                  content: text ?? essay,
                  isPrimary: true,
                  createdAt: now,
                ),
            ],
          ),
        );
    return id;
  }

  /// Una nota ya extraída de [sourceId], por el camino de la app.
  Future<String> seedExtraction(
    String sourceId, {
    String title = 'Una nota atómica',
    int? start,
    int? end,
  }) async {
    final n = counter++;
    final id = 'note-item-$n';
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: title,
            source: Source(
              id: 'note-src-$n',
              kind: SourceKind.manualNote,
              capturedAt: now,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'note-rend-$n',
                itemId: id,
                kind: RenditionKind.plainText,
                content: 'Lo extraído.',
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
    await harness.container
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: id,
          toItemId: sourceId,
          kind: RelationKind.extractedFrom,
          sourceCharStart: start,
          sourceCharEnd: end,
        );
    return id;
  }

  GoRouter router(String itemId, {({int start, int end})? jump}) => GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => ReadingScreen(itemId: itemId, jump: jump),
      ),
      GoRoute(
        path: RoutePaths.itemDetailPattern,
        builder: (_, state) =>
            Scaffold(body: Text('detalle de ${state.pathParameters['id']}')),
      ),
    ],
  );

  Future<void> pumpReading(
    WidgetTester tester,
    String itemId, {
    ({int start, int end})? jump,
  }) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router(itemId, jump: jump),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Selecciona `[start, end)` del texto, como lo haría el usuario.
  Future<void> select(WidgetTester tester, int start, int end) async {
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: TextSelection(baseOffset: start, extentOffset: end),
      ),
      SelectionChangedCause.tap,
    );
    await tester.pumpAndSettle();
  }

  double scrollOffset(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;

  group('el texto y la barra', () {
    testWidgets('muestra el texto de la fuente y su título', (tester) async {
      final id = await seedSource(title: 'Caída de Roma');
      await pumpReading(tester, id);

      expect(find.text('Caída de Roma'), findsOneWidget);
      expect(find.textContaining('Párrafo número 0'), findsWidgets);
    });

    testWidgets('sin nada extraído dice que no hay notas', (tester) async {
      final id = await seedSource();
      await pumpReading(tester, id);

      expect(find.text(es.readingExtractedCount(0)), findsOneWidget);
      expect(find.text(es.readingExtractedTitle), findsNothing);
    });

    testWidgets('sin selección dice cómo empezar y no ofrece extraer', (
      tester,
    ) async {
      final id = await seedSource();
      await pumpReading(tester, id);

      expect(find.text(es.readingSelectHint), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, es.detailExtractSelection),
        findsNothing,
      );
    });

    testWidgets('al seleccionar, "Extraer como nota" es la acción principal', (
      tester,
    ) async {
      final id = await seedSource();
      await pumpReading(tester, id);

      await select(tester, 0, 20);

      expect(find.text(es.readingSelectHint), findsNothing);
      expect(
        find.widgetWithText(FilledButton, es.detailExtractSelection),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, es.detailHighlightSelection),
        findsOneWidget,
      );
    });

    testWidgets('al soltar la selección la barra vuelve a la ayuda', (
      tester,
    ) async {
      final id = await seedSource();
      await pumpReading(tester, id);
      await select(tester, 0, 20);

      await select(tester, 5, 5);

      expect(find.text(es.readingSelectHint), findsOneWidget);
    });
  });

  group('extraer', () {
    testWidgets('crea la nota, la vincula con el rango exacto y actualiza la '
        'cuenta y la lista', (tester) async {
      final id = await seedSource();
      await pumpReading(tester, id);
      await select(tester, 0, 20);

      await tester.tap(
        find.widgetWithText(FilledButton, es.detailExtractSelection),
      );
      await tester.pumpAndSettle();

      // De dónde salió, guardado: los primeros veinte caracteres.
      final relation = await harness.database
          .select(harness.database.relations)
          .getSingle();
      expect(relation.kind, RelationKind.extractedFrom);
      expect(relation.toItemId, id);
      expect(relation.sourceCharStart, 0);
      expect(relation.sourceCharEnd, 20);

      // Y a la vista: la cuenta, la lista y el fragmento.
      expect(find.text(es.readingExtractedCount(1)), findsOneWidget);
      expect(find.text(es.readingExtractedTitle), findsOneWidget);
      expect(find.text('Párrafo número 0: el'), findsWidgets);
    });

    testWidgets('la nota que sale es atómica', (tester) async {
      final id = await seedSource();
      await pumpReading(tester, id);
      await select(tester, 0, 20);

      await tester.tap(
        find.widgetWithText(FilledButton, es.detailExtractSelection),
      );
      await tester.pumpAndSettle();

      final relation = await harness.database
          .select(harness.database.relations)
          .getSingle();
      final note = await (harness.database.select(
        harness.database.knowledgeNotes,
      )..where((n) => n.itemId.equals(relation.fromItemId))).getSingle();
      expect(note.noteKind, NoteKind.atomic);
    });

    testWidgets('se pueden extraer varias, y la cuenta sube con cada una', (
      tester,
    ) async {
      final id = await seedSource();
      await pumpReading(tester, id);

      for (final (start, end) in [(0, 20), (100, 130)]) {
        await select(tester, start, end);
        await tester.tap(
          find.widgetWithText(FilledButton, es.detailExtractSelection),
        );
        await tester.pumpAndSettle();
      }

      expect(find.text(es.readingExtractedCount(2)), findsOneWidget);
    });

    testWidgets('Resaltar desde la barra pide la nota del resaltado', (
      tester,
    ) async {
      final id = await seedSource();
      await pumpReading(tester, id);
      await select(tester, 0, 20);

      await tester.tap(
        find.widgetWithText(OutlinedButton, es.detailHighlightSelection),
      );
      await tester.pumpAndSettle();

      expect(find.text(es.detailHighlightNoteDialogTitle), findsOneWidget);
    });
  });

  group('la cuenta', () {
    testWidgets('cuenta las notas extraídas de esta fuente', (tester) async {
      final id = await seedSource();
      await seedExtraction(id, title: 'Una', start: 0, end: 20);
      await seedExtraction(id, title: 'Otra', start: 100, end: 130);
      await pumpReading(tester, id);

      expect(find.text(es.readingExtractedCount(2)), findsOneWidget);
      expect(find.text('Una'), findsOneWidget);
      expect(find.text('Otra'), findsOneWidget);
    });

    testWidgets('no cuenta las extraídas de otra fuente', (tester) async {
      final id = await seedSource(title: 'Esta');
      final other = await seedSource(title: 'Otra fuente');
      await seedExtraction(other, title: 'De la otra', start: 0, end: 20);
      await pumpReading(tester, id);

      expect(find.text(es.readingExtractedCount(0)), findsOneWidget);
      expect(find.text('De la otra'), findsNothing);
    });

    testWidgets('no cuenta los vínculos que no son extracciones', (
      tester,
    ) async {
      final id = await seedSource();
      final note = await seedExtraction(id, start: 0, end: 20);
      final citing = await seedSource(title: 'Cita', withText: false);
      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: citing,
            toItemId: id,
            kind: RelationKind.cites,
          );
      await pumpReading(tester, id);

      expect(find.text(es.readingExtractedCount(1)), findsOneWidget);
      expect(note, isNotEmpty);
    });

    testWidgets('tocar una nota abre su detalle', (tester) async {
      final id = await seedSource();
      final note = await seedExtraction(
        id,
        title: 'Mi nota',
        start: 0,
        end: 20,
      );
      await pumpReading(tester, id);
      await tester.ensureVisible(find.text('Mi nota'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mi nota'));
      await tester.pumpAndSettle();

      expect(find.text('detalle de $note'), findsOneWidget);
    });
  });

  group('saltar al fragmento', () {
    // Un fragmento en el último tercio del texto, muy por debajo de la primera
    // pantalla.
    final start = essay.length - 300;
    final end = start + 40;

    testWidgets('sin fragmento, la vista empieza arriba', (tester) async {
      final id = await seedSource();
      await pumpReading(tester, id);

      expect(scrollOffset(tester), 0);
    });

    testWidgets('abrir con un fragmento baja la vista hasta él', (
      tester,
    ) async {
      final id = await seedSource();
      await pumpReading(tester, id, jump: (start: start, end: end));

      expect(scrollOffset(tester), greaterThan(500));
    });

    testWidgets('un fragmento más cerca del principio baja menos', (
      tester,
    ) async {
      final id = await seedSource();
      await pumpReading(
        tester,
        id,
        jump: (start: essay.length ~/ 2, end: essay.length ~/ 2 + 40),
      );
      final middle = scrollOffset(tester);

      await pumpReading(tester, id, jump: (start: start, end: end));

      expect(scrollOffset(tester), greaterThan(middle));
    });

    testWidgets('un fragmento que no entra en el texto se ignora', (
      tester,
    ) async {
      final id = await seedSource();

      await pumpReading(
        tester,
        id,
        jump: (start: essay.length + 10, end: essay.length + 50),
      );

      expect(scrollOffset(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un fragmento invertido se ignora', (tester) async {
      final id = await seedSource();

      await pumpReading(tester, id, jump: (start: 500, end: 400));

      expect(scrollOffset(tester), 0);
    });

    testWidgets('el botón de una nota lleva al fragmento del que salió', (
      tester,
    ) async {
      final id = await seedSource();
      final middle = essay.length ~/ 2;
      await seedExtraction(
        id,
        title: 'Del medio',
        start: middle,
        end: middle + 40,
      );
      await pumpReading(tester, id);
      await tester.ensureVisible(find.byTooltip(es.readingGoToFragment));
      await tester.pumpAndSettle();
      final beforeJump = scrollOffset(tester);

      await tester.tap(find.byTooltip(es.readingGoToFragment));
      await tester.pumpAndSettle();

      // La lista queda debajo de todo el texto: ir al fragmento sube.
      expect(scrollOffset(tester), lessThan(beforeJump));
    });

    testWidgets('una nota sin posición guardada se lista sin botón', (
      tester,
    ) async {
      final id = await seedSource();
      await seedExtraction(id, title: 'Vieja');
      await pumpReading(tester, id);

      expect(find.text('Vieja'), findsOneWidget);
      expect(find.byTooltip(es.readingGoToFragment), findsNothing);
    });

    testWidgets('una posición que ya no entra en el texto se lista sin '
        'botón', (tester) async {
      final id = await seedSource(text: 'Un texto corto.');
      await seedExtraction(id, title: 'Corrida', start: 500, end: 600);
      await pumpReading(tester, id);

      expect(find.text('Corrida'), findsOneWidget);
      expect(find.byTooltip(es.readingGoToFragment), findsNothing);
    });

    testWidgets('con el router real, la ruta abre en el fragmento', (
      tester,
    ) async {
      final id = await seedSource();
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      harness.goTo(RoutePaths.reading(id, start: start, end: end));
      await tester.pumpAndSettle();

      expect(find.byType(ReadingScreen), findsOneWidget);
      expect(scrollOffset(tester), greaterThan(500));
    });
  });

  group('sin texto', () {
    testWidgets('lo dice y ofrece el detalle', (tester) async {
      final id = await seedSource(withText: false);
      await pumpReading(tester, id);

      expect(find.text(es.readingNoText), findsOneWidget);
      await tester.tap(find.text(es.readingOpenDetail));
      await tester.pumpAndSettle();

      expect(find.text('detalle de $id'), findsOneWidget);
    });

    testWidgets('no ofrece extraer ni pide seleccionar', (tester) async {
      final id = await seedSource(withText: false);
      await pumpReading(tester, id);

      expect(find.text(es.readingSelectHint), findsNothing);
    });
  });

  group('crear una tarjeta con la selección (F11)', () {
    Future<List<FlashcardRow>> cards() =>
        harness.database.select(harness.database.flashcards).get();

    testWidgets('con un fragmento seleccionado ofrece crear la tarjeta; sin '
        'selección no', (tester) async {
      final id = await seedSource();
      await pumpReading(tester, id);

      expect(find.byTooltip(es.flashcardsFromSelection), findsNothing);

      await select(tester, 0, 20);

      expect(find.byTooltip(es.flashcardsFromSelection), findsOneWidget);
    });

    testWidgets('el diálogo trae el fragmento como respuesta: solo falta la '
        'pregunta', (tester) async {
      final id = await seedSource();
      await pumpReading(tester, id);
      await select(tester, 0, 20);

      await tester.tap(find.byTooltip(es.flashcardsFromSelection));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextField, essay.substring(0, 20)),
        findsOneWidget,
      );
    });

    testWidgets('guardar crea la tarjeta con la respuesta y el rango exacto '
        'del fragmento', (tester) async {
      final id = await seedSource();
      await pumpReading(tester, id);
      await select(tester, 0, 20);
      await tester.tap(find.byTooltip(es.flashcardsFromSelection));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '¿Qué cayó en 476?');
      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      final card = (await cards()).single;
      expect(card.itemId, id);
      expect(card.front, '¿Qué cayó en 476?');
      expect(card.back, essay.substring(0, 20));
      expect(card.sourceCharStart, 0);
      expect(card.sourceCharEnd, 20);
      expect(find.text(es.flashcardsCreatedFromSelection), findsOneWidget);
    });

    testWidgets('el rango es el del fragmento seleccionado, no el del '
        'principio', (tester) async {
      final id = await seedSource();
      await pumpReading(tester, id);
      final start = essay.indexOf('Párrafo número 3:');
      await select(tester, start, start + 25);

      await tester.tap(find.byTooltip(es.flashcardsFromSelection));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '¿Cuál?');
      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      final card = (await cards()).single;
      expect(card.sourceCharStart, start);
      expect(card.sourceCharEnd, start + 25);
      expect(
        essay.substring(card.sourceCharStart!, card.sourceCharEnd),
        card.back,
      );
    });

    testWidgets('cancelar no crea nada', (tester) async {
      final id = await seedSource();
      await pumpReading(tester, id);
      await select(tester, 0, 20);
      await tester.tap(find.byTooltip(es.flashcardsFromSelection));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await cards(), isEmpty);
    });

    testWidgets('una pregunta en blanco no crea la tarjeta y lo avisa', (
      tester,
    ) async {
      final id = await seedSource();
      await pumpReading(tester, id);
      await select(tester, 0, 20);
      await tester.tap(find.byTooltip(es.flashcardsFromSelection));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      expect(await cards(), isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(es.flashcardsCreatedFromSelection), findsNothing);
    });
  });

  test('las rutas se arman con el fragmento', () {
    expect(RoutePaths.reading('abc'), '/reading/abc');
    expect(
      RoutePaths.reading('abc', start: 3, end: 9),
      '/reading/abc?start=3&end=9',
    );
    // Uno solo no es un rango.
    expect(RoutePaths.reading('abc', start: 3), '/reading/abc');
  });
}
