import 'package:async/async.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/inbox/data/repositories/inbox_repository_impl.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_standing.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_text.dart';

import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria, sembrando filas directo en
/// `knowledgeEntries`/`knowledgeNotes` a mano: no hace falta pasar por
/// `LibraryRepositoryImpl` para probar solo el espejo, que es lo único
/// que `InboxRepositoryImpl` lee y escribe.
void main() {
  late AppDatabase db;
  late InboxRepositoryImpl repository;

  final now = DateTime(2026, 9, 18, 10);
  var counter = 0;
  var clockNow = DateTime(2026, 9, 20, 9);

  setUp(() {
    clockNow = DateTime(2026, 9, 20, 9);
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    repository = InboxRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      clock: () => clockNow,
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<void> seedText(
    String itemId,
    String text, {
    String? textOf,
    RenditionKind kind = RenditionKind.plainText,
  }) => db
      .into(db.renditions)
      .insert(
        RenditionsCompanion.insert(
          id: 'texto-${counter++}',
          itemId: itemId,
          kind: kind,
          content: Value(text),
          isPrimary: textOf == null,
          createdAt: now,
          textOf: Value(textOf),
        ),
      );

  Future<String> seedEntry({
    ItemKind kind = ItemKind.source,
    ItemState state = ItemState.processed,
    String title = 'Un elemento',
    DateTime? createdAt,
    DateTime? updatedAt,
    String? text = 'Un texto para leer.',
  }) async {
    final id = 'item-${counter++}';
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: id,
            title: title,
            kind: kind,
            state: state,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deviceId: 'test',
          ),
        );
    // Las fuentes de estas pruebas traen su texto, salvo que se pida otra
    // cosa: lo que todavía lo espera tiene sus propias pruebas (F41).
    if (kind == ItemKind.source && text != null) await seedText(id, text);
    return id;
  }

  Future<void> seedNote(
    String itemId, {
    NoteKind noteKind = NoteKind.living,
    NoteMaturity maturity = NoteMaturity.seed,
  }) async {
    await db
        .into(db.knowledgeNotes)
        .insert(
          KnowledgeNotesCompanion.insert(
            itemId: itemId,
            noteKind: noteKind,
            maturity: maturity,
          ),
        );
  }

  group('watchPendingIds', () {
    test('trae las fuentes sobre las que nadie decidió: procesadas y las que '
        'todavía se procesan (F41)', () async {
      final processed = await seedEntry();
      final captured = await seedEntry(state: ItemState.captured);
      final triaged = await seedEntry(state: ItemState.triaged);
      final distilled = await seedEntry(state: ItemState.distilled);
      final discarded = await seedEntry(state: ItemState.discarded);
      final noteId = await seedEntry(kind: ItemKind.note);
      await seedNote(noteId);

      final ids = await repository.watchPendingIds().first;

      expect(ids, unorderedEquals([processed, captured]));
      expect(ids, isNot(contains(triaged)));
      expect(ids, isNot(contains(distilled)));
      expect(ids, isNot(contains(discarded)));
      expect(ids, isNot(contains(noteId)));
    });

    test('ordena por llegada: la que se guardó primero va primero', () async {
      final nueva = await seedEntry(
        title: 'Nueva',
        createdAt: now.add(const Duration(hours: 2)),
      );
      final vieja = await seedEntry(
        title: 'Vieja',
        createdAt: now.add(const Duration(hours: 1)),
      );

      final ids = await repository.watchPendingIds().first;

      expect(ids, [vieja, nueva]);
    });

    test('el orden no se mueve cuando la fuente se edita o le llega el texto: '
        'la tarjeta que se mira sigue arriba', () async {
      final esperando = await seedEntry(
        title: 'Un audio',
        text: null,
        createdAt: now.add(const Duration(hours: 1)),
        updatedAt: now.add(const Duration(hours: 9)),
      );
      final despues = await seedEntry(
        title: 'Otra',
        createdAt: now.add(const Duration(hours: 2)),
        updatedAt: now.add(const Duration(hours: 3)),
      );

      expect(await repository.watchPendingIds().first, [esperando, despues]);
    });

    test('dos guardadas en el mismo instante salen siempre en el mismo '
        'orden', () async {
      final b = await seedEntry(title: 'B');
      final a = await seedEntry(title: 'A');

      // El `id` desempata: el mismo orden en cada lectura.
      expect(await repository.watchPendingIds().first, [a, b]..sort());
    });

    test('se actualiza sola cuando un elemento cambia de estado', () async {
      final id = await seedEntry();

      expect(await repository.watchPendingIds().first, [id]);

      await repository.transitionState(itemId: id, to: ItemState.discarded);

      expect(await repository.watchPendingIds().first, isEmpty);
    });
  });

  group('transitionState', () {
    test('cambia el estado del elemento', () async {
      final id = await seedEntry();

      final result = await repository.transitionState(
        itemId: id,
        to: ItemState.triaged,
      );

      expect(result.isRight(), isTrue);
      final entry = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals(id))).getSingle();
      expect(entry.state, ItemState.triaged);
    });

    test('un elemento que no existe devuelve un fallo, no revienta', () async {
      final result = await repository.transitionState(
        itemId: 'no-existe',
        to: ItemState.discarded,
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('watchLivingNotes', () {
    test('solo trae notas con noteKind living', () async {
      final viva = await seedEntry(kind: ItemKind.note, title: 'Viva');
      await seedNote(viva);
      final atomica = await seedEntry(kind: ItemKind.note, title: 'Atómica');
      await seedNote(atomica, noteKind: NoteKind.atomic);
      final fuente = await seedEntry();

      final notes = await repository.watchLivingNotes().first;

      expect(notes.map((n) => n.id), [viva]);
      expect(notes.map((n) => n.id), isNot(contains(atomica)));
      expect(notes.map((n) => n.id), isNot(contains(fuente)));
    });

    test('filtra por título, sin distinguir mayúsculas', () async {
      final roma = await seedEntry(kind: ItemKind.note, title: 'Roma antigua');
      await seedNote(roma);
      final egipto = await seedEntry(kind: ItemKind.note, title: 'Egipto');
      await seedNote(egipto);

      final notes = await repository.watchLivingNotes(searchText: 'roma').first;

      expect(notes.map((n) => n.id), [roma]);
    });
  });

  group('watchNoteMaturity', () {
    test('null para una fuente', () async {
      final id = await seedEntry();

      expect(await repository.watchNoteMaturity(id).first, isNull);
    });

    test('el valor real para una nota', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id, maturity: NoteMaturity.developing);

      expect(
        await repository.watchNoteMaturity(id).first,
        NoteMaturity.developing,
      );
    });
  });

  group('watchNoteKind', () {
    test('null para una fuente', () async {
      final id = await seedEntry();

      expect(await repository.watchNoteKind(id).first, isNull);
    });

    test('el valor real para una nota', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id, noteKind: NoteKind.atomic);

      expect(await repository.watchNoteKind(id).first, NoteKind.atomic);
    });

    test('se actualiza sola tras setNoteKind', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id);

      expect(await repository.watchNoteKind(id).first, NoteKind.living);

      await repository.setNoteKind(itemId: id, kind: NoteKind.map);

      expect(await repository.watchNoteKind(id).first, NoteKind.map);
    });
  });

  group('setNoteKind', () {
    test('cambia el tipo de la nota', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id);

      final result = await repository.setNoteKind(
        itemId: id,
        kind: NoteKind.map,
      );

      expect(result.isRight(), isTrue);
      final row = await (db.select(
        db.knowledgeNotes,
      )..where((n) => n.itemId.equals(id))).getSingle();
      expect(row.noteKind, NoteKind.map);
    });

    test('sin espejo de nota devuelve un fallo, no revienta', () async {
      final id = await seedEntry(kind: ItemKind.note);
      // Sin `seedNote`: el elemento existe pero no tiene fila en
      // `knowledgeNotes` — el mismo caso que un elemento que todavía no
      // pasó por el espejo.

      final result = await repository.setNoteKind(
        itemId: id,
        kind: NoteKind.map,
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('setNoteMaturity', () {
    test('cambia la madurez de la nota', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id);

      final result = await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.mature,
      );

      expect(result.isRight(), isTrue);
      final row = await (db.select(
        db.knowledgeNotes,
      )..where((n) => n.itemId.equals(id))).getSingle();
      expect(row.maturity, NoteMaturity.mature);
    });

    test(
      'se puede volver atrás: la madurez no es un escalón de una sola vía',
      () async {
        final id = await seedEntry(kind: ItemKind.note);
        await seedNote(id, maturity: NoteMaturity.mature);

        await repository.setNoteMaturity(
          itemId: id,
          maturity: NoteMaturity.seed,
        );

        expect(await repository.watchNoteMaturity(id).first, NoteMaturity.seed);
      },
    );

    test('no toca el tipo de la nota ni a las demás', () async {
      final id = await seedEntry(kind: ItemKind.note);
      final other = await seedEntry(kind: ItemKind.note);
      await seedNote(id, noteKind: NoteKind.map);
      await seedNote(other);

      await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.developing,
      );

      expect(await repository.watchNoteKind(id).first, NoteKind.map);
      expect(
        await repository.watchNoteMaturity(other).first,
        NoteMaturity.seed,
      );
    });

    test('se refleja sola en watchNoteMaturity', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id);
      final emissions = repository.watchNoteMaturity(id);
      final expectation = expectLater(
        emissions,
        emitsThrough(NoteMaturity.developing),
      );

      await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.developing,
      );

      await expectation.timeout(const Duration(seconds: 5));
    });

    test('sin espejo de nota devuelve un fallo, no revienta', () async {
      final id = await seedEntry(kind: ItemKind.note);

      final result = await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.mature,
      );

      expect(result.isLeft(), isTrue);
    });

    test('una fuente no tiene madurez: falla', () async {
      final id = await seedEntry();

      final result = await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.mature,
      );

      expect(result.isLeft(), isTrue);
    });
  });

  /// La fila de `source` de una fuente sembrada a mano: la que lee la cola.
  Future<void> seedSourceRow(
    String itemId, {
    SourceKind kind = SourceKind.webPage,
    DateTime? capturedAt,
    SourceProcessingStatus status = SourceProcessingStatus.done,
  }) => db
      .into(db.knowledgeSources)
      .insert(
        KnowledgeSourcesCompanion.insert(
          itemId: itemId,
          sourceType: kind,
          capturedAt: capturedAt ?? now,
          contentHash: 'hash-$itemId',
          processingStatus: status,
        ),
      );

  group('watchPending (F28)', () {
    test('lo mismo que watchPendingIds, en el mismo orden, con tipo y '
        'fecha', () async {
      final nueva = await seedEntry(
        title: 'Nueva',
        createdAt: now.add(const Duration(hours: 2)),
      );
      await seedSourceRow(nueva, kind: SourceKind.youtube);
      final vieja = await seedEntry(
        title: 'Vieja',
        createdAt: now.add(const Duration(hours: 1)),
      );
      await seedSourceRow(vieja, capturedAt: DateTime(2026, 8, 30));
      final triada = await seedEntry(state: ItemState.triaged);
      await seedSourceRow(triada);

      final pending = await repository.watchPending().first;

      expect(
        pending.map((p) => p.id),
        await repository.watchPendingIds().first,
      );
      expect(pending.map((p) => p.id), [vieja, nueva]);
      expect(pending.first.title, 'Vieja');
      expect(pending.first.capturedAt, DateTime(2026, 8, 30));
      expect(pending.last.kind, SourceKind.youtube);
    });

    test('se actualiza sola al triar', () async {
      final id = await seedEntry();
      await seedSourceRow(id);
      final queue = StreamQueue(repository.watchPending());
      addTearDown(queue.cancel);
      expect((await queue.next).map((p) => p.id), [id]);

      await repository.transitionState(itemId: id, to: ItemState.triaged);

      expect(await queue.next, isEmpty);
    });
  });

  group('watchStanding (F28)', () {
    test('una fuente pendiente está en la Bandeja', () async {
      final id = await seedEntry();

      expect(
        await repository.watchStanding(id).first,
        const InboxStanding(status: InboxStatus.pending),
      );
    });

    test('triar la deja triada desde ese momento', () async {
      final id = await seedEntry();

      await repository.transitionState(itemId: id, to: ItemState.triaged);

      expect(
        await repository.watchStanding(id).first,
        InboxStanding(status: InboxStatus.triaged, since: clockNow),
      );
    });

    test('destilada también cuenta como triada; descartada, como '
        'descartada', () async {
      final destilada = await seedEntry(state: ItemState.distilled);
      final descartada = await seedEntry(state: ItemState.discarded);

      expect(
        (await repository.watchStanding(destilada).first)!.status,
        InboxStatus.triaged,
      );
      // Sin versión del estado —lo de antes de F11—, sin fecha.
      expect(
        await repository.watchStanding(descartada).first,
        const InboxStanding(status: InboxStatus.discarded),
      );
    });

    test('una nota o algo que no existe no tienen nada que ver con la '
        'Bandeja', () async {
      final nota = await seedEntry(kind: ItemKind.note);
      await seedNote(nota);

      expect(await repository.watchStanding(nota).first, isNull);
      expect(await repository.watchStanding('no-existe').first, isNull);
    });

    test(
      'una fuente que todavía se procesa ya está en la Bandeja (F41)',
      () async {
        final procesandose = await seedEntry(
          state: ItemState.captured,
          text: null,
        );

        expect(
          (await repository.watchStanding(procesandose).first)!.status,
          InboxStatus.pending,
        );
      },
    );

    test('se actualiza sola al volver a la Bandeja', () async {
      final id = await seedEntry(state: ItemState.triaged);
      await seedSourceRow(id);
      final queue = StreamQueue(repository.watchStanding(id));
      addTearDown(queue.cancel);
      expect((await queue.next)!.status, InboxStatus.triaged);

      await repository.returnToInbox(id);

      expect((await queue.next)!.status, InboxStatus.pending);
    });
  });

  group('lo que espera su texto (F41)', () {
    test('un audio sin transcribir ya espera en la Bandeja, cuenta y figura '
        'en la cola como «llegando»; cuando llega su transcripción, la misma '
        'fuente queda lista, sin moverse de lugar', () async {
      final audio = await seedEntry(
        title: 'Una clase',
        state: ItemState.captured,
        text: null,
      );
      await seedSourceRow(
        audio,
        kind: SourceKind.audio,
        status: SourceProcessingStatus.running,
      );
      final articulo = await seedEntry(title: 'Un artículo');
      await seedSourceRow(articulo);

      expect(await repository.watchPendingIds().first, [audio, articulo]);
      final queue = await repository.watchPending().first;
      expect(queue.map((p) => (p.id, p.text)), [
        (audio, PendingText.arriving),
        (articulo, PendingText.ready),
      ]);
      expect(
        (await repository.watchStanding(audio).first)!.status,
        InboxStatus.pending,
      );

      final text = StreamQueue(repository.watchPendingText(audio));
      addTearDown(text.cancel);
      expect(await text.next, PendingText.arriving);

      await seedText(audio, '[0:00] Buenas tardes a todos.');

      expect(await text.next, PendingText.ready);
      expect(await repository.watchPendingIds().first, [audio, articulo]);
    });

    test('un fallo y lo que terminó sin texto se distinguen: uno se '
        'reintenta, el otro no va a llegar solo', () async {
      final fallo = await seedEntry(state: ItemState.captured, text: null);
      await seedSourceRow(fallo, status: SourceProcessingStatus.failed);
      final enEspera = await seedEntry(state: ItemState.captured, text: null);
      await seedSourceRow(enEspera, status: SourceProcessingStatus.pending);
      final foto = await seedEntry(title: 'Una foto', text: ' \n\t \r\n');
      await seedSourceRow(foto, kind: SourceKind.image);

      expect(
        await repository.watchPendingText(fallo).first,
        PendingText.failed,
      );
      expect(
        await repository.watchPendingText(enEspera).first,
        PendingText.arriving,
      );
      // Un texto en blanco no cuenta: se intentó leer y no tenía nada.
      expect(
        await repository.watchPendingText(foto).first,
        PendingText.missing,
      );
      expect(
        await repository.watchPendingIds().first,
        unorderedEquals([fallo, enEspera, foto]),
      );
    });

    test('una nota de bloques no es el texto de una fuente', () async {
      final id = await seedEntry(text: null);
      await seedSourceRow(id);
      await seedText(id, '[]', kind: RenditionKind.blocks);

      expect(await repository.watchPendingText(id).first, PendingText.missing);
    });

    test('el texto de un archivo del «Contenido» cuenta: la página no tiene '
        'cuerpo pero trae un PDF con texto', () async {
      final id = await seedEntry(title: 'Una publicación', text: null);
      await seedSourceRow(id, kind: SourceKind.socialPost);
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'archivo',
              itemId: id,
              kind: RenditionKind.pdf,
              relativePath: const Value('originales/x/doc.pdf'),
              isPrimary: false,
              createdAt: now,
              position: const Value(0),
            ),
          );
      // El archivo solo, sin texto, no alcanza.
      expect(await repository.watchPendingText(id).first, PendingText.missing);

      await seedText(id, 'El texto del PDF.', textOf: 'archivo');

      expect(await repository.watchPendingText(id).first, PendingText.ready);
      expect(
        (await repository.watchPending().first).single.text,
        PendingText.ready,
      );
    });

    test('con texto, lo que se vuelve a extraer sigue listo: el de antes '
        'queda hasta que llega el nuevo', () async {
      final id = await seedEntry();
      await seedSourceRow(id, status: SourceProcessingStatus.running);

      expect(await repository.watchPendingText(id).first, PendingText.ready);
    });

    test('una nota o algo que no existe no tienen texto que esperar', () async {
      final nota = await seedEntry(kind: ItemKind.note);
      await seedNote(nota);

      expect(await repository.watchPendingText(nota).first, isNull);
      expect(await repository.watchPendingText('no-existe').first, isNull);
    });

    test('«Volver a la Bandeja» se ofrece tenga texto o no; en una referencia '
        'bibliográfica, no (decisión E)', () async {
      final sinTexto = await seedEntry(state: ItemState.triaged, text: null);
      await seedSourceRow(sinTexto, kind: SourceKind.audio);
      final conTexto = await seedEntry(state: ItemState.discarded);
      await seedSourceRow(conTexto);
      final referencia = await seedEntry(state: ItemState.triaged, text: null);
      await seedSourceRow(referencia, kind: SourceKind.reference);

      final a = (await repository.watchStanding(sinTexto).first)!;
      final b = (await repository.watchStanding(conTexto).first)!;
      final c = (await repository.watchStanding(referencia).first)!;

      expect((a.status, a.canReturn), (InboxStatus.triaged, true));
      expect((b.status, b.canReturn), (InboxStatus.discarded, true));
      expect((c.status, c.canReturn), (InboxStatus.triaged, false));
    });
  });

  group('returnToInbox (F41)', () {
    Future<ItemState> stateOf(String id) async => (await (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(id))).getSingle()).state;

    test('lo que ya terminó de procesarse vuelve a processed', () async {
      final id = await seedEntry(state: ItemState.triaged);
      await seedSourceRow(id);

      expect((await repository.returnToInbox(id)).isRight(), isTrue);

      expect(await stateOf(id), ItemState.processed);
      expect(await repository.watchPendingIds().first, [id]);
    });

    test('lo que todavía se procesa, espera su turno o falló vuelve a '
        'captured, como recién guardado', () async {
      for (final status in [
        SourceProcessingStatus.pending,
        SourceProcessingStatus.running,
        SourceProcessingStatus.failed,
      ]) {
        final id = await seedEntry(state: ItemState.discarded, text: null);
        await seedSourceRow(id, status: status);

        expect((await repository.returnToInbox(id)).isRight(), isTrue);

        expect(await stateOf(id), ItemState.captured, reason: status.name);
      }
    });

    test('una nota o algo que no existe: falla sin tocar nada', () async {
      final nota = await seedEntry(kind: ItemKind.note);
      await seedNote(nota);

      expect((await repository.returnToInbox(nota)).isLeft(), isTrue);
      expect((await repository.returnToInbox('no-existe')).isLeft(), isTrue);
      expect(await stateOf(nota), ItemState.processed);
    });
  });

  group('cuánto es (F30, decisión 68)', () {
    Future<void> seedChunk(String itemId, int seq, {int? page, int? endMs}) =>
        db
            .into(db.chunks)
            .insert(
              ChunksCompanion.insert(
                id: 'chunk-$itemId-$seq',
                itemId: itemId,
                seq: seq,
                content: 'Un fragmento.',
                charStart: seq * 20,
                charEnd: seq * 20 + 13,
                pageNumber: Value(page),
                endMs: Value(endMs),
              ),
            );

    test('un PDF tiene las páginas de su último fragmento', () async {
      final id = await seedEntry();
      await seedChunk(id, 0, page: 1);
      await seedChunk(id, 1, page: 248);

      final extent = await repository.watchExtent(id).first;

      expect(extent.pages, 248);
      expect(extent.duration, isNull);
    });

    test('un audio dura hasta donde termina su último fragmento', () async {
      final id = await seedEntry();
      await seedChunk(id, 0, endMs: 60000);
      await seedChunk(id, 1, endMs: 42 * 60 * 1000);

      final extent = await repository.watchExtent(id).first;

      expect(extent.duration, const Duration(minutes: 42));
      expect(extent.pages, isNull);
    });

    test('un artículo no tiene ninguna de las dos: no se inventa', () async {
      final id = await seedEntry();
      await seedChunk(id, 0);

      expect((await repository.watchExtent(id).first).isEmpty, isTrue);
      expect((await repository.watchExtent('no-existe').first).isEmpty, isTrue);
    });
  });

  group('quién y cuándo (F11)', () {
    Future<KnowledgeEntryRow> entryOf(String id) => (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(id))).getSingle();

    Future<Map<String, FieldVersionRow>> versionsOf(String id) async => {
      for (final row in await (db.select(
        db.fieldVersions,
      )..where((f) => f.itemId.equals(id))).get())
        row.fieldName: row,
    };

    test('pasar un elemento de estado deja su firma y su versión', () async {
      final id = await seedEntry();

      await repository.transitionState(itemId: id, to: ItemState.triaged);

      final entry = await entryOf(id);
      expect(entry.state, ItemState.triaged);
      expect(entry.rev, 2);
      expect(entry.deviceId, 'telefono');
      final state = (await versionsOf(id))[EntryField.state]!;
      expect(state.updatedAt, clockNow);
      expect(state.deviceId, 'telefono');
    });

    test('«pasar» al estado que ya tiene no cuenta como un cambio', () async {
      final id = await seedEntry();

      final result = await repository.transitionState(
        itemId: id,
        to: ItemState.processed,
      );

      expect(result.isRight(), isTrue);
      expect((await entryOf(id)).rev, 1);
      expect(await versionsOf(id), isEmpty);
    });

    test('cambiar el subtipo y la madurez de una nota los versiona', () async {
      final id = await seedEntry(kind: ItemKind.note);
      await seedNote(id);

      await repository.setNoteKind(itemId: id, kind: NoteKind.atomic);
      clockNow = clockNow.add(const Duration(minutes: 5));
      await repository.setNoteMaturity(
        itemId: id,
        maturity: NoteMaturity.mature,
      );

      expect((await entryOf(id)).rev, 3);
      final fields = await versionsOf(id);
      expect(fields[EntryField.noteKind]!.deviceId, 'telefono');
      expect(fields[EntryField.maturity]!.updatedAt, clockNow);
    });
  });

  group('la papelera (F11)', () {
    test('una fuente en la papelera no espera triaje, y vuelve al '
        'restaurarla', () async {
      final id = await seedEntry(title: 'Borrada');
      final other = await seedEntry(title: 'Otra');
      final queue = StreamQueue(repository.watchPendingIds());
      addTearDown(queue.cancel);
      expect(await queue.next, unorderedEquals([id, other]));

      await trashItemRows(db, id);
      expect(await queue.next, [other]);

      await restoreItemRows(db, id);
      expect(await queue.next, unorderedEquals([id, other]));
    });

    test('una nota viva en la papelera no se ofrece para vincular', () async {
      final viva = await seedEntry(kind: ItemKind.note, title: 'Viva');
      await seedNote(viva);
      final borrada = await seedEntry(kind: ItemKind.note, title: 'Borrada');
      await seedNote(borrada);
      await trashItemRows(db, borrada);

      final notes = await repository.watchLivingNotes().first;

      expect(notes.map((n) => n.id), [viva]);
    });
  });
}
