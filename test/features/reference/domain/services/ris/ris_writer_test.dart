import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/imported_reference.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/reference/domain/services/ris/ris_writer.dart';

ImportedReference _entry({
  String? title,
  ReferenceType? type,
  String? citationKey,
  List<Contributor> contributors = const [],
  int? year,
}) => ImportedReference(
  title: title,
  publishedAt: year == null ? null : DateTime(year),
  publicationPrecision: year == null ? null : PublicationPrecision.year,
  reference: ReferenceData(
    type: type,
    citationKey: citationKey,
    contributors: contributors,
  ),
);

void main() {
  group('writeRis — la estructura', () {
    test('empieza en TY y termina en ER', () {
      final text = writeRis([_entry(title: 'T', type: ReferenceType.book)]);

      expect(text, startsWith('TY  - BOOK'));
      expect(text.trim(), endsWith('ER  -'));
    });

    test('un tipo sin equivalente nativo (documental) usa GEN', () {
      final text = writeRis([
        _entry(title: 'T', type: ReferenceType.documentary),
      ]);

      expect(text, contains('TY  - GEN'));
      expect(text, contains('G1  - documentary'));
    });

    test('sin tipo, G1 queda en "none"', () {
      final text = writeRis([_entry(title: 'T')]);

      expect(text, contains('G1  - none'));
    });
  });

  group('writeRis — el ID', () {
    test('conserva la clave que ya traía la referencia', () {
      final text = writeRis([_entry(title: 'T', citationKey: 'garcia1967')]);

      expect(text, contains('ID  - garcia1967'));
    });

    test('sin clave, la arma con el apellido del autor y el año', () {
      final text = writeRis([
        _entry(
          title: 'T',
          year: 1950,
          contributors: const [
            Contributor(
              name: PersonName(family: 'Turing', given: 'Alan'),
            ),
          ],
        ),
      ]);

      expect(text, contains('ID  - turing1950'));
    });

    test('dos entradas con la misma clave se distinguen con una letra', () {
      final text = writeRis([
        _entry(title: 'Primera', citationKey: 'mismo'),
        _entry(title: 'Segunda', citationKey: 'mismo'),
      ]);

      expect(text, contains('ID  - mismo\n'));
      expect(text, contains('ID  - mismoa\n'));
    });
  });

  group('writeRis — los nombres', () {
    test('el autor se escribe "Apellido, Nombre"', () {
      final text = writeRis([
        _entry(
          title: 'T',
          contributors: const [
            Contributor(
              name: PersonName(family: 'García', given: 'Juan'),
            ),
          ],
        ),
      ]);

      expect(text, contains('AU  - García, Juan'));
    });

    test('una institución se escribe con una coma al final', () {
      final text = writeRis([
        _entry(
          title: 'T',
          contributors: const [
            Contributor(name: PersonName.institution('ACM')),
          ],
        ),
      ]);

      expect(text, contains('AU  - ACM,'));
    });
  });
}
