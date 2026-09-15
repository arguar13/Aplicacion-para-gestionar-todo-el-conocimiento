import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/services/speech_segmentation.dart';

void main() {
  test('texto vacío no produce ningún fragmento', () {
    expect(splitIntoSpeechSegments(''), isEmpty);
    expect(splitIntoSpeechSegments('   '), isEmpty);
  });

  test('separa oraciones seguidas de un espacio', () {
    final segments = splitIntoSpeechSegments(
      'Primera oración. Segunda oración. Tercera oración.',
    );

    expect(segments, [
      'Primera oración.',
      'Segunda oración.',
      'Tercera oración.',
    ]);
  });

  test('también separa con signos de exclamación e interrogación', () {
    final segments = splitIntoSpeechSegments('¿Qué tal? ¡Muy bien! Genial.');

    expect(segments, ['¿Qué tal?', '¡Muy bien!', 'Genial.']);
  });

  test('junta saltos de línea sueltos dentro de la misma oración', () {
    final segments = splitIntoSpeechSegments('Una oración\nen dos líneas.');

    expect(segments, ['Una oración\nen dos líneas.']);
  });

  test('una oración sin punto final igual queda como un fragmento', () {
    final segments = splitIntoSpeechSegments('Sin punto final');

    expect(segments, ['Sin punto final']);
  });

  test('una oración mucho más larga que el tope se corta en el espacio más '
      'cercano, sin partir palabras', () {
    final longSentence = List.generate(100, (i) => 'palabra$i').join(' ');

    final segments = splitIntoSpeechSegments('$longSentence.');

    expect(segments.length, greaterThan(1));
    for (final segment in segments) {
      expect(segment.length, lessThanOrEqualTo(400));
    }
    // Ninguna palabra quedó partida al medio: unir todo de nuevo
    // reconstruye exactamente el texto original.
    expect(segments.join(' '), '$longSentence.');
  });
}
