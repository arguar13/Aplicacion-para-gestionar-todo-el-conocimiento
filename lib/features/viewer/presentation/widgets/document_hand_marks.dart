import 'package:sinapsis/core/domain/entities/highlight.dart';

// Los resaltados a mano de la persona (F38) sobre un documento real —el PDF,
// la página web archivada—: en qué orden se pintan. El color, sobre papel, es
// el de `HighlightPalette.onPaper` y su línea, `HighlightPalette.lineOnPaper`.

/// Los resaltados de la persona de abajo hacia arriba: el más nuevo, encima,
/// donde dos se pisan. A igual fecha, por id, para que el orden no cambie
/// entre pantallas.
List<Highlight> stackedHighlights(Iterable<Highlight> highlights) {
  final stacked = highlights.toList()
    ..sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
  return stacked;
}
