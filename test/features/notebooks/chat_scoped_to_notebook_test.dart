import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/data/services/chunk_passage_retriever.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../support/chat_actions.dart';
import '../../support/fake_id_generator.dart';
import '../../support/library_harness.dart';
import '../../support/processed_rows.dart';
import '../processed/processed_harness.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Un cuaderno acota el chat a sus documentos procesados (F16, D1; F41,
/// paso 5): lee solo el texto procesado, nunca los pasajes de las fuentes de
/// la Biblioteca —tampoco los de la fuente de la que salió un procesado—. Y
/// funciona como buscador acotado SIN el modelo de lenguaje descargado
/// (principio 4: degradar antes que fallar).
void main() {
  final es = AppLocalizationsEs();

  group('el alcance de un cuaderno', () {
    const text =
        'Los acueductos llevaban agua a Roma. '
        'El Senado discutía las leyes del foro.';
    late ProcessedHarness h;
    late NotebookRepositoryImpl notebooks;
    final docId = processedDocumentIdFor('roma');

    setUp(() async {
      h = await ProcessedHarness.create();
      notebooks = NotebookRepositoryImpl(
        database: h.db,
        processed: h.repository,
        telemetry: _SilentTelemetry(),
        ids: FakeIdGenerator(prefix: 'nb'),
        clock: () => h.vault.now,
      );
      await h.vault.saveSource('roma', title: 'Roma antigua', text: text);
      await h.vault.saveSource(
        'grecia',
        title: 'Grecia',
        text: 'El Senado de Esparta era la gerusía.',
      );
      expect((await h.process.passUnchanged('roma')).isRight(), isTrue);
    });
    tearDown(() => h.close());

    Future<Set<String>> scopeOf(String notebookId) async =>
        (await notebooks.memberIds(
          notebookId,
        )).getRight().toNullable()!.toSet();

    test('lee solo el texto procesado: ningún pasaje de una fuente, ni de la '
        'suya', () async {
      final notebook = await notebooks.create(
        name: 'Roma',
        mode: NotebookMode.manual,
      );
      // Pedir que entren las fuentes no las mete: solo el procesado entra.
      await notebooks.addItems(
        notebookId: notebook.id,
        itemIds: [docId, 'roma', 'grecia'],
      );
      final retriever = ChunkPassageRetriever(database: h.db);

      final found = await retriever.retrieve(
        'senado acueductos',
        scopeIds: await scopeOf(notebook.id),
      );

      expect(found.map((s) => s.itemId), [docId]);
      expect(found.single.excerpt, contains('Senado'));
      // Con toda la bóveda, las fuentes sí: el alcance es lo que las saca.
      final unscoped = await retriever.retrieve('senado');
      expect(unscoped.map((s) => s.itemId), containsAll(['roma', 'grecia']));
    });

    test(
      'uno por consulta tampoco trae las fuentes que cumplen la vista',
      () async {
        final notebook = await notebooks.create(
          name: 'Senado',
          mode: NotebookMode.query,
          query: const LibraryQuery(searchText: 'senado'),
        );
        final retriever = ChunkPassageRetriever(database: h.db);

        final scope = await scopeOf(notebook.id);
        final found = await retriever.retrieve('senado', scopeIds: scope);

        expect(scope, {docId});
        expect(found.map((s) => s.itemId), [docId]);
      },
    );

    test('un procesado que coincide solo por el título da su primera parte en '
        'el orden en que se lee —el resumen antes que las notas—, no un pasaje '
        'vacío', () async {
      await insertProcessedRows(
        h.db,
        id: 'apuntes',
        title: 'Cartago',
        parts: {
          ProcessedSection.notes: ['Lo que pienso de Aníbal.'],
          ProcessedSection.summary: ['Las guerras púnicas fueron tres.'],
        },
      );
      final notebook = await notebooks.create(
        name: 'Cartago',
        mode: NotebookMode.manual,
      );
      await notebooks.addItem(notebookId: notebook.id, itemId: 'apuntes');

      final found = await ChunkPassageRetriever(
        database: h.db,
      ).retrieve('cartago', scopeIds: await scopeOf(notebook.id));

      expect(found.single.itemId, 'apuntes');
      expect(found.single.excerpt, 'Las guerras púnicas fueron tres.');
      // Un procesado no tiene forma propia: la cita abre el documento.
      expect(found.single.sourceCharStart, isNull);
    });
  });

  group('en el chat, sin el modelo de lenguaje', () {
    late LibraryHarness harness;

    Future<void> pumpChat(WidgetTester tester) async {
      // Sin `chatModelReady`: por defecto es `false` — es justo lo que este
      // test necesita confirmar.
      harness = await LibraryHarness.create();
      await tester.pumpWidget(harness.wrap(const ChatScreen()));
      await tester.pumpAndSettle();
    }

    Future<void> send(WidgetTester tester, String text) =>
        sendChatMessage(tester, text);

    /// El cuaderno se elige en la hoja «Dónde pregunto», que abre la línea
    /// debajo del modelo (F42).
    Future<void> selectScope(WidgetTester tester, String label) =>
        chooseChatScope(tester, label);

    testWidgets('elegir un cuaderno igual acota la búsqueda a sus procesados', (
      tester,
    ) async {
      await pumpChat(tester);
      // Título y cuerpo distintos: si coincidieran, la tarjeta de fuente
      // mostraría el mismo texto dos veces —título y fragmento citado— y
      // `find.text` dejaría de ser único.
      await insertProcessedRows(
        harness.database,
        id: 'adentro',
        title: 'Adentro del cuaderno',
        parts: {
          ProcessedSection.notes: ['habla de lo de adentro'],
        },
      );
      await harness.capture('Afuera del cuaderno\n\nhabla de lo de afuera');
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Mi cuaderno', mode: NotebookMode.manual);
      await harness.container
          .read(notebookRepositoryProvider)
          .addItem(notebookId: notebook.id, itemId: 'adentro');
      await tester.pumpAndSettle();

      // Sin acotar todavía: la palabra "cuaderno" está en los dos títulos.
      await send(tester, 'cuaderno');
      expect(find.text('Adentro del cuaderno'), findsOneWidget);
      expect(find.text('Afuera del cuaderno'), findsOneWidget);

      await tester.tap(find.byTooltip(es.chatNewConversationTooltip));
      await tester.pumpAndSettle();
      await selectScope(tester, 'Mi cuaderno');
      await send(tester, 'cuaderno');

      // Acotado, solo el de adentro — sin haber tocado el modelo en ningún
      // momento: no hay `chatModelReady` en este test.
      expect(find.text('Adentro del cuaderno'), findsOneWidget);
      expect(find.text('Afuera del cuaderno'), findsNothing);
      expect(harness.chatModel.vaultConversations, isEmpty);
    });

    testWidgets(
      'un cuaderno sin nada adentro dice que no encontró nada —no es que la '
      'búsqueda haya fallado—',
      (tester) async {
        await pumpChat(tester);
        await harness.capture('Lo único que hay\n\ncon algo de cuerpo');

        final notebook = await harness.container
            .read(notebookRepositoryProvider)
            .create(name: 'Cuaderno vacío', mode: NotebookMode.manual);
        await tester.pumpAndSettle();

        await selectScope(tester, notebook.name);
        await send(tester, 'lo único');

        expect(find.text('Lo único que hay'), findsNothing);
        expect(find.text(es.chatNoSourcesFound), findsOneWidget);
      },
    );

    testWidgets(
      'uno por consulta acota a los procesados que cumplen su vista, no a lo '
      'de la Biblioteca que la cumple',
      (tester) async {
        await pumpChat(tester);
        await insertProcessedRows(
          harness.database,
          id: 'adentro',
          title: 'Adentro por consulta',
          parts: {
            ProcessedSection.notes: ['habla de una consulta'],
          },
        );
        await harness.capture('Adentro de la Biblioteca\n\notra consulta');
        await harness.capture('Afuera de la consulta\n\nhabla de otra cosa');

        // La consulta de un cuaderno por consulta sale de una vista guardada
        // (16.3): esa vía nunca lleva `ids` —`libraryQueryToJson` los deja
        // afuera a propósito, es de la sesión, no del filtro que se nombra—,
        // así que lo que de verdad acota acá es el propio filtro de texto,
        // sobre los procesados.
        await harness.container
            .read(notebookRepositoryProvider)
            .create(
              name: 'Por consulta',
              mode: NotebookMode.query,
              query: const LibraryQuery(searchText: 'adentro'),
            );
        await tester.pumpAndSettle();

        await selectScope(tester, 'Por consulta');
        await send(tester, 'consulta');

        expect(find.text('Adentro por consulta'), findsOneWidget);
        expect(find.text('Adentro de la Biblioteca'), findsNothing);
        expect(find.text('Afuera de la consulta'), findsNothing);
        expect(harness.chatModel.vaultConversations, isEmpty);
      },
    );
  });
}
