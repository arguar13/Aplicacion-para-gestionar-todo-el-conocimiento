import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_canonical_text.dart';

import '../support/sample_reports.dart';

/// El texto de un informe (F45, paso 8c): lo que se lee de él como un solo
/// texto, con dónde está cada parte —el título, la bajada, las secciones,
/// sus bloques, el glosario, las preguntas y sus opciones—, para escribir
/// notas sobre sus pedazos.
void main() {
  group('el texto, de punta a punta', () {
    test('en el orden del informe, cada parte con lo que se ve —sin '
        '«**» ni «*»— y un renglón en blanco entre una y otra', () {
      final text = ReportText.of(sampleReport());
      final parts = [for (final part in text.parts) part.text];
      expect(parts.take(8), [
        'Éxodo: liberación y alianza',
        'De la esclavitud en Egipto a la Alianza del Sinaí.',
        'Introducción',
        'El libro del Éxodo cuenta cómo Moisés guía al pueblo fuera de Egipto.',
        'La esclavitud y el llamado.',
        'Las plagas y la salida.',
        'El paso del mar.',
        'La llegada al Sinaí.',
      ]);
      // Después de los bloques, las preguntas con sus opciones, en el orden
      // guardado y no en el mezclado.
      expect(parts.skip(8).take(6), [
        '¿Quién guía al pueblo fuera de Egipto?',
        'Moisés',
        'Aarón',
        'Josué',
        'El Faraón',
        '¿A dónde llega el pueblo?',
      ]);
      expect(text.content, parts.join(ReportText.separator));
      for (final part in text.parts) {
        expect(text.content.substring(part.start, part.end), part.text);
      }
    });

    test('dónde está cada parte, por su lugar', () {
      final text = ReportText.of(sampleReport());
      expect(
        text.partAt(const ReportTextPlace.title())?.text,
        'Éxodo: liberación y alianza',
      );
      expect(
        text.partAt(const ReportTextPlace.subtitle())?.text,
        'De la esclavitud en Egipto a la Alianza del Sinaí.',
      );
      expect(
        text.partAt(const ReportTextPlace.sectionTitle(1))?.text,
        'Moisés y el Faraón',
      );
      expect(
        text.partAt(const ReportTextPlace.block(1, 0))?.text,
        'Las plagas',
      );
      expect(
        text.partAt(const ReportTextPlace.block(1, 3))?.text,
        'Dejá ir a mi pueblo.',
      );
      expect(
        text.partAt(const ReportTextPlace.block(1, 4))?.text,
        'El Faraón endurece su corazón una y otra vez.',
      );
      expect(
        text.partAt(const ReportTextPlace.question(0, 1))?.text,
        '¿A dónde llega el pueblo?',
      );
      expect(
        text.partAt(const ReportTextPlace.option(0, 0, 3))?.text,
        'El Faraón',
      );
      expect(text.partAt(const ReportTextPlace.option(0, 0, 4)), isNull);
      expect(text.partAt(const ReportTextPlace.block(2, 1)), isNull);
    });

    test('el glosario: el término y su definición, cada uno su parte', () {
      final text = ReportText.of(sampleGlossary());
      expect(text.partAt(const ReportTextPlace.term(1, 1))?.text, 'Moisés');
      expect(
        text.partAt(const ReportTextPlace.definition(1, 1))?.text,
        'Quien guía al pueblo.',
      );
    });

    test('lo vacío no es parte: un título de sección que la IA no puso, una '
        'bajada que no hay', () {
      final text = ReportText.of(
        const Report(
          title: 'Informe',
          sections: [ReportSection(title: '  ', body: 'Un párrafo.')],
        ),
      );
      expect(
        [for (final part in text.parts) part.place],
        const [ReportTextPlace.title(), ReportTextPlace.block(0, 0)],
      );
      expect(text.content, 'Informe\n\nUn párrafo.');
    });

    test('el mismo informe da siempre el mismo texto: el lugar de cada nota '
        'no cambia', () {
      expect(
        ReportText.of(sampleReport()).content,
        ReportText.of(sampleReport()).content,
      );
    });

    test('solo las preguntas y las opciones son del interactivo', () {
      expect(const ReportTextPlace.question(0, 0).interactiveOnly, isTrue);
      expect(const ReportTextPlace.option(0, 0, 1).interactiveOnly, isTrue);
      expect(const ReportTextPlace.block(0, 0).interactiveOnly, isFalse);
      expect(const ReportTextPlace.sectionTitle(0).interactiveOnly, isFalse);
    });
  });

  group('de una posición a su parte', () {
    final text = ReportText.of(sampleReport());
    final intro = text.partAt(const ReportTextPlace.sectionTitle(0))!;
    final firstBlock = text.partAt(const ReportTextPlace.block(0, 0))!;

    test('la parte que la tiene; en el separador o afuera, ninguna', () {
      expect(text.partContaining(intro.start), intro);
      expect(text.partContaining(intro.end - 1), intro);
      expect(text.partContaining(intro.end), isNull);
      expect(text.partContaining(intro.end + 1), isNull);
      expect(text.partContaining(firstBlock.start), firstBlock);
      expect(text.partContaining(-1), isNull);
      expect(text.partContaining(text.content.length), isNull);
    });

    test('la primera que muestra algo de un tramo: si empieza en un '
        'separador, la siguiente', () {
      expect(text.firstPartOf(intro.start + 2, firstBlock.end), intro);
      expect(text.firstPartOf(intro.end, firstBlock.end), firstBlock);
      expect(text.firstPartOf(intro.end, intro.end + 1), isNull);
      expect(text.firstPartOf(5, 5), isNull);
    });

    test('las que toca un tramo, en orden', () {
      expect(
        text.partsTouching(intro.start + 3, firstBlock.start + 4).toList(),
        [intro, firstBlock],
      );
      expect(text.partsTouching(intro.end, firstBlock.start), isEmpty);
    });

    test('un tramo recortado a una parte, contado desde su comienzo', () {
      expect(ReportText.clip(intro, intro.start - 3, intro.start + 5), (0, 5));
      expect(ReportText.clip(intro, intro.start + 2, intro.end + 9), (
        2,
        intro.text.length,
      ));
      expect(ReportText.clip(intro, intro.end, intro.end + 3), isNull);
      expect(ReportText.clip(intro, intro.start - 4, intro.start), isNull);
    });
  });
}
