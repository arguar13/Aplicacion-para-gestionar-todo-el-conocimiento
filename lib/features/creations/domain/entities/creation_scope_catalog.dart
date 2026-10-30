import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';

/// Lo que tiene un recorte, como lo dice su fila del selector de Repasar
/// (F43, M11): la misma línea en «Recientes», en «Todos» y en los resultados.
///
/// Las cifras son las de la píldora (`CreationScopeSummary`) y salen de las
/// mismas reglas: las dos no pueden discrepar.
@immutable
class CreationScopeLine {
  const CreationScopeLine({
    required this.scope,
    required this.name,
    this.documents = 0,
    this.cards = 0,
    this.creations = 0,
    this.hasSummary = false,
    this.hasSynthesis = false,
  });

  final CreationScope scope;

  /// El título del documento, el nombre del cuaderno o del tema; vacío en
  /// «Todo lo procesado», que lo nombra la interfaz.
  final String name;

  /// Cuántos documentos procesados vivos tiene; 1 en un documento.
  final int documents;

  /// Las tarjetas que estudia «Para hoy» en él: las de sus documentos y las de
  /// sus fuentes; en «Todo», todas.
  final int cards;

  /// Las creaciones vivas que muestra «Lo creado» en él.
  final int creations;

  /// Si es un documento con su resumen o su síntesis marcados (F36, F41).
  final bool hasSummary;
  final bool hasSynthesis;

  @override
  bool operator ==(Object other) =>
      other is CreationScopeLine &&
      other.scope == scope &&
      other.name == name &&
      other.documents == documents &&
      other.cards == cards &&
      other.creations == creations &&
      other.hasSummary == hasSummary &&
      other.hasSynthesis == hasSynthesis;

  @override
  int get hashCode => Object.hash(
    scope,
    name,
    documents,
    cards,
    creations,
    hasSummary,
    hasSynthesis,
  );

  @override
  String toString() =>
      'CreationScopeLine(${scope.storageKey}, $name, $documents docs, '
      '$cards tarjetas, $creations creaciones'
      '${hasSummary ? ', resumen' : ''}${hasSynthesis ? ', síntesis' : ''})';
}

/// Lo que el selector de Repasar ofrece (F43, M11), entero, con la línea de
/// cada uno, leído de una vez: «Todo lo procesado», cada documento procesado
/// vivo, cada cuaderno y los temas que se pidieron.
///
/// Lo que no está acá ya no existe —un documento en la papelera, un cuaderno o
/// un tema borrados—: los recientes que lo apuntaban se olvidan.
@immutable
class CreationScopeCatalog {
  CreationScopeCatalog({
    required this.all,
    required List<CreationScopeLine> documents,
    required List<CreationScopeLine> notebooks,
    required List<CreationScopeLine> topics,
  }) : documents = List.unmodifiable(documents),
       notebooks = List.unmodifiable(notebooks),
       topics = List.unmodifiable(topics),
       _byScope = {
         all.scope: all,
         for (final line in [...documents, ...notebooks, ...topics])
           line.scope: line,
       };

  /// «Todo lo procesado».
  final CreationScopeLine all;

  /// Cada documento procesado vivo, sin un orden que importe: el selector los
  /// ordena de la A a la Z.
  final List<CreationScopeLine> documents;

  /// Cada cuaderno.
  final List<CreationScopeLine> notebooks;

  /// Los temas pedidos que existen, por categoría o por «Temas».
  final List<CreationScopeLine> topics;

  final Map<CreationScope, CreationScopeLine> _byScope;

  /// La línea de [scope], o `null` si no está: ya no existe o no se pidió.
  CreationScopeLine? lineOf(CreationScope scope) => _byScope[scope];

  @override
  String toString() =>
      'CreationScopeCatalog(${documents.length} documentos, '
      '${notebooks.length} cuadernos, ${topics.length} temas)';
}
