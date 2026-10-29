import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';
import 'package:sinapsis/features/creations/report/domain/report_markup.dart';

/// El poco Markdown que escribe la IA en una sección (F43, paso 10) y las
/// palabras clave de las fuentes encima (decisión 85).
void main() {
  group('los bloques', () {
    test('párrafos, viñetas con sangría, listas, subtítulos y citas', () {
      final blocks = parseReportBody(
        'Un párrafo\npartido a mano.\n\n'
        '- Una viñeta\n'
        '  que sigue abajo.\n'
        '  - Una de adentro.\n'
        '* Otra con asterisco.\n'
        '• Otra con punto.\n\n'
        '1. Primero.\n'
        '2) Segundo.\n\n'
        '### **Un subtítulo**\n'
        '> Una cita.\n'
        'Otro párrafo.',
      );
      expect(blocks, [
        const ReportParagraph([ReportInline('Un párrafo partido a mano.')]),
        const ReportBullet([ReportInline('Una viñeta que sigue abajo.')]),
        const ReportBullet([ReportInline('Una de adentro.')], level: 1),
        const ReportBullet([ReportInline('Otra con asterisco.')]),
        const ReportBullet([ReportInline('Otra con punto.')]),
        const ReportBullet([ReportInline('Primero.')], number: 1),
        const ReportBullet([ReportInline('Segundo.')], number: 2),
        const ReportSubheading([ReportInline('Un subtítulo')]),
        const ReportQuote([ReportInline('Una cita.')]),
        const ReportParagraph([ReportInline('Otro párrafo.')]),
      ]);
    });

    test('una negrita al principio de la línea no es una viñeta', () {
      expect(parseReportBody('**Moisés** guía al pueblo.'), [
        const ReportParagraph([
          ReportInline('Moisés', bold: true),
          ReportInline(' guía al pueblo.'),
        ]),
      ]);
    });

    test('las líneas en Windows y las vacías no cuentan', () {
      expect(parseReportBody('Uno.\r\n\r\n\r\n- Dos.\r\n'), [
        const ReportParagraph([ReportInline('Uno.')]),
        const ReportBullet([ReportInline('Dos.')]),
      ]);
      expect(parseReportBody('  \n\n'), isEmpty);
    });
  });

  group('los pedazos', () {
    test('negrita e itálica, con sus dos marcas', () {
      expect(parseReportInlines('El **Éxodo** y el *Faraón* y __Aarón__.'), [
        const ReportInline('El '),
        const ReportInline('Éxodo', bold: true),
        const ReportInline(' y el '),
        const ReportInline('Faraón', italic: true),
        const ReportInline(' y '),
        const ReportInline('Aarón', bold: true),
        const ReportInline('.'),
      ]);
      expect(parseReportInlines('Un _énfasis_ suelto.'), [
        const ReportInline('Un '),
        const ReportInline('énfasis', italic: true),
        const ReportInline(' suelto.'),
      ]);
    });

    test('una marca sin su pareja queda como está', () {
      expect(parseReportInlines('5 * 3 = 15 y snake_case_name'), [
        const ReportInline('5 * 3 = 15 y snake_case_name'),
      ]);
      expect(parseReportInlines('**sin cerrar'), [
        const ReportInline('**sin cerrar'),
      ]);
    });

    test('la itálica dentro de una negrita pierde sus marcas', () {
      expect(parseReportInlines('**El *gran* éxodo**'), [
        const ReportInline('El gran éxodo', bold: true),
      ]);
    });
  });

  group('las palabras clave', () {
    final keywords = ReportKeywords(const ['Moisés', 'Mar Rojo', 'mar']);

    test('se marcan sin mayúsculas ni tildes, palabra entera', () {
      expect(
        withReportKeywords(
          parseReportInlines('MOISES cruza el **mar Rojo**; Moisésito no.'),
          keywords,
        ),
        [
          const ReportInline('MOISES', keyword: true),
          const ReportInline(' cruza el '),
          const ReportInline('mar Rojo', bold: true, keyword: true),
          const ReportInline('; Moisésito no.'),
        ],
      );
    });

    test('la frase más larga gana, y sin palabras clave nada cambia', () {
      expect(keywords.rangesIn('El mar. El Mar Rojo.'), [(3, 6), (11, 19)]);
      final plain = parseReportInlines('Moisés y el mar.');
      expect(withReportKeywords(plain, ReportKeywords.empty), same(plain));
    });

    test('los bloques de una sección, con sus palabras clave', () {
      expect(reportBlocksWithKeywords('- Moisés guía.', keywords), [
        const ReportBullet([
          ReportInline('Moisés', keyword: true),
          ReportInline(' guía.'),
        ]),
      ]);
    });
  });
}
