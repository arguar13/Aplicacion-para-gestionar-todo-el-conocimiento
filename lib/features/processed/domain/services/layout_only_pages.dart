import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/services/tidy_check.dart';

/// Una página del texto de un documento procesado, lo justo para saber si se
/// cambiaron sus palabras: su id, su texto y su tramo en el texto de la
/// fuente. Viaja a otro hilo con un libro entero.
typedef PageToCompare = ({String id, String content, int start, int end});

/// Las páginas de `input.pages` —del texto de un documento procesado— que se
/// editaron sin cambiar ni una palabra de la fuente: solo los renglones, los
/// cortes y los títulos, lo que hace la IA al ordenar el texto (F45, decisión
/// B). Cada una, por su id, con la huella de su texto ([pageFingerprint]).
///
/// Es la comprobación de siempre de lo ordenado (`checkTidiedText`), contra
/// el tramo de la fuente de cada página y con los encabezados y los pies que
/// se repiten en `input.source`. Una página cuyas palabras cambió la persona —una
/// letra, una palabra de más o de menos— no está: es suya, y nada la toca.
///
/// Sirve antes de volver a extraer la fuente (F45, paso 4): después, su texto
/// viejo ya no está, y no hay contra qué comparar.
Map<String, String> layoutOnlyPages(
  ({String source, List<PageToCompare> pages}) input,
) {
  final source = input.source;
  final margins = TidyMargins.of(source);
  return {
    for (final page in input.pages)
      if (page.start >= 0 &&
          page.end <= source.length &&
          page.start < page.end &&
          checkTidiedText(
            source.substring(page.start, page.end),
            page.content,
            margins: margins,
          ).isFaithful)
        page.id: pageFingerprint(page.content),
  };
}

/// Las páginas de [parts] que vale la pena comparar: las de la sección
/// «Texto», copiadas de la fuente y editadas, con su tramo de la fuente. Una
/// copia sin editar no hace falta —«Actualizar» ya la renueva— y una escrita
/// en el procesado no es de la fuente.
List<PageToCompare> editedCopiedPages(List<ProcessedPart> parts) => [
  for (final part in parts)
    if (part.section == ProcessedSection.text &&
        part.origin == ProcessedPartOrigin.copied &&
        !part.isPristineCopy)
      if (part.anchor case final anchor?)
        (
          id: part.id,
          content: part.content,
          start: anchor.start,
          end: anchor.end,
        ),
];

/// La huella del texto de una página: si cambió desde que se miró. Estable
/// entre una sesión y otra, a diferencia de `String.hashCode`.
String pageFingerprint(String content) =>
    sha256.convert(utf8.encode(content)).toString();
