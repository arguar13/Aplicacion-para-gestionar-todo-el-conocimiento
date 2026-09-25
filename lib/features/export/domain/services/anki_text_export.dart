import 'dart:convert';
import 'dart:typed_data';

import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';

/// El separador de un archivo de texto para Anki (F17, commit 5): el
/// camino alternativo al `.apkg` —D5, para cuando el paquete no sirve—.
enum AnkiTextFormat {
  tsv,
  csv;

  String get fileExtension => switch (this) {
    AnkiTextFormat.tsv => 'tsv',
    AnkiTextFormat.csv => 'csv',
  };

  String get _char => switch (this) {
    AnkiTextFormat.tsv => '\t',
    AnkiTextFormat.csv => ',',
  };

  /// El valor que entiende el encabezado `#separator:` de Anki —la
  /// palabra, no el carácter—, confirmado contra la documentación oficial
  /// (docs.ankiweb.net/importing/text-files.html: «Comma, Semicolon, Tab,
  /// Space, Pipe, Colon, or the corresponding literal characters»).
  String get _separatorHeaderValue => switch (this) {
    AnkiTextFormat.tsv => 'Tab',
    AnkiTextFormat.csv => 'Comma',
  };
}

/// El mismo mazo que arma `AnkiPackageBuilder` —tarjeta, subdeck ya
/// resuelto, procedencia ya resuelta (F17, commits 2/3)—, pero como texto
/// plano que Anki 2.1.54+ importa directo, con los encabezados `#` que su
/// manual documenta para eso: separador, que los campos son HTML, y en
/// qué columna está el mazo de cada fila. Sintaxis confirmada contra la
/// documentación oficial, no adivinada —queda a verificar en Anki real
/// recién en el commit 6 de este plan, junto con el resto—.
///
/// Los campos son HTML —así guarda Anki cualquier campo, sin importar el
/// camino de entrada, es lo mismo que ya vale para `AnkiPackageBuilder`—:
/// un salto de línea real adentro se escribe `<br>`, porque un separador
/// de línea real ahí partiría el archivo en una fila de más (una nota por
/// línea, sin excepción). Una tabulación real dentro de un campo —rara en
/// un front/back escrito a mano— se cambia por un espacio en el TSV, que
/// no tiene cómo escaparla; el CSV la deja pasar entre comillas.
///
/// Un solo modelo de columnas para TODO el archivo (F20): a diferencia del
/// `.apkg`, el formato de texto de Anki no admite dos formas de nota
/// distintas en un mismo archivo —el encabezado `#columns:` es uno solo—.
/// Una tarjeta `multipleChoice` sigue siendo fiel igual: sus distractores
/// reales entran en el mismo campo `Back`, como una lista legible, en vez
/// de perderse. No es "a medias" —nada de la información se descarta—,
/// solo un modelo de Anki propio menos que en el `.apkg`, que es donde de
/// verdad importa para repasar de forma interactiva.
Uint8List buildAnkiTextExport(
  List<AnkiCardExport> cards,
  AnkiTextFormat format,
) {
  final sep = format._char;
  final lines = <String>[
    '#separator:${format._separatorHeaderValue}',
    '#html:true',
    '#deck column:3',
    '#columns:${['Front', 'Back', 'Deck'].join(sep)}',
    for (final export in cards)
      [
        _field(export.card.front.trim(), format),
        _field(_backWithProvenance(export), format),
        _field(export.deckPath, format),
      ].join(sep),
  ];
  return Uint8List.fromList(utf8.encode(lines.join('\n')));
}

String _backWithProvenance(AnkiCardExport export) {
  final back = _backWithDistractors(export);
  final provenance = export.provenance;
  if (provenance == null || provenance.isEmpty) return back;
  return '$back<br><br>$provenance';
}

/// [AnkiCardExport.answer], con los distractores reales debajo —si
/// trae—, como una lista legible: mismo criterio de contenido que la
/// plantilla del segundo modelo de `AnkiPackageBuilder`, adaptado a un
/// único campo de texto.
String _backWithDistractors(AnkiCardExport export) {
  final answer = export.answer.trim();
  if (export.distractors.isEmpty) return answer;

  final distractors = export.distractors.map((d) => d.trim()).join('<br>');
  return '$answer<br><br>Otras opciones consideradas:<br>$distractors';
}

/// Un campo listo para una fila: sin saltos de línea reales, sin la
/// tabulación del propio TSV, y entre comillas si hace falta en el CSV.
String _field(String value, AnkiTextFormat format) {
  final singleLine = value.replaceAll('\r\n', '\n').replaceAll('\n', '<br>');
  return switch (format) {
    AnkiTextFormat.tsv => singleLine.replaceAll('\t', ' '),
    AnkiTextFormat.csv => _quoteIfNeeded(singleLine),
  };
}

/// RFC 4180: entre comillas si trae la coma o una comilla —ya sin saltos
/// de línea reales, normalizados antes de llegar acá—, doblando cada
/// comilla que ya traía.
String _quoteIfNeeded(String value) {
  if (!value.contains(',') && !value.contains('"')) return value;
  return '"${value.replaceAll('"', '""')}"';
}
