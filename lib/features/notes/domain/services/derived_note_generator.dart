import 'package:sinapsis/core/domain/entities/chat_source.dart';

/// Los cuatro derivados que F16 sabe armar (D5): una nota nueva, generada,
/// nunca una edición de lo que ya existe —la restricción inalienable del
/// encargo—.
enum DerivedNoteType {
  /// Una sección por tema importante, con sus afirmaciones clave.
  studyGuide,

  /// Preguntas que el contenido permite responder, para repasar.
  openQuestions,

  /// Los puntos principales, agrupados por tema.
  outline,

  /// Los hechos que se puedan fechar, en el orden en que ocurrieron.
  timeline,
}

/// Una afirmación de un derivado, ya anclada a un pasaje real de una fuente
/// (D6): con esto alcanza para crear después una `RelationKind.
/// extractedFrom` de verdad —`sourceItemId` es a quién, `sourceCharStart`/
/// `sourceCharEnd` es dónde—.
///
/// No hay `DerivedClaim` sin ancla: lo que el modelo dijo sin que su cita se
/// pudiera encontrar tal cual en ninguna fuente nunca llega a existir como
/// tal —se descarta antes, no se guarda con el ancla vacía—.
class DerivedClaim {
  const DerivedClaim({
    required this.text,
    required this.sourceItemId,
    required this.sourceCharStart,
    required this.sourceCharEnd,
  });

  final String text;
  final String sourceItemId;
  final int sourceCharStart;
  final int sourceCharEnd;
}

/// Un grupo de afirmaciones bajo un mismo título —una guía de estudio y un
/// esquema lo usan; una lista de preguntas o una cronología no necesitan
/// agrupar, y quedan en una sola sección sin título—.
class DerivedSection {
  const DerivedSection({required this.claims, this.heading});

  final String? heading;
  final List<DerivedClaim> claims;
}

/// Lo que arma [DerivedNoteGenerator], todavía sin guardar.
///
/// Puede quedar sin secciones —`isEmpty`— si nada de lo que devolvió el
/// modelo se pudo anclar a una fuente real: no es un error, es un derivado
/// que no sirvió, mismo criterio que una tarjeta que el modelo no supo
/// generar.
class DerivedNoteDraft {
  const DerivedNoteDraft({required this.type, required this.sections});

  final DerivedNoteType type;
  final List<DerivedSection> sections;

  bool get isEmpty => sections.isEmpty;
}

/// Propone un derivado —guía de estudio, preguntas abiertas, esquema o
/// cronología— a partir de un conjunto de fuentes, usando el mismo modelo
/// de lenguaje del chat (F16, D5).
///
/// Mismo patrón que `FlashcardGenerator`, con una regla más estricta:
/// mientras que una tarjeta sin cita verificable se guarda igual, sin
/// fragmento, acá una afirmación que no se pueda anclar a un offset real de
/// alguna fuente no se escribe en el derivado —D6—. Nunca guarda nada por
/// su cuenta: crear la nota de verdad, con su marca y sus relaciones
/// `extractedFrom`, es de quien use esto, no de acá.
///
/// El método se llama `generateDerivedNote`, no `generate`: `GemmaChatModel`
/// ya implementa `FlashcardGenerator.generate`, con otra firma —un solo
/// método no puede tener dos firmas distintas en la misma clase—.
// ignore: one_member_abstracts
abstract interface class DerivedNoteGenerator {
  Future<DerivedNoteDraft> generateDerivedNote({
    required DerivedNoteType type,
    required List<ChatSource> sources,
  });
}
