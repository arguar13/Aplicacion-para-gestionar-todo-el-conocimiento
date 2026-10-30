import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// Lo que el Resumen del Mapa (F44, paso 3) necesita saber de cada documento
/// procesado, además del grafo de temas: cuándo llegó, qué temas tiene de lo
/// que se mira y cómo va su estudio.
class BoardItemFact {
  const BoardItemFact({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.valueIds,
  });

  final String id;
  final String title;

  /// Cuándo se procesó: lo que dicen «Lo nuevo» y las cifras de 30 días.
  final DateTime createdAt;

  /// Los valores que tiene de lo que se mira (temas, etiquetas u otra
  /// categoría); vacío si ninguno.
  final List<String> valueIds;
}

/// Un vínculo entre dos documentos procesados vivos, con cuándo se hizo.
class BoardLinkFact {
  const BoardLinkFact({
    required this.fromId,
    required this.toId,
    required this.createdAt,
  });

  final String fromId;
  final String toId;
  final DateTime createdAt;
}

/// Las tarjetas de un documento procesado: las suyas y las de su fuente, las
/// mismas que estudia Repasar con ese documento en el selector (F43).
class BoardCardFact {
  const BoardCardFact({required this.cards, required this.dueToday});

  /// Cuántas tiene, pausadas incluidas: con alguna, ya tiene tarjetas.
  final int cards;

  /// Cuántas tocan hoy: ni pausadas ni pospuestas, y que vencen antes de que
  /// termine el día de estudio.
  final int dueToday;
}

/// Lo que el Resumen lee de la base para un pedido del Mapa: los documentos y
/// los vínculos que pasan el mismo filtro que el mapa.
class BoardFacts {
  const BoardFacts({required this.items, required this.links});

  const BoardFacts.empty() : items = const [], links = const [];

  final List<BoardItemFact> items;

  /// Los vínculos con sus DOS extremos en [items].
  final List<BoardLinkFact> links;
}

/// De dónde sale lo que el Resumen cuenta además del grafo de temas (F44, paso
/// 3). Solo lee.
///
/// Se lee en dos partes porque cambian a ritmos distintos: los documentos y
/// sus vínculos se mueven con el mapa —se vuelven a leer cuando el motor
/// recalcula—; las tarjetas, cada vez que se repasa una, sin que el mapa
/// tenga por qué enterarse.
abstract interface class BoardFactsSource {
  /// Los documentos procesados vivos que pasan [filter], con sus valores de
  /// [definitionId] (`kSpacesDimensionId` para los temas), y los vínculos
  /// entre ellos.
  ///
  /// Falla con una excepción si la biblioteca no pudo resolver el filtro.
  Future<BoardFacts> readFacts(
    String definitionId, {
    LibraryQuery filter = const LibraryQuery(),
  });

  /// Las tarjetas de cada documento procesado vivo que tiene alguna, por su
  /// id, contadas para el día de estudio de [now]. Un documento sin tarjetas
  /// no está.
  Future<Map<String, BoardCardFact>> readCards(DateTime now);

  /// Avisa cada vez que se escribe algo que puede cambiar lo que devuelve
  /// [readCards]: una tarjeta nueva, borrada o repasada.
  Stream<void> cardChanges();
}
