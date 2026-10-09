/// Paths y nombres de ruta centralizados. Cada feature nuevo añade sus
/// constantes aquí (o expone su propio archivo `xxx_route_paths.dart` que
/// este archivo re-exporta) para que las URLs web queden en un solo lugar.
abstract final class RoutePaths {
  static const splash = '/splash';

  /// Las dos caras de la bóveda. Son rutas distintas y no una sola pantalla
  /// con dos modos porque responden a situaciones distintas: crear la bóveda
  /// pasa una vez en la vida del dispositivo, abrirla pasa en cada arranque.
  static const vaultCreate = '/vault/create';
  static const vaultUnlock = '/vault/unlock';

  /// La biblioteca: la pantalla principal con todo lo guardado.
  static const library = '/library';

  /// El detalle de un elemento. Se arma con [itemDetail] para no escribir la
  /// interpolación a mano en cada sitio que navega hasta acá.
  static const itemDetailPattern = '$library/:id';

  static String itemDetail(String id) => '$library/$id';

  /// El Explorador: lo ya procesado, organizado en carpetas.
  static const explorer = '/explorer';

  /// El Explorador ya filtrado por el valor [valueId] de una propiedad: lo
  /// que el Atlas abre desde una rama o un vacío (F13).
  static String explorerFor(String valueId) =>
      '$explorer?value=${Uri.encodeQueryComponent(valueId)}';

  /// El Explorador parado en el tema [spaceId] —un espacio—: lo que el Mapa
  /// y el Atlas abren desde un tema (F28).
  static String explorerForSpace(String spaceId) =>
      '$explorer?space=${Uri.encodeQueryComponent(spaceId)}';

  /// El Atlas: el índice dinámico de lo que se sabe y de lo que falta (F13).
  /// Un destino de navegación principal.
  static const atlas = '/atlas';

  /// La Bandeja de entrada: lo recién procesado, esperando triaje.
  static const inbox = '/inbox';

  /// Guardar algo nuevo.
  static const capture = '/capture';

  /// El modelo de transcripción: si está descargado, y descargarlo.
  static const transcriptionModel = '/transcription-model';

  /// Copia de seguridad de la bóveda completa: exportar e importar.
  static const vaultBackup = '/vault-backup';

  /// Devolver al dispositivo el espacio que la bóveda ya no usa (F12).
  static const vaultCompaction = '/vault-compaction';

  /// Lo que el generador de duplicados (F7) encontró parecido a algo ya
  /// guardado, en toda la bóveda. Ruta plana, mismo criterio que
  /// [graphTension]: es una acción de mantenimiento de la bóveda, no un
  /// octavo destino de navegación.
  static const duplicates = '/duplicates';

  /// El mantenimiento del vocabulario controlado (F8): valores repetidos, de
  /// un solo uso, sin uso, categorías vacías. Ruta plana, mismo criterio que
  /// [duplicates]: es una acción de mantenimiento de la bóveda, no un
  /// destino de navegación.
  static const vocabulary = '/vocabulary';

  /// El explorador de UNA categoría del vocabulario: sus valores con cuántos
  /// elementos los tienen, para renombrar, fusionar y manejar alias. Se arma
  /// con [vocabularyCategory], mismo criterio que [graphLocal].
  static const vocabularyCategoryPattern = '$vocabulary/category/:id';

  static String vocabularyCategory(String definitionId) =>
      '$vocabulary/category/$definitionId';

  /// Los `[[enlaces]]` sin nota de toda la bóveda (F9), con la creación en
  /// lote. Ruta plana, mismo criterio que [duplicates]: es una acción de
  /// mantenimiento de la bóveda, no un destino de navegación.
  static const brokenLinks = '/broken-links';

  /// La revisión en lote de las sugerencias de propiedad de toda la bóveda
  /// (F9). Ruta plana, mismo criterio que [brokenLinks].
  static const suggestionReview = '/suggestion-review';

  /// Las notas vivas que crecieron esta semana (F9): la entrada a la sesión de
  /// consolidación. Ruta plana, mismo criterio que [brokenLinks].
  static const grownNotes = '/grown-notes';

  /// La vista de lectura para destilar (F9): el texto de una fuente para
  /// sacarle notas. Se arma con [reading], que admite el fragmento al que
  /// abrirla —`start` y `end` en la consulta—.
  static const readingPattern = '/reading/:id';

  static String reading(String itemId, {int? start, int? end}) {
    final query = start != null && end != null ? '?start=$start&end=$end' : '';
    return '/reading/$itemId$query';
  }

  /// La línea de tiempo de los hechos con fecha (F9). Ruta plana, mismo
  /// criterio que [brokenLinks]: es una vista sobre lo guardado, no un
  /// destino de navegación.
  static const timeline = '/timeline';

  /// La línea de tiempo ya filtrada por el valor [valueId] de una propiedad,
  /// con su nombre [label] para rotular el filtro (F13): lo que el Atlas abre
  /// desde el eje temporal de una rama.
  static String timelineFor({required String valueId, required String label}) =>
      '$timeline?value=${Uri.encodeQueryComponent(valueId)}'
      '&label=${Uri.encodeQueryComponent(label)}';

  /// La línea de tiempo ya filtrada por el tema [spaceId] —un espacio—, con
  /// su nombre [label] (F28): lo que el Atlas de los temas abre desde el eje
  /// de una rama.
  static String timelineForSpace({
    required String spaceId,
    required String label,
  }) =>
      '$timeline?space=${Uri.encodeQueryComponent(spaceId)}'
      '&label=${Uri.encodeQueryComponent(label)}';

  /// El Mapa de conocimiento (F14): el tablero, el esquema y el grafo de
  /// temas. Un destino de navegación principal. Conserva el camino `/graph`
  /// del grafo completo al que reemplazó porque de él cuelgan [graphTension] y
  /// [graphLocalPattern].
  static const graph = '/graph';

  /// Los pares de elementos que se contradicen entre sí, en toda la
  /// bóveda. Ruta plana bajo `/graph`, mismo criterio que [chatModel]: es
  /// una lente sobre datos que ya vive en el grafo, no un destino propio.
  static const graphTension = '$graph/tension';

  /// El grafo local de un elemento puntual, con pan y zoom. Se arma con
  /// [graphLocal] para no escribir la interpolación a mano en cada sitio
  /// que navega hasta acá.
  static const graphLocalPattern = '$graph/local/:id';

  static String graphLocal(String itemId) => '$graph/local/$itemId';

  /// Los cuadernos (F16): un subconjunto con nombre de la bóveda, manual o
  /// por consulta guardada. Un destino de navegación principal.
  static const notebooks = '/notebooks';

  /// El detalle de un cuaderno. Se arma con [notebookDetail], mismo criterio
  /// que [itemDetail].
  static const notebookDetailPattern = '$notebooks/:id';

  static String notebookDetail(String id) => '$notebooks/$id';

  /// Preguntarle algo a la bóveda.
  static const chat = '/chat';

  /// Si el modelo de lenguaje del chat está descargado, y descargarlo.
  static const chatModel = '/chat/model';

  /// Si el modelo de embeddings del motor de relaciones está descargado,
  /// y descargarlo. Ruta plana bajo `/relations`, mismo criterio que
  /// [chatModel]: es una lente sobre datos, no un destino de navegación.
  static const embeddingModel = '/relations/embedding-model';

  /// La ayuda para que el sistema no cierre la app con trabajo a medias
  /// (F29): "Inicio automático" y la batería.
  static const keepWorking = '/keep-working';

  /// Calcular bajo demanda los embeddings que le falten a lo ya
  /// capturado antes de tener el modelo descargado.
  static const embeddingBackfill = '/relations/embedding-backfill';

  /// Repasar las tarjetas que ya tocan.
  static const review = '/review';

  /// Las insignias de F17, D7: qué premia la app y qué ya se ganó. Ruta
  /// plana bajo `/review`, mismo criterio que [graphTension]: es una
  /// lente sobre el hábito de repasar, no un destino de navegación propio.
  static const reviewBadges = '$review/badges';

  /// El historial de repasos de F17, D8: curva de retención, calendario de
  /// constancia y tarjetas difíciles. Ruta plana bajo `/review`, mismo
  /// criterio que [reviewBadges].
  static const reviewHistory = '$review/history';

  /// La sesión de repaso (F31, ola 2): estudiar de a una tarjeta. Pantalla
  /// completa, sin la barra de navegación. Se arma con [reviewSessionFor].
  static const reviewSession = '$review/session';

  /// La sesión de repaso de un recorte: [kind] es el nombre de un
  /// `StudyScopeKind` (`all`, `space`, `value`, `notebook`, `item`) e [id] el
  /// del espacio, valor, cuaderno o elemento. Con [practice], «Practicar
  /// igual»: repasar todas las tarjetas sin tocar su calendario.
  static String reviewSessionFor({
    String kind = 'all',
    String? id,
    bool practice = false,
  }) {
    final query = <String, String>{
      if (kind != 'all') 'kind': kind,
      if (id != null) 'id': id,
      if (practice) 'practice': '1',
    };
    return query.isEmpty
        ? reviewSession
        : Uri(path: reviewSession, queryParameters: query).toString();
  }

  /// Idioma, tema, modelo de transcripción, copia de seguridad y bloqueo de
  /// la bóveda, todo junto.
  static const settings = '/settings';

  /// Lo que se borró y todavía se puede restaurar (F11).
  static const trash = '/trash';

  /// Lo que la IA organizó sola, lo que dejó para revisar y en qué anda su
  /// cola (F27). Ruta plana, mismo criterio que [trash]: se llega desde
  /// Ajustes › IA y desde la línea de cada elemento, no es un destino de
  /// navegación.
  static const aiActivity = '/ai-activity';

  /// Lo mismo, solo de un elemento: lo que abre «Ver» desde su detalle.
  static String aiActivityFor(String itemId) =>
      '$aiActivity?item=${Uri.encodeQueryComponent(itemId)}';

  /// Los cambios que una fusión no pudo decidir sola y esperan que el usuario
  /// elija (F11).
  static const conflicts = '/conflicts';
}

abstract final class RouteNames {
  static const splash = 'splash';
  static const vaultCreate = 'vault-create';
  static const vaultUnlock = 'vault-unlock';
  static const library = 'library';
  static const itemDetail = 'item-detail';
  static const explorer = 'explorer';
  static const atlas = 'atlas';
  static const notebooks = 'notebooks';
  static const notebookDetail = 'notebook-detail';
  static const inbox = 'inbox';
  static const capture = 'capture';
  static const transcriptionModel = 'transcription-model';
  static const vaultBackup = 'vault-backup';
  static const vaultCompaction = 'vault-compaction';
  static const duplicates = 'duplicates';
  static const vocabulary = 'vocabulary';
  static const vocabularyCategory = 'vocabulary-category';
  static const brokenLinks = 'broken-links';
  static const suggestionReview = 'suggestion-review';
  static const grownNotes = 'grown-notes';
  static const timeline = 'timeline';
  static const reading = 'reading';
  static const graph = 'graph';
  static const chat = 'chat';
  static const chatModel = 'chat-model';
  static const embeddingModel = 'embedding-model';
  static const keepWorking = 'keep-working';
  static const embeddingBackfill = 'embedding-backfill';
  static const graphTension = 'graph-tension';
  static const graphLocal = 'graph-local';
  static const review = 'review';
  static const reviewSession = 'review-session';
  static const reviewBadges = 'review-badges';
  static const reviewHistory = 'review-history';
  static const settings = 'settings';
  static const trash = 'trash';
  static const aiActivity = 'ai-activity';
  static const conflicts = 'conflicts';
}

/// «Mis tarjetas» (F31, ola 2): todas las tarjetas, con búsqueda, filtros y
/// acciones en lote. Admite un recorte en la consulta (`?item=`, `?space=`,
/// `?value=` o `?notebook=` con el identificador). Ruta plana, mismo criterio
/// que [RoutePaths.reviewHistory].
const kRouteCards = '/cards';

/// Las estadísticas de repaso (F31, ola 2): pronóstico, reparto por etapa y
/// botones usados, con lo que ya había (racha, constancia, retención).
const kRouteReviewStats = '/review/stats';

/// Los nombres de esas dos rutas.
const kRouteNameCards = 'cards';
const kRouteNameReviewStats = 'review-stats';
