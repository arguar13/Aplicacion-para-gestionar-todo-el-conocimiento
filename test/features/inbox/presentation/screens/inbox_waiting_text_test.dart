import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Lo nuevo entra a la Bandeja apenas se guarda, tenga su texto o no (F41):
/// la tarjeta dice qué le falta, «Descartar» se puede de entrada, y lo que
/// necesita el texto queda apagado, con su motivo, hasta que llega —y entonces
/// se prende solo, en la misma tarjeta—.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  final now = DateTime(2026, 10, 27, 9);
  var counter = 0;

  setUp(() async {
    harness = await LibraryHarness.create();
    counter = 0;
  });

  KnowledgeItem sourceItem({
    required String title,
    SourceKind kind = SourceKind.audio,
    ProcessingState processing = ProcessingState.processing,
    String? file = 'originales/x/archivo',
    List<Rendition> renditions = const [],
  }) {
    final n = counter++;
    final at = now.add(Duration(minutes: n));
    return KnowledgeItem(
      id: 'item-$n',
      title: title,
      source: Source(
        id: 'src-$n',
        kind: kind,
        capturedAt: at,
        originalFilePath: file,
      ),
      processingState: processing,
      createdAt: at,
      updatedAt: at,
      renditions: renditions,
    );
  }

  Future<KnowledgeItem> save(KnowledgeItem item) async {
    await harness.container.read(libraryRepositoryProvider).save(item);
    return item;
  }

  Rendition transcript(String itemId) => Rendition.text(
    id: 'texto-$itemId',
    itemId: itemId,
    kind: RenditionKind.plainText,
    content: 'Buenas tardes a todos: hoy, el Imperio romano.',
    isPrimary: true,
    createdAt: now,
  );

  Future<ItemState> stateOf(String id) async => (await (harness.database.select(
    harness.database.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle()).state;

  Future<void> pumpInbox(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const InboxScreen()));
    await tester.pumpAndSettle();
  }

  /// El botón de la tarjeta con [label], para ver si está prendido.
  ButtonStyleButton button(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );

  bool enabled(WidgetTester tester, String label) =>
      button(tester, label).onPressed != null;

  testWidgets('un audio recién guardado ya está en la Bandeja con '
      '«Transcribiendo…»: cuenta, se puede descartar y lo demás está apagado '
      'con su motivo; cuando llega la transcripción, la misma tarjeta se '
      'prende sola', (tester) async {
    final audio = await save(sourceItem(title: 'Una clase grabada'));
    await pumpInbox(tester);

    expect(find.text('Una clase grabada'), findsOneWidget);
    expect(find.text(es.inboxPendingCount(1)), findsOneWidget);
    expect(find.text(es.inboxTextTranscribing), findsOneWidget);
    expect(find.text(es.inboxTextArrivingHint), findsOneWidget);
    expect(find.byKey(const Key('pending-excerpt')), findsNothing);
    expect(enabled(tester, es.inboxActionDiscard), isTrue);
    for (final label in [
      es.inboxActionTriage,
      es.inboxActionPassUnchanged,
      es.inboxActionExtract,
      es.inboxActionLink,
    ]) {
      expect(enabled(tester, label), isFalse, reason: label);
    }
    expect(find.byTooltip(es.inboxTextNeededArriving), findsNWidgets(4));
    expect(await stateOf(audio.id), ItemState.captured);

    // Llega la transcripción: el procesamiento la guarda, como siempre.
    await save(
      audio.copyWith(
        processingState: ProcessingState.ready,
        renditions: [transcript(audio.id)],
        updatedAt: now.add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Una clase grabada'), findsOneWidget);
    expect(find.text(es.inboxTextTranscribing), findsNothing);
    expect(find.byKey(const Key('pending-excerpt')), findsOneWidget);
    for (final label in [
      es.inboxActionTriage,
      es.inboxActionPassUnchanged,
      es.inboxActionExtract,
      es.inboxActionLink,
    ]) {
      expect(enabled(tester, label), isTrue, reason: label);
    }
    expect(find.byTooltip(es.inboxTextNeededArriving), findsNothing);
    expect(await stateOf(audio.id), ItemState.processed);
  });

  testWidgets('mientras espera, ni la flecha ni el gesto la trían ni la '
      'abren para extraer; la flecha izquierda sí la descarta', (tester) async {
    final audio = await save(sourceItem(title: 'Una clase grabada'));
    await pumpInbox(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    // Tampoco «Pasar todo sin modificar» (F41): no hay texto que pasar.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    // Ni lo intenta: no hay un fallo que avisar.
    expect(find.byType(SnackBar), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.drag(find.text('Una clase grabada'), const Offset(400, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Una clase grabada'), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(await stateOf(audio.id), ItemState.captured);
    expect(find.text('Una clase grabada'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(await stateOf(audio.id), ItemState.discarded);
    expect(find.text(es.inboxEmptyTitle), findsOneWidget);
  });

  testWidgets('descartarla mientras espera y deshacer la devuelve esperando', (
    tester,
  ) async {
    final audio = await save(sourceItem(title: 'Una clase grabada'));
    await pumpInbox(tester);

    await tester.tap(find.text(es.inboxActionDiscard));
    await tester.pumpAndSettle();
    expect(await stateOf(audio.id), ItemState.discarded);

    await tester.tap(find.text(es.inboxUndo).last);
    await tester.pumpAndSettle();

    expect(await stateOf(audio.id), ItemState.captured);
    expect(find.text(es.inboxTextTranscribing), findsOneWidget);
  });

  testWidgets('una foto dice «Leyendo la foto…» y un documento «Extrayendo el '
      'texto…», en la tarjeta y en la lista de la cola', (tester) async {
    await save(
      sourceItem(
        title: 'Una pizarra',
        kind: SourceKind.image,
        processing: ProcessingState.pending,
      ),
    );
    await save(sourceItem(title: 'Un libro', kind: SourceKind.document));
    await save(
      sourceItem(
        title: 'Un artículo',
        kind: SourceKind.webPage,
        processing: ProcessingState.ready,
        file: null,
        renditions: [transcript('item-2')],
      ),
    );
    await pumpInbox(tester);

    expect(find.text('Una pizarra'), findsOneWidget);
    expect(find.text(es.inboxTextReadingPhoto), findsOneWidget);

    await tester.tap(find.text(es.inboxPendingCount(3)));
    await tester.pumpAndSettle();

    String subtitleOf(String title) => tester
        .widget<Text>(
          find.descendant(
            of: find.widgetWithText(ListTile, title),
            matching: find.textContaining(' · '),
          ),
        )
        .data!;
    expect(subtitleOf('Una pizarra'), contains(es.inboxTextReadingPhoto));
    expect(subtitleOf('Un libro'), contains(es.inboxTextExtracting));
    // Lo que ya tiene su texto no dice nada de más.
    expect(subtitleOf('Un artículo').split(' · '), hasLength(2));

    await tester.tap(find.text('Un libro'));
    await tester.pumpAndSettle();

    expect(find.text(es.inboxTextExtracting), findsOneWidget);
  });

  testWidgets('si sacarle el texto falló, lo dice y «Reintentar» lo vuelve a '
      'poner en la cola', (tester) async {
    final foto = await save(
      sourceItem(
        title: 'Una pizarra',
        kind: SourceKind.image,
        processing: ProcessingState.failed,
      ),
    );
    await pumpInbox(tester);

    expect(find.text(es.inboxTextFailed), findsOneWidget);
    expect(find.byTooltip(es.inboxTextNeededFailed), findsNWidgets(4));
    expect(enabled(tester, es.inboxActionDiscard), isTrue);

    await tester.tap(find.byKey(const Key('pending-text-retry')));
    await tester.pumpAndSettle();

    expect(harness.queue.enqueued, [foto.id]);
    // Vuelve a esperar su turno: la tarjeta lo dice sola.
    expect(find.text(es.inboxTextReadingPhoto), findsOneWidget);
    // Lo que miraba el fallo se soltó: el temporizador de drift, que vence.
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('lo que terminó sin texto lo dice, ofrece volver a leer el '
      'original y se puede descartar', (tester) async {
    final foto = await save(
      sourceItem(
        title: 'Una foto sin letras',
        kind: SourceKind.image,
        processing: ProcessingState.ready,
      ),
    );
    await pumpInbox(tester);

    expect(find.text(es.inboxTextMissing), findsOneWidget);
    expect(find.byKey(const Key('pending-text-reextract')), findsOneWidget);
    expect(find.byTooltip(es.inboxTextNeededMissing), findsNWidgets(4));

    await tester.tap(find.text(es.inboxActionDiscard));
    await tester.pumpAndSettle();

    expect(await stateOf(foto.id), ItemState.discarded);
  });

  testWidgets('una página sin texto propio que trae el de un archivo de su '
      '«Contenido» se tría, pero «Extraer nota» y «Pasar todo sin modificar» '
      'siguen apagadas: las dos trabajan sobre el texto del elemento', (
    tester,
  ) async {
    final pagina = await save(
      sourceItem(
        title: 'Una página',
        kind: SourceKind.webPage,
        processing: ProcessingState.ready,
        file: null,
      ),
    );
    await harness.database
        .into(harness.database.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'adjunto',
            itemId: pagina.id,
            kind: RenditionKind.pdf,
            relativePath: const Value('originales/x/adjunto.pdf'),
            isPrimary: false,
            createdAt: now,
            position: const Value(0),
          ),
        );
    await harness.database
        .into(harness.database.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'adjunto-texto',
            itemId: pagina.id,
            kind: RenditionKind.plainText,
            content: const Value('El texto del adjunto.'),
            isPrimary: false,
            createdAt: now,
            textOf: const Value('adjunto'),
          ),
        );
    await pumpInbox(tester);

    expect(enabled(tester, es.inboxActionTriage), isTrue);
    expect(enabled(tester, es.inboxActionLink), isTrue);
    expect(enabled(tester, es.inboxActionExtract), isFalse);
    expect(
      find.byTooltip(es.inboxActionExtractDisabledTooltip),
      findsOneWidget,
    );
    expect(enabled(tester, es.inboxActionPassUnchanged), isFalse);
    expect(
      find.byTooltip(es.inboxActionPassUnchangedDisabledTooltip),
      findsOneWidget,
    );
  });
}
