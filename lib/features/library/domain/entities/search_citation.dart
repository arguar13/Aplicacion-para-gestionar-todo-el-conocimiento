/// El carácter que abre una coincidencia dentro de [SearchCitation.snippet].
///
/// Del área de uso privado de Unicode: un carácter que ningún texto trae y que
/// la base puede intercalar sin ambigüedad. Marcar con `<b>` o `*` confundiría
/// una coincidencia con texto de la fuente que ya trae esas marcas.
final String kSnippetOpen = String.fromCharCode(0xE000);

/// El que la cierra.
final String kSnippetClose = String.fromCharCode(0xE001);

/// Un tramo de un fragmento, con o sin la coincidencia resaltada.
class SnippetPart {
  const SnippetPart(this.text, {required this.highlighted});

  final String text;

  /// `true` si es lo que se buscó.
  final bool highlighted;
}

/// DÓNDE de una fuente está lo que se buscó: el fragmento, y la posición que
/// permite volver a él —el minuto de una transcripción, la página de un
/// documento, los caracteres del texto—.
///
/// Es lo que hace que un resultado de búsqueda diga "en el minuto 12:40" y no
/// solo "está en este video": la búsqueda encuentra chunks, no elementos
/// enteros, y cada chunk sabe dónde empieza.
class SearchCitation {
  const SearchCitation({
    required this.itemId,
    required this.chunkId,
    required this.snippet,
    required this.charStart,
    required this.charEnd,
    this.startMs,
    this.endMs,
    this.pageNumber,
  });

  final String itemId;
  final String chunkId;

  /// Un trozo del chunk alrededor de lo que se encontró, con las coincidencias
  /// entre [kSnippetOpen] y [kSnippetClose]. Usar [parts] para mostrarlo.
  final String snippet;

  /// Dónde está el chunk en el texto de la fuente, en unidades UTF-16: las
  /// mismas coordenadas que usan los resaltados y la vista de lectura.
  final int charStart;
  final int charEnd;

  /// Cuándo empieza el chunk en el audio o el video de origen, si la fuente
  /// trae marcas de tiempo.
  final int? startMs;
  final int? endMs;

  /// En qué página está, si la fuente la trae.
  final int? pageNumber;

  /// El fragmento partido en tramos, para dibujar la coincidencia resaltada.
  List<SnippetPart> get parts {
    final result = <SnippetPart>[];
    var highlighted = false;
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) return;
      result.add(SnippetPart(buffer.toString(), highlighted: highlighted));
      buffer.clear();
    }

    for (final unit in snippet.runes) {
      final char = String.fromCharCode(unit);
      if (char == kSnippetOpen) {
        flush();
        highlighted = true;
      } else if (char == kSnippetClose) {
        flush();
        highlighted = false;
      } else {
        buffer.write(char);
      }
    }
    flush();
    return result;
  }

  /// El minuto donde está, como `12:40` o `1:02:03`; `null` si la fuente no
  /// trae marcas de tiempo.
  String? get timestamp {
    final ms = startMs;
    if (ms == null) return null;
    final totalSeconds = ms ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final ss = seconds.toString().padLeft(2, '0');
    if (hours == 0) return '$minutes:$ss';
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
}
