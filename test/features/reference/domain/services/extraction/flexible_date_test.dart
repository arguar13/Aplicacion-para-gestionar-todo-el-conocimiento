import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/flexible_date.dart';

void main() {
  test('solo el ano', () {
    final date = parseFlexibleDate('2023');
    expect(date?.date, DateTime(2023));
    expect(date?.precision, PublicationPrecision.year);
  });

  test('ano y mes con guion', () {
    final date = parseFlexibleDate('2023-05');
    expect(date?.date, DateTime(2023, 5));
    expect(date?.precision, PublicationPrecision.month);
  });

  test('fecha completa con guion', () {
    final date = parseFlexibleDate('2023-05-12');
    expect(date?.date, DateTime(2023, 5, 12));
    expect(date?.precision, PublicationPrecision.day);
  });

  test('fecha completa con barra', () {
    final date = parseFlexibleDate('2023/05/12');
    expect(date?.date, DateTime(2023, 5, 12));
    expect(date?.precision, PublicationPrecision.day);
  });

  test('con hora y huso al final, que se ignoran', () {
    final date = parseFlexibleDate('2023-05-12T10:30:00+02:00');
    expect(date?.date, DateTime(2023, 5, 12));
    expect(date?.precision, PublicationPrecision.day);
  });

  test('un 31 de febrero se recorta al mes', () {
    final date = parseFlexibleDate('2023-02-31');
    expect(date?.date, DateTime(2023, 2));
    expect(date?.precision, PublicationPrecision.month);
  });

  test('un mes que no existe se recorta al ano', () {
    final date = parseFlexibleDate('2023-13');
    expect(date?.date, DateTime(2023));
    expect(date?.precision, PublicationPrecision.year);
  });

  test('lo que no empieza con un ano no es una fecha', () {
    expect(parseFlexibleDate('mayo de 2023'), isNull);
    expect(parseFlexibleDate(''), isNull);
  });
}
