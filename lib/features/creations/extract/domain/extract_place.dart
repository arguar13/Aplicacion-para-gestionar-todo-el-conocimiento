import 'package:flutter/foundation.dart';

/// Un lugar del texto propio de un documento procesado al que el lector único
/// (F45, mejora 12; F47, paso 1) va apenas se abre, y que resalta un momento:
/// el título de un capítulo que se tocó en el Índice (F46, paso 4, decisión
/// C).
///
/// `[start, end)` son posiciones del texto propio —sus páginas de «Texto» una
/// detrás de la otra—, las mismas con que el lector arma sus bloques y con
/// que va a una nota de «Notas (N)»: por eso llega por el mismo camino.
@immutable
class ExtractPlace {
  const ExtractPlace({
    required this.documentId,
    required this.start,
    required this.end,
    this.visit = 0,
  }) : assert(start >= 0 && end > start, 'un tramo con algo adentro');

  /// El documento donde está; si el lector no lo muestra, no va a ningún
  /// lado.
  final String documentId;
  final int start;
  final int end;

  /// Qué pedido es. Dos pedidos de ir al mismo lugar son distintos si su
  /// [visit] lo es: al costado del Índice, el lector ya está abierto, y tocar
  /// otra vez el mismo capítulo —después de haber leído más abajo— vuelve a
  /// llevar ahí. No viaja en la dirección: la pantalla propia del lector se
  /// abre una vez por pedido.
  final int visit;

  /// Cómo viaja en la dirección del lector (`at=`): `documento:inicio-fin`.
  /// Las claves de los documentos no llevan `:` —son UUID—, y se corta por
  /// el último, así que tampoco importaría.
  String get query => '$documentId:$start-$end';

  /// Lo que dice [query], o `null` si no es un lugar: una dirección escrita a
  /// mano o vieja abre el lector desde el comienzo, sin fallar.
  static ExtractPlace? parse(String? query) {
    if (query == null) return null;
    final colon = query.lastIndexOf(':');
    if (colon <= 0) return null;
    final range = query.substring(colon + 1).split('-');
    if (range.length != 2) return null;
    final start = int.tryParse(range.first);
    final end = int.tryParse(range.last);
    if (start == null || end == null || start < 0 || end <= start) return null;
    return ExtractPlace(
      documentId: query.substring(0, colon),
      start: start,
      end: end,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExtractPlace &&
      other.documentId == documentId &&
      other.start == start &&
      other.end == end &&
      other.visit == visit;

  @override
  int get hashCode => Object.hash(documentId, start, end, visit);

  @override
  String toString() => 'ExtractPlace($query #$visit)';
}
