import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/anki_import/data/services/sqlite_anki_package_reader.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/export/data/services/anki_package_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';

import '../../../../support/anki_package_fixture.dart';
import '../../../../support/rss_sampler.dart';

/// Ida y vuelta: lo que Sinapsis exporta con `AnkiPackageBuilder` lo tiene que
/// poder leer `SqliteAnkiPackageReader` sin perder nada de lo que importa.
void main() {
  const builder = AnkiPackageBuilder();
  const reader = SqliteAnkiPackageReader();

  Flashcard card({
    required String id,
    required String front,
    required String back,
    int repetitions = 0,
    double easeFactor = 2.5,
    int intervalDays = 0,
    DateTime? dueAt,
    FlashcardKind kind = FlashcardKind.freeRecall,
  }) {
    final now = DateTime.now();
    return Flashcard(
      id: id,
      itemId: 'item-1',
      front: front,
      back: back,
      dueAt: dueAt ?? now,
      createdAt: now,
      repetitions: repetitions,
      easeFactor: easeFactor,
      intervalDays: intervalDays,
      kind: kind,
    );
  }

  AnkiCardExport export(
    Flashcard card, {
    String deckPath = 'Sinapsis::Sin tema',
    String? provenance,
    String? answer,
    List<String> distractors = const [],
  }) => AnkiCardExport(
    card: card,
    deckPath: deckPath,
    answer: answer ?? card.back,
    provenance: provenance,
    distractors: distractors,
  );

  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<AnkiImportedPackage> roundTrip(List<AnkiCardExport> cards) async =>
      reader.readBytes(await builder.build(cards));

  test('las tarjetas, sus mazos y su calendario vuelven iguales', () async {
    final start = today();
    final cards = [
      export(
        card(id: 'nueva', front: '¿Capital de Italia?', back: 'Roma'),
        deckPath: 'Sinapsis::Geografía',
      ),
      export(
        card(
          id: 'madura',
          front: '¿Año de la caída de Roma de Occidente?',
          back: '476',
          repetitions: 6,
          easeFactor: 2.36,
          intervalDays: 45,
          dueAt: DateTime(start.year, start.month, start.day + 12),
        ),
        deckPath: 'Sinapsis::Historia::Roma',
      ),
      export(
        card(
          id: 'joven',
          front: '¿Qué es la fotosíntesis?',
          back: 'El proceso por el que las plantas fabrican su alimento.',
          repetitions: 1,
          intervalDays: 1,
          dueAt: DateTime(start.year, start.month, start.day + 1),
        ),
        deckPath: 'Sinapsis::Biología',
      ),
    ];

    final package = await roundTrip(cards);

    expect(package.cardCount, 3);
    expect(package.skippedCards, 0);
    expect(package.decks.map((d) => d.path).toSet(), {
      'Sinapsis::Geografía',
      'Sinapsis::Historia::Roma',
      'Sinapsis::Biología',
    });

    AnkiImportedCard byGuid(String id) =>
        package.cards.singleWhere((c) => c.guid == id);

    final fresh = byGuid('nueva');
    expect(fresh.kind, AnkiCardKind.basic);
    expect(fresh.front, '¿Capital de Italia?');
    expect(fresh.back, 'Roma');
    expect(fresh.schedule.isNew, isTrue);
    expect(fresh.schedule.repetitions, 0);

    final mature = byGuid('madura');
    expect(mature.front, '¿Año de la caída de Roma de Occidente?');
    expect(mature.back, '476');
    expect(mature.schedule.state, AnkiCardState.review);
    expect(mature.schedule.repetitions, 6);
    expect(mature.schedule.intervalDays, 45);
    expect(mature.schedule.easeFactor, 2.36);
    expect(
      mature.schedule.dueAt,
      DateTime(start.year, start.month, start.day + 12),
    );
    expect(package.decks.firstWhere((d) => d.cards.contains(mature)).levels, [
      'Sinapsis',
      'Historia',
      'Roma',
    ]);

    final young = byGuid('joven');
    expect(young.schedule.intervalDays, 1);
    expect(young.schedule.repetitions, 1);
    expect(
      young.schedule.dueAt,
      DateTime(start.year, start.month, start.day + 1),
    );
  });

  test(
    'una tarjeta vencida vuelve para hoy, no con un vencimiento negativo',
    () async {
      final start = today();
      final package = await roundTrip([
        export(
          card(
            id: 'atrasada',
            front: 'a',
            back: 'b',
            repetitions: 3,
            intervalDays: 9,
            dueAt: DateTime(start.year, start.month, start.day - 20),
          ),
        ),
      ]);

      final schedule = package.cards.single.schedule;
      expect(
        schedule.dueAt!.isAfter(start.subtract(const Duration(days: 1))),
        isTrue,
      );
      expect(
        schedule.dueAt!.isAfter(start.add(const Duration(days: 2))),
        isFalse,
      );
    },
  );

  test('la procedencia exportada queda debajo del dorso', () async {
    final package = await roundTrip([
      export(
        card(id: 'c', front: 'P', back: 'R'),
        provenance: 'Fuente: Livio, Ab urbe condita, p. 12',
      ),
    ]);

    expect(
      package.cards.single.back,
      'R\n\nFuente: Livio, Ab urbe condita, p. 12',
    );
  });

  test('la opción múltiple no se degrada a una tarjeta básica', () async {
    final package = await roundTrip([
      export(
        card(
          id: 'mc',
          front: '¿Quién fundó Roma?',
          back: '',
          kind: FlashcardKind.multipleChoice,
        ),
        answer: 'Rómulo',
        distractors: ['Eneas', 'Julio César'],
      ),
    ]);

    final imported = package.cards.single;
    expect(imported.kind, AnkiCardKind.multipleChoice);
    expect(imported.front, '¿Quién fundó Roma?');
    expect(imported.back, 'Rómulo');
    expect(imported.distractors, ['Eneas', 'Julio César']);
  });

  test('Unicode y textos con HTML sensible se conservan', () async {
    final package = await roundTrip([
      export(
        card(
          id: 'u',
          front: '¿Qué significa 🍍 en "piña"? <b> & ñandú',
          back: 'Привет 漢字',
        ),
      ),
    ]);

    final imported = package.cards.single;
    // El builder no escapa HTML: `<b>` es negrita para Anki, igual que acá.
    expect(imported.front, contains('"piña"'));
    expect(imported.front, contains('🍍'));
    expect(imported.front, contains('& ñandú'));
    expect(imported.back, 'Привет 漢字');
  });

  test('mil tarjetas en varios mazos', () async {
    final cards = [
      for (var i = 0; i < 1000; i++)
        export(
          card(id: 'c$i', front: 'Pregunta $i', back: 'Respuesta $i'),
          deckPath: 'Sinapsis::Tema ${i % 7}',
        ),
    ];

    final package = await roundTrip(cards);

    expect(package.cardCount, 1000);
    expect(package.decks, hasLength(7));
    expect(package.cards.map((c) => c.guid).toSet(), hasLength(1000));
  });

  test('sin tarjetas: un mazo vacío con aviso, no un error', () async {
    final package = await roundTrip(const []);

    expect(package.decks, isEmpty);
    expect(package.warnings, isNotEmpty);
  });

  test('desde un archivo en disco', () async {
    final dir = Directory.systemTemp.createTempSync('sinapsis-anki-t-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'sinapsis.apkg'))
      ..writeAsBytesSync(
        await builder.build([export(card(id: 'x', front: 'F', back: 'B'))]),
      );

    final package = await reader.readFile(file.path);

    expect(package.cards.single.front, 'F');
  });

  test(
    'un .apkg con 150 MB de medios se lee sin pasar por la memoria',
    () async {
      final dir = Directory.systemTemp.createTempSync('sinapsis-anki-t-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'con_medios.apkg');

      final collectionFile = Uint8List.fromList(
        collectionBytes(
          crt: 1772323200,
          models: [basicModel(10)],
          decks: [deck(1, 'Default')],
          notes: const [
            FixtureNote(id: 100, modelId: 10, fields: ['a', 'b']),
          ],
          cards: const [FixtureCard(id: 1000, noteId: 100)],
        ),
      );
      // El fixture se arma en otro aislado: medir la memoria en el mismo infla
      // el punto de partida con lo que se armó.
      await Isolate.run(() {
        // El medio: 150 MB sin comprimir, generados por tandas.
        final bigPath = p.join(p.dirname(path), 'gigante');
        final big = File(bigPath).openSync(mode: FileMode.write);
        final chunk = Uint8List(1024 * 1024);
        for (var i = 0; i < 150; i++) {
          big.writeFromSync(chunk);
        }
        big.closeSync();
        ZipFileEncoder()
          ..create(path)
          ..addArchiveFile(
            ArchiveFile.bytes('collection.anki21', collectionFile),
          )
          ..addArchiveFile(
            ArchiveFile.bytes('media', '{"0":"gigante.mp3"}'.codeUnits),
          )
          ..addArchiveFile(
            ArchiveFile.stream('0', InputFileStream(bigPath))
              ..compression = CompressionType.none,
          )
          ..closeSync();
      });
      expect(File(path).lengthSync(), greaterThan(150 * 1024 * 1024));

      final sampler = await RssSampler.start(
        measure: MemoryMeasure.privateCommit,
      );
      final package = await reader.readFile(path);
      final growth = await sampler.stop();

      expect(package.cardCount, 1);
      expect(package.packageMediaFiles, 1);
      expect(
        growth,
        lessThan(60 * 1024 * 1024),
        reason:
            'la memoria creció ${growth ~/ (1024 * 1024)} MB leyendo el mazo',
      );
    },
  );
}
