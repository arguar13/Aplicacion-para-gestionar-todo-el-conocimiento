import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';

/// Una página de la sección «Texto» de un documento procesado, ubicada: dónde
/// está en el texto propio y, si todavía es la de la fuente letra por letra,
/// dónde está en la fuente.
@immutable
class ProcessedTextPage {
  const ProcessedTextPage({
    required this.partId,
    required this.start,
    required this.end,
    this.source,
  });

  final String partId;

  /// `[start, end)` en el texto propio: las páginas una detrás de la otra.
  final int start;
  final int end;

  /// Dónde está en la fuente, si es una copia sin editar.
  final ProcessedAnchor? source;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is ProcessedTextPage &&
      other.partId == partId &&
      other.start == start &&
      other.end == end &&
      other.source == source;

  @override
  int get hashCode => Object.hash(partId, start, end, source);
}

/// Cómo se corresponden el texto propio de un documento procesado y el de su
/// fuente (decisión I): lo que deja que una oración estudiada en el procesado
/// lleve a la fuente, y que una copiada de la fuente se ubique en el texto
/// propio. Pura.
///
/// Hay dos formas de texto propio:
///
/// - **Las páginas** de su sección «Texto», una detrás de la otra. Una página
///   copiada sin editar dice dónde está en la fuente; una editada, no.
/// - **El texto de la fuente**, cuando el procesado no tiene sección «Texto»
///   pero sí la copia del original: es el mismo texto, con las mismas
///   posiciones.
@immutable
class ProcessedStudyLayout {
  /// Con sección «Texto»: [pages], en orden.
  ProcessedStudyLayout.pages(List<ProcessedTextPage> pages)
    : pages = List.unmodifiable(pages),
      sourceRenditionId = null,
      _bySource = List.unmodifiable(
        pages.where((p) => p.source != null).toList()
          ..sort((a, b) => a.source!.start.compareTo(b.source!.start)),
      );

  /// Sin sección «Texto»: el texto propio es el de la forma [renditionId] de la
  /// fuente.
  const ProcessedStudyLayout.source(String renditionId)
    : pages = const [],
      sourceRenditionId = renditionId,
      _bySource = const [];

  final List<ProcessedTextPage> pages;

  /// La forma de la fuente cuyo texto es el propio, sin sección «Texto».
  final String? sourceRenditionId;

  final List<ProcessedTextPage> _bySource;

  /// Si el texto propio son las páginas de la sección «Texto».
  bool get hasPages => sourceRenditionId == null;

  /// Cuánto mide el texto propio con páginas.
  int get pagesLength => pages.isEmpty ? 0 : pages.last.end;

  /// Dónde está en el texto propio lo que marca [anchor] en la fuente, o
  /// `null` si no está ahí letra por letra: cae en una página editada, en
  /// otra forma de la fuente, o fuera de las páginas.
  ProcessedSpan? ownOf(ProcessedAnchor anchor) {
    if (!hasPages) {
      return anchor.renditionId == sourceRenditionId
          ? ProcessedSpan(start: anchor.start, end: anchor.end)
          : null;
    }
    final first = _pageAtSource(anchor.renditionId, anchor.start);
    final last = _pageAtSource(anchor.renditionId, anchor.end - 1);
    if (first == null || last == null) return null;
    final start = first.start + anchor.start - first.source!.start;
    final end = last.start + anchor.end - last.source!.start;
    // Entre una y otra no puede haber una página editada ni un salto.
    return end - start == anchor.end - anchor.start
        ? ProcessedSpan(start: start, end: end)
        : null;
  }

  /// Dónde está en la fuente el tramo `[start, end)` del texto propio, o `null`
  /// si no es de la fuente letra por letra.
  ProcessedAnchor? sourceOf(int start, int end) {
    if (end <= start) return null;
    if (!hasPages) {
      return ProcessedAnchor(
        renditionId: sourceRenditionId!,
        start: start,
        end: end,
      );
    }
    final first = _pageAtOwn(start);
    final last = _pageAtOwn(end - 1);
    final a = first?.source;
    final b = last?.source;
    if (first == null || last == null || a == null || b == null) return null;
    if (a.renditionId != b.renditionId) return null;
    final sourceStart = a.start + start - first.start;
    final sourceEnd = b.start + end - last.start;
    return sourceEnd - sourceStart == end - start
        ? ProcessedAnchor(
            renditionId: a.renditionId,
            start: sourceStart,
            end: sourceEnd,
          )
        : null;
  }

  ProcessedTextPage? _pageAtOwn(int offset) {
    var low = 0;
    var high = pages.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final page = pages[mid];
      if (offset < page.start) {
        high = mid - 1;
      } else if (offset >= page.end) {
        low = mid + 1;
      } else {
        return page;
      }
    }
    return null;
  }

  ProcessedTextPage? _pageAtSource(String renditionId, int offset) {
    var low = 0;
    var high = _bySource.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final page = _bySource[mid];
      final source = page.source!;
      if (offset < source.start) {
        high = mid - 1;
      } else if (offset >= source.end) {
        low = mid + 1;
      } else {
        return source.renditionId == renditionId ? page : null;
      }
    }
    return null;
  }
}
