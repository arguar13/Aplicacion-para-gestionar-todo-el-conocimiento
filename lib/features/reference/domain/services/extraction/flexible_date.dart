import 'package:sinapsis/core/domain/entities/publication_date.dart';

/// Una fecha con la exactitud con que se leyó, antes de guardarse.
typedef ParsedFlexibleDate = ({DateTime date, PublicationPrecision precision});

/// Lee una fecha de las que trae un `<meta>` o un bloque XMP: «2023»,
/// «2023-05», «2023-05-12», «2023/05/12», con o sin hora y huso al final
/// —que se ignoran, porque la cita nunca llega a la hora—. `null` si
/// [raw] no empieza con un año.
///
/// No es tan estricta como `_parseIsoDate` de `ReferenceDraft`: un extractor
/// recibe lo que trajo la página, no lo que alguien tipeó a mano, y rechazar
/// «2023/05/12» perdería una fecha real por el separador.
ParsedFlexibleDate? parseFlexibleDate(String raw) {
  final match = RegExp(
    r'^(\d{4})(?:[-/](\d{1,2}))?(?:[-/](\d{1,2}))?',
  ).firstMatch(raw.trim());
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  if (year < 1 || year > 9999) return null;

  final monthText = match.group(2);
  if (monthText == null) {
    return (date: DateTime(year), precision: PublicationPrecision.year);
  }
  final month = int.parse(monthText);
  if (month < 1 || month > 12) {
    return (date: DateTime(year), precision: PublicationPrecision.year);
  }

  final dayText = match.group(3);
  if (dayText == null) {
    return (date: DateTime(year, month), precision: PublicationPrecision.month);
  }
  final day = int.parse(dayText);
  final date = DateTime(year, month, day);
  // `DateTime` corre el 31 de febrero al 3 de marzo: si el mes cambió, el día
  // no existía, y se guarda solo el mes.
  if (date.month != month) {
    return (date: DateTime(year, month), precision: PublicationPrecision.month);
  }
  return (date: date, precision: PublicationPrecision.day);
}
