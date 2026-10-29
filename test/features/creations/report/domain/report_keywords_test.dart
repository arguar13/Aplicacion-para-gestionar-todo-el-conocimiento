import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';
import 'package:sinapsis/features/creations/report/domain/report_order.dart';

import '../support/sample_reports.dart';

/// Las palabras clave que se buscan en un informe y el orden fijo de las
/// opciones de sus preguntas (F43, paso 10).
void main() {
  group('las palabras clave', () {
    test('las que no dicen nada solas no se pintan nunca', () {
      final keywords = ReportKeywords(const ['de', 'La', 'Sinaí', '', '  ']);
      expect(keywords.length, 1);
      expect(keywords.contains('sinai'), isTrue);
      expect(keywords.rangesIn('La ley de Dios en el Sinaí'), [(21, 26)]);
    });

    test('una frase más larga que cuatro palabras no se busca', () {
      final keywords = ReportKeywords(const ['uno dos tres cuatro cinco']);
      expect(keywords.isEmpty, isTrue);
    });

    test('dos con las mismas palabras son las mismas', () {
      expect(
        ReportKeywords(const ['Moisés', 'Sinaí']),
        ReportKeywords(const ['sinai', 'MOISES']),
      );
    });

    test('las más marcadas primero; a igual cuenta, las más largas', () {
      expect(
        rankReportKeywords({'mar': 3, 'alianza': 3, 'moises': 9, 'sinai': 1}),
        ['moises', 'alianza', 'mar', 'sinai'],
      );
      expect(
        rankReportKeywords({for (var i = 0; i < 400; i++) 'palabra$i': i}),
        hasLength(kReportKeywordsMax),
      );
    });
  });

  group('el orden de las opciones', () {
    test('mezcla, pero siempre igual para la misma pregunta', () {
      final question = sampleReport().sections.first.questions.first;
      final once = reportOptionOrder(question);
      expect(reportOptionOrder(question), once);
      expect(once.toSet(), question.options.toSet());
      // La correcta no queda siempre primera: con muchas preguntas, alguna
      // la pone en otro lugar.
      final firsts = <int>{
        for (var i = 0; i < 40; i++)
          reportOptionOrder(
            question.copyWith(question: '¿Pregunta $i?'),
          ).indexOf(question.correct),
      };
      expect(firsts.length, greaterThan(2));
    });

    test('las letras', () {
      expect(
        [for (var i = 0; i < 5; i++) reportOptionLetter(i)],
        ['A', 'B', 'C', 'D', 'E'],
      );
    });
  });
}
