import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_text_export.dart';

/// El camino alternativo al `.apkg` (F17, commit 5): puro, sobre lo que ya
/// resolvió el caso de uso —sin base, sin bindings—.
void main() {
  Flashcard card({
    String id = 'c1',
    String front = 'Pregunta',
    String back = 'Respuesta',
  }) => Flashcard(
    id: id,
    itemId: 'item-1',
    front: front,
    back: back,
    dueAt: DateTime(2024),
    createdAt: DateTime(2024),
  );

  AnkiCardExport export({
    Flashcard? card_,
    String deckPath = 'Sinapsis::Sin tema',
    String? answer,
    String? provenance,
    List<String> distractors = const [],
  }) {
    final resolved = card_ ?? card();
    return AnkiCardExport(
      card: resolved,
      deckPath: deckPath,
      answer: answer ?? resolved.back,
      provenance: provenance,
      distractors: distractors,
    );
  }

  String decode(AnkiTextFormat format, List<AnkiCardExport> cards) =>
      utf8.decode(buildAnkiTextExport(cards, format));

  group('encabezados de Anki 2.1.54+', () {
    test('TSV: separador Tab', () {
      final lines = decode(AnkiTextFormat.tsv, const []).split('\n');

      expect(lines[0], '#separator:Tab');
      expect(lines[1], '#html:true');
      expect(lines[2], '#deck column:3');
      expect(lines[3], '#columns:Front\tBack\tDeck');
    });

    test('CSV: separador Comma', () {
      final lines = decode(AnkiTextFormat.csv, const []).split('\n');

      expect(lines[0], '#separator:Comma');
      expect(lines[3], '#columns:Front,Back,Deck');
    });

    test('sin tarjetas, igual arma un archivo válido, solo encabezados', () {
      final text = decode(AnkiTextFormat.tsv, const []);

      expect(text.split('\n'), hasLength(4));
    });
  });

  group('una fila por tarjeta', () {
    test('Front, Back y el subdeck ya resuelto, en ese orden', () {
      final text = decode(AnkiTextFormat.tsv, [
        export(deckPath: 'Sinapsis::Historia::Roma'),
      ]);

      expect(text, contains('Pregunta\tRespuesta\tSinapsis::Historia::Roma'));
    });

    test('varias tarjetas son varias filas, en el mismo orden', () {
      final text = decode(AnkiTextFormat.tsv, [
        export(
          card_: card(front: 'p1', back: 'r1'),
        ),
        export(
          card_: card(id: 'c2', front: 'p2', back: 'r2'),
        ),
      ]);
      final rows = text.split('\n').skip(4).toList();

      expect(rows[0], startsWith('p1\tr1\t'));
      expect(rows[1], startsWith('p2\tr2\t'));
    });

    test('con procedencia, va debajo de la respuesta, igual que el .apkg', () {
      final text = decode(AnkiTextFormat.tsv, [
        export(provenance: '(Autor, 2020)'),
      ]);

      expect(text, contains('Respuesta<br><br>(Autor, 2020)'));
    });

    test('sin procedencia, la respuesta queda igual que siempre', () {
      final text = decode(AnkiTextFormat.tsv, [export()]);

      expect(text, contains('Pregunta\tRespuesta\t'));
    });
  });

  group('un salto de línea real rompería el archivo: se escapa', () {
    test('en el front y en el back, como <br> —Anki guarda HTML siempre—', () {
      final text = decode(AnkiTextFormat.tsv, [
        export(
          card_: card(front: 'línea 1\nlínea 2', back: 'r'),
        ),
      ]);

      expect(text, contains('línea 1<br>línea 2'));
      expect(text.split('\n'), hasLength(5));
    });

    test(r'un \r\n también se escapa, sin dejar un \r suelto', () {
      final text = decode(AnkiTextFormat.tsv, [
        export(
          card_: card(front: 'a\r\nb', back: 'r'),
        ),
      ]);

      expect(text, contains('a<br>b'));
      expect(text, isNot(contains('\r')));
    });
  });

  group('una tabulación real dentro de un campo, en TSV', () {
    test('se cambia por un espacio: el formato no puede escaparla', () {
      final text = decode(AnkiTextFormat.tsv, [
        export(
          card_: card(front: 'con\ttab', back: 'r'),
        ),
      ]);
      final row = text.split('\n')[4];

      expect(row.split('\t'), ['con tab', 'r', 'Sinapsis::Sin tema']);
    });
  });

  group('una coma real dentro de un campo, en CSV', () {
    test('el campo entero va entre comillas', () {
      final text = decode(AnkiTextFormat.csv, [
        export(
          card_: card(front: 'con, coma', back: 'r'),
        ),
      ]);

      expect(text, contains('"con, coma",r,'));
    });

    test('una comilla real adentro se dobla', () {
      final text = decode(AnkiTextFormat.csv, [
        export(
          card_: card(front: 'con "comillas"', back: 'r'),
        ),
      ]);

      expect(text, contains('"con ""comillas""",r,'));
    });

    test('sin coma ni comilla, no hace falta encerrarlo', () {
      final text = decode(AnkiTextFormat.csv, [export()]);

      expect(text, contains('Pregunta,Respuesta,'));
    });
  });

  group('una tarjeta de opción múltiple (F20, commit 9)', () {
    test('sus distractores reales van debajo de la respuesta, en el mismo '
        'campo Back —el archivo de texto no admite un modelo aparte—', () {
      final text = decode(AnkiTextFormat.tsv, [
        // card.back queda vacío en una tarjeta multipleChoice de verdad
        // (FlashcardRepositoryImpl.createMultipleChoice); answer es lo
        // que el caso de uso resuelve aparte, de la opción correcta.
        export(
          card_: card(back: ''),
          answer: 'Respuesta',
          distractors: const ['Distractor uno', 'Distractor dos'],
        ),
      ]);

      expect(
        text,
        contains(
          'Pregunta\tRespuesta<br><br>Otras opciones '
          'consideradas:<br>Distractor uno<br>Distractor dos\t',
        ),
      );
    });

    test('con procedencia, va después de los distractores', () {
      final text = decode(AnkiTextFormat.tsv, [
        export(distractors: const ['Distractor uno'], provenance: '(Cita)'),
      ]);

      expect(
        text,
        contains(
          'Pregunta\tRespuesta<br><br>Otras opciones '
          'consideradas:<br>Distractor uno<br><br>(Cita)\t',
        ),
      );
    });

    test('sin ningún distractor, el campo queda igual que siempre', () {
      final text = decode(AnkiTextFormat.tsv, [export()]);

      expect(text, contains('Pregunta\tRespuesta\t'));
    });
  });
}
