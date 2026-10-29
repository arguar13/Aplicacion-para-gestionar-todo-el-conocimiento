import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';

/// Lo que dice la píldora del selector de Repasar sobre un recorte (F43): su
/// nombre y la línea de detalle, «N documentos · M tarjetas · K creaciones».
@immutable
class CreationScopeSummary {
  const CreationScopeSummary({
    required this.scope,
    required this.name,
    required this.documents,
    required this.cards,
    required this.creations,
    this.exists = true,
  });

  final CreationScope scope;

  /// El título del documento, el nombre del cuaderno, del tema o del valor;
  /// `null` en «Todo lo procesado» —lo nombra la interfaz— y en un recorte que
  /// ya no existe.
  final String? name;

  /// Cuántos documentos procesados vivos tiene.
  final int documents;

  /// Cuántas tarjetas estudia «Para hoy» en él: las de sus documentos y las de
  /// sus fuentes (`StudyScope.processed`); en «Todo», todas.
  final int cards;

  /// Cuántas creaciones vivas muestra «Lo creado» en él.
  final int creations;

  /// `false` si lo que apunta ya no está: el documento se borró, el cuaderno o
  /// el tema ya no existen. La píldora lo dice y ofrece elegir otro.
  final bool exists;

  @override
  bool operator ==(Object other) =>
      other is CreationScopeSummary &&
      other.scope == scope &&
      other.name == name &&
      other.documents == documents &&
      other.cards == cards &&
      other.creations == creations &&
      other.exists == exists;

  @override
  int get hashCode =>
      Object.hash(scope, name, documents, cards, creations, exists);

  @override
  String toString() =>
      'CreationScopeSummary(${scope.storageKey}, $name, $documents docs, '
      '$cards tarjetas, $creations creaciones${exists ? '' : ', no existe'})';
}

/// Un documento procesado como fuente de una creación (F43): lo que necesitan
/// la fila de «Fuentes: N fuentes ▾», la del selector y el armado del material.
@immutable
class CreationSource {
  const CreationSource({
    required this.documentId,
    required this.title,
    required this.isLive,
    this.sourceItemId,
    this.hasSummary = false,
    this.hasSynthesis = false,
    this.hasKeywords = false,
    this.cards = 0,
    this.creations = 0,
  });

  final String documentId;

  /// Su título; vacío si el documento ya no existe.
  final String title;

  /// Si es un documento procesado vivo. Uno que no lo es —borrado de verdad o
  /// en la papelera— es una «fuente borrada».
  final bool isLive;

  /// La fuente de la Biblioteca de la que salió, si sigue enlazada.
  final String? sourceItemId;

  /// Si ya tiene resumen, síntesis y palabras clave (F36, F41): las de extraer
  /// los muestran, y el armado del material usa sus oraciones.
  final bool hasSummary;
  final bool hasSynthesis;
  final bool hasKeywords;

  /// Sus tarjetas y las de su fuente, vivas.
  final int cards;

  /// Las creaciones vivas sobre él o que lo leyeron.
  final int creations;

  @override
  bool operator ==(Object other) =>
      other is CreationSource &&
      other.documentId == documentId &&
      other.title == title &&
      other.isLive == isLive &&
      other.sourceItemId == sourceItemId &&
      other.hasSummary == hasSummary &&
      other.hasSynthesis == hasSynthesis &&
      other.hasKeywords == hasKeywords &&
      other.cards == cards &&
      other.creations == creations;

  @override
  int get hashCode => Object.hash(
    documentId,
    title,
    isLive,
    sourceItemId,
    hasSummary,
    hasSynthesis,
    hasKeywords,
    cards,
    creations,
  );

  @override
  String toString() =>
      'CreationSource($documentId, $title${isLive ? '' : ', borrada'})';
}
