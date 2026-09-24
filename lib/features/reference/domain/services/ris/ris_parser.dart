import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/imported_reference.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/services/bibliographic_identifiers.dart';

/// Una entrada de un `.ris` que el analizador no supo convertir: un tipo
/// (`TY`) que no está entre los nueve de la app. Se informa y se salta, en
/// vez de adivinar (D4), igual que en BibTeX.
class RisSkippedEntry {
  const RisSkippedEntry({required this.id, required this.type});

  final String? id;
  final String type;
}

/// Lo que salió de leer un archivo `.ris` entero: las entradas que se
/// entendieron y las que no.
class RisParseResult {
  const RisParseResult({required this.entries, required this.skipped});

  final List<ImportedReference> entries;
  final List<RisSkippedEntry> skipped;
}

/// Lee un archivo `.ris` entero (F15, commit 14), con las mismas garantías
/// que el analizador de BibTeX: un registro empieza en `TY  - …` y termina en
/// `ER  - `, y una línea que no trae su propia etiqueta se suma a la del
/// campo anterior —la forma en que un título o un resumen quedan partidos
/// en varias líneas—. Sin macros ni llaves que resolver: RIS no las tiene.
///
/// RIS no define un juego de caracteres propio como BibTeX —no hace falta
/// nada como `decodeLatexAccents`—, y el nombre de una persona ya viene
/// «Apellido, Nombre», sin la ambigüedad que sí tiene BibTeX sin coma.
RisParseResult parseRis(String source) {
  final lines = source.split(RegExp(r'\r\n|\r|\n'));
  final entries = <ImportedReference>[];
  final skipped = <RisSkippedEntry>[];

  Map<String, List<String>>? current;
  String? lastTag;

  void flush() {
    final fields = current;
    current = null;
    lastTag = null;
    if (fields == null || !fields.containsKey('TY')) return;

    final type = fields['TY']!.first.trim().toUpperCase();
    final entry = _toEntry(type: type, fields: fields);
    if (entry == null) {
      skipped.add(RisSkippedEntry(id: fields['ID']?.first.trim(), type: type));
    } else {
      entries.add(entry);
    }
  }

  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) continue;

    final match = _tagLine.firstMatch(line);
    if (match != null) {
      final tag = match.group(1)!.toUpperCase();
      final value = (match.group(2) ?? '').trim();

      if (tag == 'TY') flush();
      current ??= {};
      current!.putIfAbsent(tag, () => []).add(value);
      lastTag = tag;

      if (tag == 'ER') flush();
    } else if (current != null && lastTag != null) {
      final values = current![lastTag]!;
      values[values.length - 1] = '${values.last} ${line.trim()}'.trim();
    }
  }
  flush(); // Por si el archivo termina sin `ER` (se toma lo que había).

  return RisParseResult(entries: entries, skipped: skipped);
}

/// Una línea con etiqueta: dos letras o dígitos, un guion (con o sin el
/// espaciado de dos espacios habitual) y el valor hasta el final.
final _tagLine = RegExp(r'^([A-Za-z][A-Za-z0-9])\s*-\s?(.*)$');

/// Los códigos de `TY` que la app entiende, y a cuál de los nueve tipos
/// propios corresponden (D4). `CPAPER` entra como artículo con el
/// contenedor del congreso, igual que `@inproceedings` en BibTeX; `CONF`
/// —el volumen entero de las actas— entra como libro.
const _typeFromRis = {
  'JOUR': ReferenceType.article,
  'JFULL': ReferenceType.article,
  'INPR': ReferenceType.article,
  'ABST': ReferenceType.article,
  'BOOK': ReferenceType.book,
  'CONF': ReferenceType.book,
  'CHAP': ReferenceType.chapter,
  'CPAPER': ReferenceType.article,
  'THES': ReferenceType.thesis,
  'WEB': ReferenceType.website,
  'ELEC': ReferenceType.website,
  'EJOUR': ReferenceType.website,
  'RPRT': ReferenceType.other,
  'GEN': ReferenceType.other,
};

ImportedReference? _toEntry({
  required String type,
  required Map<String, List<String>> fields,
}) {
  final mapped = _typeFromRis[type];
  if (mapped == null) return null;

  String? one(String tag) {
    final value = fields[tag]?.first.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  // `G1`/`G2` son campos propios —ver [writeRis]— que ningún otro lector de
  // RIS usa ni entiende, y que solo importan para la ida y vuelta propia.
  final typeHint = one('G1');
  final refType = typeHint == null
      ? mapped
      : (typeHint == 'none' ? null : (_typeFromName(typeHint) ?? mapped));

  final contributors = <Contributor>[];
  for (final raw in fields['AU'] ?? const <String>[]) {
    final name = _parseRisName(raw);
    if (name != null) contributors.add(Contributor(name: name));
  }
  for (final raw in fields['A2'] ?? const <String>[]) {
    final name = _parseRisName(raw);
    if (name != null) {
      contributors.add(Contributor(name: name, role: ContributorRole.editor));
    }
  }

  final (publishedAt, precision) = _dateFrom(one('PY'), one('G2'));
  final sn = one('SN');

  return ImportedReference(
    title: one('TI') ?? one('T1'),
    url: one('UR'),
    publishedAt: publishedAt,
    publicationPrecision: precision,
    reference: ReferenceData(
      type: refType,
      contributors: contributors,
      containerTitle: one('T2'),
      publisher: one('PB'),
      publisherPlace: one('CY'),
      edition: one('ET'),
      volume: one('VL'),
      issue: one('IS'),
      pages: _pagesFrom(one('SP'), one('EP')),
      isbn: sn == null ? null : normalizeIsbn(sn),
      issn: sn == null ? null : normalizeIssn(sn),
      doi: one('DO'),
      accessedAt: _fullDateFrom(one('DA')),
      citationKey: one('ID'),
    ),
  );
}

/// `Apellido, Nombre` —la forma que pide RIS—, o una institución si la
/// línea termina en coma sin nada detrás («World Health Organization,»,
/// la convención con la que EndNote marca un autor corporativo—.
PersonName? _parseRisName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.endsWith(',')) {
    final institution = trimmed.substring(0, trimmed.length - 1).trim();
    return institution.isEmpty ? null : PersonName.institution(institution);
  }

  final comma = trimmed.indexOf(',');
  if (comma < 0) return PersonName(family: trimmed);

  final family = trimmed.substring(0, comma).trim();
  if (family.isEmpty) return null;
  return PersonName(family: family, given: trimmed.substring(comma + 1).trim());
}

ReferenceType? _typeFromName(String name) {
  for (final type in ReferenceType.values) {
    if (type.name == name) return type;
  }
  return null;
}

String? _pagesFrom(String? start, String? end) {
  if (start == null && end == null) return null;
  if (start != null && end != null) return '$start-$end';
  return start ?? end;
}

(DateTime?, PublicationPrecision?) _dateFrom(String? py, String? undated) {
  if (undated != null) return (null, PublicationPrecision.undated);
  if (py == null) return (null, null);

  final parts = py.split('/');
  final year = int.tryParse(parts.elementAtOrNull(0) ?? '');
  if (year == null) return (null, null);

  final month = int.tryParse(parts.elementAtOrNull(1) ?? '');
  final day = int.tryParse(parts.elementAtOrNull(2) ?? '');

  if (month != null && day != null) {
    return (DateTime(year, month, day), PublicationPrecision.day);
  }
  if (month != null) return (DateTime(year, month), PublicationPrecision.month);
  return (DateTime(year), PublicationPrecision.year);
}

/// El formato `AAAA/MM/DD/` de RIS, exigiendo los tres números —a
/// diferencia de `PY`, que también vale solo con el año—: es la misma
/// exactitud que pide `_parseIsoDate` para `urldate` en BibTeX.
DateTime? _fullDateFrom(String? da) {
  if (da == null) return null;
  final parts = da.split('/');
  final year = int.tryParse(parts.elementAtOrNull(0) ?? '');
  final month = int.tryParse(parts.elementAtOrNull(1) ?? '');
  final day = int.tryParse(parts.elementAtOrNull(2) ?? '');
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}
