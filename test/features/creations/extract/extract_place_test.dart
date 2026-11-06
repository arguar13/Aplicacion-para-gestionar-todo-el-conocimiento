import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/domain/extract_place.dart';

/// El lugar al que va el lector único al abrirse (F46, paso 4): cómo viaja en
/// la dirección y qué hace con una que no es un lugar.
void main() {
  const place = ExtractPlace(documentId: '0190d7a1-roma', start: 120, end: 135);

  test('viaja en la dirección del lector y vuelve igual', () {
    final location = RoutePaths.extractReading(StudyCreationKind.fullText, [
      '0190d7a1-roma',
    ], at: place);
    final uri = Uri.parse(location);
    expect(uri.queryParameters['docs'], '0190d7a1-roma');
    expect(ExtractPlace.parse(uri.queryParameters['at']), place);
  });

  test('sin lugar, la dirección de siempre', () {
    final location = RoutePaths.extractReading(StudyCreationKind.fullText, [
      'a',
      'b',
    ]);
    final uri = Uri.parse(location);
    expect(uri.path, '/read/full_text');
    expect(uri.queryParameters, {'docs': 'a,b'});
  });

  test('se corta por el último «:», y el pedido no viaja: es de esta vez', () {
    expect(
      ExtractPlace.parse('doc:con:dos-puntos:3-9'),
      const ExtractPlace(documentId: 'doc:con:dos-puntos', start: 3, end: 9),
    );
    expect(
      ExtractPlace.parse(
        const ExtractPlace(documentId: 'd', start: 1, end: 2, visit: 7).query,
      ),
      const ExtractPlace(documentId: 'd', start: 1, end: 2),
    );
  });

  test('una dirección que no es un lugar abre desde el comienzo, sin '
      'fallar', () {
    for (final broken in [
      null,
      '',
      'sin-documento',
      ':1-2',
      'd:1',
      'd:a-b',
      'd:-1-4',
      'd:5-5',
      'd:9-3',
      'd:1-2-3',
    ]) {
      expect(ExtractPlace.parse(broken), isNull, reason: '«$broken»');
    }
  });

  test('dos pedidos del mismo lugar son distintos si su pedido lo es', () {
    const again = ExtractPlace(
      documentId: '0190d7a1-roma',
      start: 120,
      end: 135,
      visit: 1,
    );
    expect(again, isNot(place));
    expect(again.query, place.query);
  });
}
