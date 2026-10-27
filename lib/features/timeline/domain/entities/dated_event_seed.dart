import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/services/temporal_expressions.dart';

/// Lo que ya se sabe de un hecho fechado antes de abrir su formulario (F40,
/// paso 5): de qué documento sale, la cita y, si la cita trae una fecha, la
/// fecha. Lo demás —el título que falta, confirmar la fecha— lo pone la
/// persona.
///
/// Es un punto de partida y no un `DatedEventInput` porque todavía no se puede
/// guardar: le falta, por lo menos, el título.
@immutable
class DatedEventSeed {
  const DatedEventSeed({
    this.itemId,
    this.title = '',
    this.date,
    this.end,
    this.renditionId,
    this.startOffset,
    this.endOffset,
    this.excerpt,
  });

  /// Lo seleccionado en un texto: `[start, end)` de [content], el contenido
  /// entero de la forma de texto [renditionId] del elemento [itemId].
  ///
  /// La cita queda puesta tal cual está en el texto —con las mismas
  /// posiciones con que se guardan los resaltados y las tarjetas— y, si trae
  /// una fecha, viene cargada (y su fin, si es un rango). Si trae varias, la
  /// primera: la persona puede cambiarla en el formulario.
  ///
  /// El título sugerido es la propia cita cuando es corta —cabe en una línea
  /// del eje—; una cita larga lo deja vacío, porque un renglón cortado a la
  /// mitad no es un título.
  factory DatedEventSeed.fromQuote({
    required String itemId,
    required String renditionId,
    required String content,
    required int start,
    required int end,
  }) {
    assert(
      start >= 0 && end > start && end <= content.length,
      'La cita [$start, $end) no cae dentro de un texto de ${content.length}',
    );
    final excerpt = content.substring(start, end);
    final found = findTemporalExpressions(excerpt);
    final first = found.isEmpty ? null : found.first;
    return DatedEventSeed(
      itemId: itemId,
      title: _suggestedTitle(excerpt),
      date: first?.date,
      end: first?.endDate,
      renditionId: renditionId,
      startOffset: start,
      endOffset: end,
      excerpt: excerpt,
    );
  }

  /// El elemento del que sale, o `null` si la persona todavía lo elige.
  final String? itemId;

  final String title;

  final HistoricalDate? date;
  final HistoricalDate? end;

  /// La cita: el texto, dónde está y cómo se leía.
  final String? renditionId;
  final int? startOffset;
  final int? endOffset;
  final String? excerpt;

  /// Si trae una cita con su posición: entonces el elemento no se cambia, que
  /// es de donde sale.
  bool get hasQuote => renditionId != null && startOffset != null;

  /// Lo más largo que puede ser una cita para servir de título.
  static const maxSuggestedTitle = 80;

  static String _suggestedTitle(String excerpt) {
    final collapsed = excerpt.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.length <= maxSuggestedTitle ? collapsed : '';
  }

  @override
  bool operator ==(Object other) =>
      other is DatedEventSeed &&
      other.itemId == itemId &&
      other.title == title &&
      other.date == date &&
      other.end == end &&
      other.renditionId == renditionId &&
      other.startOffset == startOffset &&
      other.endOffset == endOffset &&
      other.excerpt == excerpt;

  @override
  int get hashCode => Object.hash(
    itemId,
    title,
    date,
    end,
    renditionId,
    startOffset,
    endOffset,
    excerpt,
  );
}
