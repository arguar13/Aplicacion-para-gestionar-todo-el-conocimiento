import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/services/reference_codec.dart';
import 'package:sinapsis/features/reference/presentation/reference_presentation.dart';
import 'package:sinapsis/features/vault/domain/entities/merge_conflict.dart';
import 'package:sinapsis/features/vault/presentation/screens/merge_conflicts_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Cómo se nombran y se leen los datos bibliográficos (F15): los tipos de obra,
/// los roles, la exactitud de la fecha y, sobre todo, una referencia entera en
/// un conflicto de fusión.
void main() {
  final es = AppLocalizationsEs();
  final en = AppLocalizationsEn();

  const garcia = PersonName(family: 'García Márquez', given: 'Gabriel');

  final full = ReferenceData(
    type: ReferenceType.book,
    contributors: const [
      Contributor(name: garcia),
      Contributor(
        name: PersonName(family: 'Rabassa', given: 'Gregory'),
        role: ContributorRole.translator,
      ),
    ],
    publisher: 'Sudamericana',
    publisherPlace: 'Buenos Aires',
    edition: '2.ª ed.',
    pages: '45-67',
    doi: '10.1000/xyz123',
    accessedAt: DateTime(2026, 9, 5),
    publicationPrecision: PublicationPrecision.year,
  );

  group('los nombres', () {
    test('cada tipo de obra tiene el suyo, en los dos idiomas', () {
      for (final type in ReferenceType.values) {
        expect(type.label(es), isNotEmpty, reason: type.name);
        expect(type.label(en), isNotEmpty, reason: type.name);
      }
      expect(ReferenceType.primarySource.label(es), 'Fuente primaria');
      expect(ReferenceType.onlinePublication.label(en), 'Online publication');
    });

    test('cada exactitud de fecha tiene el suyo', () {
      for (final precision in PublicationPrecision.values) {
        expect(precision.label(es), isNotEmpty, reason: precision.name);
      }
      expect(PublicationPrecision.undated.label(es), 'Sin fecha');
    });

    test('cada rol nombra su lista de personas', () {
      expect(ContributorRole.author.listLabel(es), 'Autores');
      expect(ContributorRole.translator.listLabel(es), 'Traductores');
      expect(ContributorRole.editor.listLabel(en), 'Editors');
      expect(ContributorRole.director.listLabel(en), 'Directors');
    });
  });

  group('describeReference', () {
    test('una línea por dato, con su etiqueta', () {
      expect(
        describeReference(es, full),
        [
          'Tipo de obra: Libro',
          'Autores: García Márquez, Gabriel',
          'Traductores: Rabassa, Gregory',
          'Editorial: Sudamericana',
          'Lugar de publicación: Buenos Aires',
          'Edición: 2.ª ed.',
          'Páginas: 45-67',
          'DOI: 10.1000/xyz123',
          'Consultado el: 2026-09-05',
          'Exactitud de la fecha: Solo el año',
        ].join('\n'),
      );
    });

    test('en inglés', () {
      final text = describeReference(en, full);

      expect(text, contains('Type of work: Book'));
      expect(text, contains('Translators: Rabassa, Gregory'));
      expect(text, contains('Accessed on: 2026-09-05'));
    });

    test('solo dice lo que tiene', () {
      expect(
        describeReference(es, const ReferenceData(volume: '3')),
        'Volumen: 3',
      );
    });

    test('varias personas del mismo rol van juntas, en su orden', () {
      const reference = ReferenceData(
        contributors: [
          Contributor(name: garcia),
          Contributor(
            name: PersonName(family: 'Borges', given: 'Jorge Luis'),
          ),
        ],
      );

      expect(
        describeReference(es, reference),
        'Autores: García Márquez, Gabriel; Borges, Jorge Luis',
      );
    });

    test('sin ningún dato es vacío', () {
      expect(describeReference(es, const ReferenceData()), isEmpty);
    });
  });

  group('un conflicto de fusión', () {
    MergeConflict conflict() => MergeConflict(
      id: 'c1',
      itemId: 'a',
      itemTitle: 'Cien años de soledad',
      fieldName: EntryField.reference,
      kind: MergeConflictKind.field,
      local: const MergeConflictVersion(),
      incoming: const MergeConflictVersion(),
      detectedAt: DateTime(2026, 9, 21),
    );

    test('nombra el campo', () {
      expect(conflictFieldLabel(es, conflict()), 'Datos bibliográficos');
      expect(conflictFieldLabel(en, conflict()), 'Bibliographic data');
    });

    test('muestra la referencia guardada uno por línea, no el JSON', () {
      final version = MergeConflictVersion(text: encodeReference(full));

      final text = conflictVersionText(es, conflict(), version);

      expect(text, describeReference(es, full));
      expect(text, isNot(contains('{')));
    });

    test('una versión sin referencia dice que está vacía', () {
      expect(
        conflictVersionText(es, conflict(), const MergeConflictVersion()),
        es.conflictsEmptyValue,
      );
    });

    test('un texto que no se entiende también', () {
      expect(
        conflictVersionText(
          es,
          conflict(),
          const MergeConflictVersion(text: 'esto no es JSON'),
        ),
        es.conflictsEmptyValue,
      );
    });
  });
}
