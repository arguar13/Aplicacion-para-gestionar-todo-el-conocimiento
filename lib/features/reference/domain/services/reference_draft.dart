import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/services/bibliographic_identifiers.dart';
import 'package:sinapsis/core/domain/services/person_name_parser.dart';

/// Un dato de texto de la referencia que el formulario edita (F15).
enum ReferenceField {
  /// El libro, la revista o el sitio que contiene la obra.
  container,
  publisher,
  place,
  edition,
  volume,
  issue,
  pages,
  isbn,
  issn,
  doi,

  /// Cuándo se consultó, escrito «AAAA-MM-DD».
  accessed,
  citationKey,
}

/// Los datos que el formulario muestra para una obra de [type], en el orden en
/// que se piden: los que esa clase de obra usa. `null` —una obra sin tipo, que
/// todavía se está completando— muestra todos.
///
/// El formulario agrega, además, cualquier dato que la obra ya tenga aunque su
/// tipo no lo use: nunca se esconde lo que alguien cargó.
List<ReferenceField> fieldsFor(ReferenceType? type) => switch (type) {
  ReferenceType.book => const [
    ReferenceField.publisher,
    ReferenceField.place,
    ReferenceField.edition,
    ReferenceField.volume,
    ReferenceField.isbn,
    ReferenceField.doi,
    ReferenceField.citationKey,
  ],
  ReferenceType.chapter => const [
    ReferenceField.container,
    ReferenceField.publisher,
    ReferenceField.pages,
    ReferenceField.place,
    ReferenceField.edition,
    ReferenceField.volume,
    ReferenceField.isbn,
    ReferenceField.doi,
    ReferenceField.citationKey,
  ],
  ReferenceType.article => const [
    ReferenceField.container,
    ReferenceField.volume,
    ReferenceField.issue,
    ReferenceField.pages,
    ReferenceField.doi,
    ReferenceField.issn,
    ReferenceField.citationKey,
  ],
  ReferenceType.thesis => const [
    ReferenceField.publisher,
    ReferenceField.doi,
    ReferenceField.citationKey,
  ],
  ReferenceType.primarySource => const [
    ReferenceField.publisher,
    ReferenceField.place,
    ReferenceField.citationKey,
  ],
  ReferenceType.documentary => const [
    ReferenceField.publisher,
    ReferenceField.place,
    ReferenceField.citationKey,
  ],
  ReferenceType.website || ReferenceType.onlinePublication => const [
    ReferenceField.container,
    ReferenceField.publisher,
    ReferenceField.accessed,
    ReferenceField.citationKey,
  ],
  ReferenceType.other || null => ReferenceField.values,
};

/// Los pocos datos que se ven sin desplegar «Más datos»: los que el estilo pide
/// de esa clase de obra. El resto queda plegado.
List<ReferenceField> primaryFieldsFor(ReferenceType? type) => switch (type) {
  ReferenceType.chapter => const [
    ReferenceField.container,
    ReferenceField.publisher,
  ],
  ReferenceType.article => const [
    ReferenceField.container,
    ReferenceField.volume,
  ],
  ReferenceType.website ||
  ReferenceType.onlinePublication => const [ReferenceField.container],
  _ => const [ReferenceField.publisher],
};

/// Las clases de persona que se piden para una obra de [type], en el orden en
/// que se muestran. `null` pide todas.
List<ContributorRole> rolesFor(ReferenceType? type) => switch (type) {
  ReferenceType.book => const [
    ContributorRole.author,
    ContributorRole.editor,
    ContributorRole.translator,
  ],
  ReferenceType.chapter => const [
    ContributorRole.author,
    ContributorRole.editor,
    ContributorRole.translator,
  ],
  ReferenceType.documentary => const [
    ContributorRole.director,
    ContributorRole.author,
  ],
  ReferenceType.other || null => const [
    ContributorRole.author,
    ContributorRole.editor,
    ContributorRole.translator,
    ContributorRole.director,
  ],
  _ => const [ContributorRole.author],
};

/// Una persona tal como se está escribiendo en el formulario.
class PersonDraft {
  const PersonDraft({
    required this.role,
    required this.text,
    this.isInstitution = false,
  });

  /// La persona [contributor] como se escribe en el formulario.
  factory PersonDraft.of(Contributor contributor) => PersonDraft(
    role: contributor.role,
    text: contributor.name.label,
    isInstitution: contributor.name.isInstitution,
  );

  /// Lo que hizo en la obra.
  final ContributorRole role;

  /// Lo que se escribió: «Apellido, Nombre», o el nombre entero de una
  /// institución.
  final String text;

  /// Si es una institución: no se parte en apellido y nombre.
  final bool isInstitution;

  /// La persona que el texto nombra, o `null` si está vacío.
  Contributor? toContributor({String? personId}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final name = isInstitution
        ? PersonName.institution(trimmed)
        : parseName(trimmed)?.name;
    if (name == null) return null;
    return Contributor(name: name, role: role, personId: personId);
  }
}

/// Qué está mal en lo que se escribió, por dato.
enum ReferenceDraftError {
  doi,
  isbn,
  issn,

  /// La fecha de publicación no existe —el 31 de febrero, un mes sin año—.
  date,

  /// La fecha de consulta no es «AAAA-MM-DD».
  accessed,
}

/// Lo que el formulario de la referencia tiene escrito (F15): los datos, sus
/// personas y la fecha, todavía como texto.
///
/// Es lo que se valida y se convierte antes de guardar. Vive aparte de la
/// pantalla para poder probarlo sin ella: qué se pide de cada tipo de obra,
/// cómo se lee una fecha a medias, qué identificador no sirve.
class ReferenceDraft {
  const ReferenceDraft({
    this.type,
    this.people = const [],
    this.fields = const {},
    this.year = '',
    this.month = '',
    this.day = '',
    this.undated = false,
  });

  /// El borrador de una referencia ya guardada y de la fecha de publicación de
  /// su fuente.
  factory ReferenceDraft.of(ReferenceData reference, DateTime? publishedAt) {
    final date = PublicationDate.fromStored(
      publishedAt,
      reference.publicationPrecision,
    );
    final accessed = reference.accessedAt;
    return ReferenceDraft(
      type: reference.type,
      people: [for (final c in reference.contributors) PersonDraft.of(c)],
      fields: {
        ReferenceField.container: ?reference.containerTitle,
        ReferenceField.publisher: ?reference.publisher,
        ReferenceField.place: ?reference.publisherPlace,
        ReferenceField.edition: ?reference.edition,
        ReferenceField.volume: ?reference.volume,
        ReferenceField.issue: ?reference.issue,
        ReferenceField.pages: ?reference.pages,
        ReferenceField.isbn: ?reference.isbn,
        ReferenceField.issn: ?reference.issn,
        ReferenceField.doi: ?reference.doi,
        if (accessed != null) ReferenceField.accessed: isoDateText(accessed),
        ReferenceField.citationKey: ?reference.citationKey,
      },
      year: date.year?.toString() ?? '',
      month: date.month?.toString() ?? '',
      day: date.day?.toString() ?? '',
      undated: date.isUndated,
    );
  }

  final ReferenceType? type;
  final List<PersonDraft> people;

  /// Lo escrito en cada dato de texto; el que falta o está vacío es «nada».
  final Map<ReferenceField, String> fields;

  /// La fecha de publicación, escrita por partes: el año, el mes y el día.
  final String year;
  final String month;
  final String day;

  /// Si la obra no tiene fecha —a diferencia de una fecha que no se cargó—.
  final bool undated;

  String _text(ReferenceField field) => (fields[field] ?? '').trim();

  String? _nullable(ReferenceField field) {
    final text = _text(field);
    return text.isEmpty ? null : text;
  }

  /// Lo que está mal, por dato. Vacío si se puede guardar.
  Set<ReferenceDraftError> validate() {
    final errors = <ReferenceDraftError>{};
    if (_text(ReferenceField.doi).isNotEmpty &&
        normalizeDoi(_text(ReferenceField.doi)) == null) {
      errors.add(ReferenceDraftError.doi);
    }
    if (_text(ReferenceField.isbn).isNotEmpty &&
        normalizeIsbn(_text(ReferenceField.isbn)) == null) {
      errors.add(ReferenceDraftError.isbn);
    }
    if (_text(ReferenceField.issn).isNotEmpty &&
        normalizeIssn(_text(ReferenceField.issn)) == null) {
      errors.add(ReferenceDraftError.issn);
    }
    if (_text(ReferenceField.accessed).isNotEmpty &&
        _parseIsoDate(_text(ReferenceField.accessed)) == null) {
      errors.add(ReferenceDraftError.accessed);
    }
    if (!undated && _publication() == null) {
      errors.add(ReferenceDraftError.date);
    }
    return errors;
  }

  /// La fecha de publicación con su exactitud: `(fecha, exactitud)`, o `null`
  /// si lo escrito no es una fecha. Sin nada escrito y sin marcar «sin fecha»
  /// es una fecha desconocida —`(null, null)`—, que es válida: no se cargó.
  ({DateTime? date, PublicationPrecision? precision})? _publication() {
    final y = year.trim();
    final m = month.trim();
    final d = day.trim();
    if (y.isEmpty && m.isEmpty && d.isEmpty) {
      return (date: null, precision: null);
    }
    final yearNumber = int.tryParse(y);
    if (yearNumber == null || yearNumber < 1 || yearNumber > 9999) return null;
    if (m.isEmpty) {
      // Un día sin mes no es una fecha.
      return d.isEmpty
          ? (date: DateTime(yearNumber), precision: PublicationPrecision.year)
          : null;
    }
    final monthNumber = int.tryParse(m);
    if (monthNumber == null || monthNumber < 1 || monthNumber > 12) {
      return null;
    }
    if (d.isEmpty) {
      return (
        date: DateTime(yearNumber, monthNumber),
        precision: PublicationPrecision.month,
      );
    }
    final dayNumber = int.tryParse(d);
    if (dayNumber == null || dayNumber < 1) return null;
    final date = DateTime(yearNumber, monthNumber, dayNumber);
    // `DateTime` corre el 31 de febrero al 3 de marzo: si el mes cambió, el día
    // no existía.
    if (date.month != monthNumber) return null;
    return (date: date, precision: PublicationPrecision.day);
  }

  /// La fecha de publicación que se guarda en la fuente. Solo tiene sentido si
  /// [validate] no marca la fecha.
  DateTime? get publishedAt => undated ? null : _publication()?.date;

  /// La referencia que se guarda. Solo tiene sentido si [validate] no marca
  /// nada.
  ReferenceData build() => ReferenceData(
    type: type,
    contributors: [for (final person in people) ?person.toContributor()],
    containerTitle: _nullable(ReferenceField.container),
    publisher: _nullable(ReferenceField.publisher),
    publisherPlace: _nullable(ReferenceField.place),
    edition: _nullable(ReferenceField.edition),
    volume: _nullable(ReferenceField.volume),
    issue: _nullable(ReferenceField.issue),
    pages: _nullable(ReferenceField.pages),
    isbn: _nullable(ReferenceField.isbn),
    issn: _nullable(ReferenceField.issn),
    doi: _nullable(ReferenceField.doi),
    accessedAt: _parseIsoDate(_text(ReferenceField.accessed)),
    citationKey: _nullable(ReferenceField.citationKey),
    publicationPrecision: undated
        ? PublicationPrecision.undated
        : _publication()?.precision,
  );
}

/// La fecha como se escribe en el formulario: «2026-09-05».
String isoDateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Lee «AAAA-MM-DD»; `null` si no lo es o el día no existe.
DateTime? _parseIsoDate(String text) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}
