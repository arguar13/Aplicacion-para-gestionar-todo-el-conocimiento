import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/bibtex_entry.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/reference/domain/services/bibtex/bibtex_writer.dart';

BibtexEntry _entry({
  String? title,
  ReferenceType? type,
  String? citationKey,
  List<Contributor> contributors = const [],
  int? year,
}) => BibtexEntry(
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
  group('writeBibtex — la clave', () {
    test('conserva la clave que ya traía la referencia', () {
      final text = writeBibtex([_entry(title: 'T', citationKey: 'garcia1967')]);

      expect(text, contains('@misc{garcia1967,'));
    });

    test('sin clave, la arma con el apellido del primer autor y el año', () {
      final text = writeBibtex([
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

      expect(text, contains('@misc{turing1950,'));
    });

    test('sin autor ni clave, usa la primera palabra del título', () {
      final text = writeBibtex([_entry(title: 'Una obra sin firmar')]);

      expect(text, contains('@misc{una,'));
    });

    test('dos entradas con la misma clave se distinguen con una letra', () {
      final text = writeBibtex([
        _entry(title: 'Primera', citationKey: 'garcia1967'),
        _entry(title: 'Segunda', citationKey: 'garcia1967'),
      ]);

      expect(text, contains('@misc{garcia1967,'));
      expect(text, contains('@misc{garcia1967a,'));
    });

    test('una clave con acentos se pasa a ASCII, sin forzar minúsculas', () {
      final text = writeBibtex([
        _entry(title: 'T', citationKey: 'GonzálezPérez'),
      ]);

      expect(text, contains('@misc{GonzalezPerez,'));
    });
  });

  group('writeBibtex — los campos', () {
    test('el autor se escribe "Apellido, Nombre"', () {
      final text = writeBibtex([
        _entry(
          title: 'T',
          contributors: const [
            Contributor(
              name: PersonName(family: 'García', given: 'Juan'),
            ),
          ],
        ),
      ]);

      expect(text, contains('author = {García, Juan}'));
    });

    test('una institución se escribe entre llaves', () {
      final text = writeBibtex([
        _entry(
          title: 'T',
          contributors: const [
            Contributor(name: PersonName.institution('ACM')),
          ],
        ),
      ]);

      expect(text, contains('author = {{ACM}}'));
    });

    test('un tipo con equivalente nativo usa ese tipo de BibTeX', () {
      final text = writeBibtex([_entry(title: 'T', type: ReferenceType.book)]);

      expect(text, startsWith('@book{'));
    });

    test('un tipo sin equivalente nativo (documental) usa @misc', () {
      final text = writeBibtex([
        _entry(title: 'T', type: ReferenceType.documentary),
      ]);

      expect(text, startsWith('@misc{'));
      expect(text, contains('sinapsis-type = {documentary}'));
    });

    test('sin tipo, sinapsis-type queda en "none"', () {
      final text = writeBibtex([_entry(title: 'T')]);

      expect(text, contains('sinapsis-type = {none}'));
    });
  });
}
