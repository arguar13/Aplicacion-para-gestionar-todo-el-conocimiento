import 'package:sinapsis/core/domain/entities/knowledge_item.dart';

/// Aplica lo que trajo un transformador sobre la versión ACTUAL del elemento.
///
/// El procesamiento puede tardar minutos —horas, con un video largo—, y
/// mientras tanto el usuario sigue usando el elemento: le pone etiquetas, lo
/// mueve de tema, le cambia el título. Guardar el resultado del transformador
/// tal cual devolvería el elemento a como estaba al empezar, y perdería todo
/// eso (F21).
///
/// Es una fusión de tres vías, campo por campo, entre [original] —cómo
/// estaba al empezar—, [enriched] —lo que devolvió el transformador— y
/// [current] —cómo está ahora—: un campo toma el valor del transformador solo
/// si el transformador lo cambió y el usuario no. Si los dos lo cambiaron, gana
/// el usuario: el título que alguien escribió a mano vale más que el que
/// trajo una página. Todo lo que un transformador no toca —etiquetas,
/// propiedades, tema, nota— sale siempre de [current].
KnowledgeItem mergeTransformResult({
  required KnowledgeItem original,
  required KnowledgeItem enriched,
  required KnowledgeItem current,
}) {
  T pick<T>(T before, T proposed, T now) =>
      proposed != before && now == before ? proposed : now;

  final source = current.source.copyWith(
    authorName: pick(
      original.source.authorName,
      enriched.source.authorName,
      current.source.authorName,
    ),
    authorUrl: pick(
      original.source.authorUrl,
      enriched.source.authorUrl,
      current.source.authorUrl,
    ),
    publishedAt: pick(
      original.source.publishedAt,
      enriched.source.publishedAt,
      current.source.publishedAt,
    ),
    originalFilePath: pick(
      original.source.originalFilePath,
      enriched.source.originalFilePath,
      current.source.originalFilePath,
    ),
  );

  final renditionsChanged = !_sameElements(
    enriched.renditions,
    original.renditions,
  );
  final renditionsUntouched = _sameElements(
    current.renditions,
    original.renditions,
  );

  return current.copyWith(
    title: pick(original.title, enriched.title, current.title),
    subtitle: pick(original.subtitle, enriched.subtitle, current.subtitle),
    source: source,
    renditions: renditionsChanged && renditionsUntouched
        ? enriched.renditions
        : current.renditions,
  );
}

/// Si [a] y [b] tienen los mismos elementos en el mismo orden. Cada forma es
/// un valor (freezed): dos iguales son `==` aunque sean instancias distintas.
bool _sameElements<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
