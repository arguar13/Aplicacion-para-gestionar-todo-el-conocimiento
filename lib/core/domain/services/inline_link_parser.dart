import 'package:sinapsis/core/domain/entities/content_block.dart';

/// Un `[[Título]]` tal como aparece escrito en un texto.
class InlineLinkMention {
  const InlineLinkMention({required this.title, required this.normalizedTitle});

  /// El título como se escribió, recortado: lo que se le muestra a quien
  /// mira y con lo que se crea la nota si el enlace estaba roto.
  final String title;

  /// El título para COMPARAR: recortado y en minúsculas. Es la regla con la
  /// que los enlaces se resuelven desde que existen —"Roma" y "roma" son el
  /// mismo destino— y no se cambió al persistirlos: pasar a ignorar también
  /// los acentos habría resuelto enlaces que hasta hoy no resolvían.
  final String normalizedTitle;
}

/// El contenido de un enlace no puede contener `]]`: sin esa guarda, un
/// `[[]]` vacío seguido de otro enlace más adelante se "enganchaba" a través
/// de los cierres y devolvía como título todo lo que quedaba en el medio.
final _linkPattern = RegExp(r'\[\[((?:(?!\]\]).)+?)\]\]');

/// La forma de un título con la que se compara contra otro.
String normalizeLinkTitle(String title) => title.trim().toLowerCase();

/// Los enlaces `[[ ]]` de [text], en el orden en que aparecen y sin repetir el
/// mismo destino: si "Roma" aparece dos veces, cuenta una.
///
/// Un `[[ ]]` vacío o de puros espacios no es un enlace.
List<InlineLinkMention> extractInlineLinks(String text) {
  final seen = <String>{};
  final mentions = <InlineLinkMention>[];

  for (final match in _linkPattern.allMatches(text)) {
    final title = match.group(1)!.trim();
    final normalized = normalizeLinkTitle(title);
    if (normalized.isEmpty || !seen.add(normalized)) continue;
    mentions.add(InlineLinkMention(title: title, normalizedTitle: normalized));
  }
  return mentions;
}

/// Los enlaces de cualquier bloque de [blocks], sin repetir destino entre
/// bloques.
List<InlineLinkMention> extractInlineLinksFromBlocks(
  List<ContentBlock> blocks,
) {
  final seen = <String>{};
  final mentions = <InlineLinkMention>[];

  for (final block in blocks) {
    for (final mention in extractInlineLinks(block.text)) {
      if (seen.add(mention.normalizedTitle)) mentions.add(mention);
    }
  }
  return mentions;
}
