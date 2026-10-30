import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/source_text_button.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';
import '../processed_ui_fixture.dart';

/// «El texto de la fuente» (F45, paso 3): lo que estaba en el «Más» de una
/// fuente en la Biblioteca —volver a extraer el texto, quitarle las marcas de
/// tiempo, soltar el texto de un libro— se hace desde su documento procesado,
/// con la misma hoja y lo mismo al tocarlo, sobre la fuente.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  const transcript = '[0:00] hola\n[0:05] chau';

  setUp(() async => harness = await LibraryHarness.create());

  final button = find.byKey(const Key('processed-source-text'));
  final sheet = find.byType(BottomSheet);

  Finder option(String name) => find.byKey(Key('source-more-$name'));

  /// Guarda la fuente [id], procesa su texto y abre su documento.
  Future<void> open(
    WidgetTester tester,
    String id, {
    required SourceKind kind,
    String text = 'Roma, un libro.',
    String? originalName,
  }) async {
    await harness.saveTextSource(
      id,
      kind: kind,
      text: text,
      originalName: originalName,
    );
    final documentId = await harness.processTextAndNotes(id);
    await pumpApp(tester, harness);
    await pushAndSettle(
      tester,
      harness,
      RoutePaths.processedDocument(documentId),
    );
    expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
  }

  Future<List<TextRendition>> sourceTexts(String id) async =>
      (await harness.container.read(libraryRepositoryProvider).findById(id))
          .getRight()
          .toNullable()!
          .renditions
          .whereType<TextRendition>()
          .toList();

  group('dónde está', () {
    testWidgets('en la tarjeta de la fuente, al lado de «Volver a triar»', (
      tester,
    ) async {
      await open(
        tester,
        'clase',
        kind: SourceKind.audio,
        text: transcript,
        originalName: 'clase.m4a',
      );

      expect(button, findsOneWidget);
      expect(find.text(es.f45S3SourceText), findsOneWidget);
      // Lo que hace, dicho entero: al mantenerlo apretado y al lector de
      // pantalla.
      expect(find.byTooltip(es.f45S3SourceTextHint), findsOneWidget);
      // En la misma fila de botones de la tarjeta, que se acomoda en
      // renglones si no entra.
      final row = find.ancestor(
        of: find.text(es.processedRetriage),
        matching: find.byType(Wrap),
      );
      expect(find.descendant(of: row, matching: button), findsOneWidget);
    });

    testWidgets('una página web no lo ofrece: volver a bajarla no es volver '
        'a leer el mismo original', (tester) async {
      await open(tester, 'pagina', kind: SourceKind.webPage);

      expect(button, findsNothing);
    });

    testWidgets('con la fuente en la papelera tampoco: primero se restaura', (
      tester,
    ) async {
      await harness.saveTextSource(
        'libro',
        kind: SourceKind.document,
        originalName: 'libro.pdf',
      );
      final documentId = await harness.processTextAndNotes('libro');
      await trashItemRows(harness.database, 'libro');
      await pumpApp(tester, harness);
      await pushAndSettle(
        tester,
        harness,
        RoutePaths.processedDocument(documentId),
      );

      expect(find.text(es.processedSourceInTrash), findsOneWidget);
      expect(button, findsNothing);
    });

    test('solo en lo que puede tener algo que hacer con su texto', () {
      expect(
        {
          for (final kind in SourceKind.values)
            if (offersSourceTextActions(kind)) kind,
        },
        {
          SourceKind.youtube,
          SourceKind.audio,
          SourceKind.video,
          SourceKind.document,
          SourceKind.image,
        },
      );
    });
  });

  group('la hoja', () {
    testWidgets('en un audio: volver a extraer y quitar las marcas, con lo '
        'que hace cada una y la nota de que cambia la fuente', (tester) async {
      await open(
        tester,
        'clase',
        kind: SourceKind.audio,
        text: transcript,
        originalName: 'clase.m4a',
      );
      await openSheet(tester);

      expect(
        find.descendant(of: sheet, matching: find.text(es.f45S3SourceText)),
        findsOneWidget,
      );
      expect(find.text(es.sourcePanelMoreTitle), findsNothing);
      expect(find.text(es.f45S3SourceTextNote), findsOneWidget);
      expect(option('reextract'), findsOneWidget);
      expect(find.text(es.sourcePanelReextractHint), findsOneWidget);
      expect(option('removeTimestamps'), findsOneWidget);
      expect(find.text(es.sourcePanelRemoveTimestampsHint), findsOneWidget);
      // El texto de una transcripción no se suelta, y lo de la IA ya es del
      // documento procesado, en su «Más».
      for (final name in ['deleteText', 'organizeWithAi', 'findDatesWithAi']) {
        expect(option(name), findsNothing, reason: name);
      }
    });

    testWidgets('en un libro: volver a extraer y soltar el texto, sin marcas '
        'de tiempo ni «pantalla completa» (la hace «Leer como libro»)', (
      tester,
    ) async {
      await open(
        tester,
        'libro',
        kind: SourceKind.document,
        text: '[12:30] Horario de atención',
        originalName: 'libro.pdf',
      );
      await openSheet(tester);

      expect(option('reextract'), findsOneWidget);
      expect(option('deleteText'), findsOneWidget);
      expect(find.text(es.sourcePanelDeleteTextHint), findsOneWidget);
      // Un PDF con una línea que empieza como una marca no es una
      // transcripción: no hay marcas que quitar.
      expect(option('removeTimestamps'), findsNothing);
      expect(find.text(es.detailExpandViewer), findsNothing);
    });

    testWidgets('mientras la fuente extrae su texto no ofrece nada, y dice '
        'por qué', (tester) async {
      await open(
        tester,
        'clase',
        kind: SourceKind.audio,
        text: transcript,
        originalName: 'clase.m4a',
      );
      final repository = harness.container.read(libraryRepositoryProvider);
      final source = (await repository.findById(
        'clase',
      )).getRight().toNullable()!;
      await repository.save(
        source.copyWith(processingState: ProcessingState.pending),
      );
      await openSheet(tester);

      expect(find.text(es.f45S3SourceTextBusy), findsOneWidget);
      expect(find.text(es.f45S3SourceTextNote), findsNothing);
      expect(
        find.descendant(of: sheet, matching: find.byType(ListTile)),
        findsNothing,
      );
    });

    testWidgets('sin nada que hacer, lo dice en vez de quedar vacía', (
      tester,
    ) async {
      // Una foto sin su archivo: no hay nada que volver a leer.
      await open(tester, 'foto', kind: SourceKind.image);
      await openSheet(tester);

      expect(find.text(es.f45S3SourceTextNothing), findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.byType(ListTile)),
        findsNothing,
      );
    });
  });

  group('lo que hace, sobre la fuente', () {
    testWidgets('«Quitar marcas de tiempo» deja el texto de la fuente sin los '
        'minutos, y ya no se ofrece', (tester) async {
      await open(
        tester,
        'clase',
        kind: SourceKind.audio,
        text: transcript,
        originalName: 'clase.m4a',
      );
      await openSheet(tester);
      await tester.tap(option('removeTimestamps'));
      await tester.pumpAndSettle();

      expect((await sourceTexts('clase')).single.content, 'hola\nchau');
      expect(find.text(es.detailTimestampsRemoved), findsOneWidget);

      await openSheet(tester);
      expect(option('removeTimestamps'), findsNothing);
    });

    testWidgets('«Volver a extraer el texto» pregunta el idioma de un audio, '
        'lo guarda y deja pedido volver a extraerlo', (tester) async {
      await open(
        tester,
        'clase',
        kind: SourceKind.audio,
        text: transcript,
        originalName: 'clase.m4a',
      );
      await openSheet(tester);
      await tester.tap(option('reextract'));
      await tester.pumpAndSettle();

      expect(find.text(es.detailReextractLanguage), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.detailReextractConfirm));
      await tester.pumpAndSettle();

      final source = await (harness.database.select(
        harness.database.knowledgeSources,
      )..where((s) => s.itemId.equals('clase'))).getSingle();
      expect(source.language, 'en');
      final marks = await (harness.database.select(
        harness.database.processingCheckpoints,
      )..where((c) => c.itemId.equals('clase'))).get();
      expect(marks.map((m) => m.kind), [ProcessingCheckpointKind.reextract]);
      expect(find.text(es.detailReextractStarted), findsOneWidget);
    });

    testWidgets('«Borrar el texto, quedarme con el libro» manda el texto de '
        'la fuente a la papelera de la app, con «Deshacer», y el documento '
        'procesado conserva el suyo', (tester) async {
      await open(
        tester,
        'libro',
        kind: SourceKind.document,
        originalName: 'libro.pdf',
      );
      await openSheet(tester);
      await tester.tap(option('deleteText'));
      await tester.pumpAndSettle();

      expect(await sourceTexts('libro'), isEmpty);
      final row = await (harness.database.select(
        harness.database.knowledgeSources,
      )..where((s) => s.itemId.equals('libro'))).getSingle();
      expect(row.onlyFile, isTrue);
      expect(find.text(es.detailTextTrashed), findsOneWidget);
      // Lo procesado es una copia: no se toca.
      expect(find.byKey(const Key('processed-section-text')), findsOneWidget);

      await tester.tap(find.text(es.contentTrashUndo));
      await tester.pumpAndSettle();
      expect(await sourceTexts('libro'), hasLength(1));
    });
  });

  group('en un teléfono', () {
    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('a 360 dp con la letra al doble, en ${themeMode.name}: la '
          'tarjeta y la hoja entran sin desbordarse', (tester) async {
        await harness.saveTextSource(
          'clase',
          title: 'Una clase de historia romana con un título largo',
          kind: SourceKind.audio,
          text: transcript,
          originalName: 'clase.m4a',
        );
        final documentId = await harness.processTextAndNotes('clase');
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: harness.container,
            child: MaterialApp(
              locale: const Locale('es'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              builder: (context, child) => MediaQuery.withClampedTextScaling(
                minScaleFactor: 2,
                maxScaleFactor: 2,
                child: child!,
              ),
              home: ProcessedDocumentScreen(documentId: documentId),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(tester.getRect(button).right, lessThanOrEqualTo(360));

        await openSheet(tester);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          option('removeTimestamps'),
          80,
          scrollable: find.descendant(
            of: sheet,
            matching: find.byType(Scrollable),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
