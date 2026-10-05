import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';

/// Cuántos caracteres de fuentes —títulos y fragmentos— ve el modelo por
/// pedido al armar un derivado (F30).
///
/// La ventana de Gemma es de 2048 tokens para todo: la instrucción (~200), la
/// respuesta más larga (`kDerivedNoteReplyTokens`, 768) y las fuentes. En
/// español cuenta unos 3,5 caracteres por token (`kFlashcardPartChars`):
/// 3000 caracteres son ~860 tokens, y entran con margen. Es una cuenta para
/// repartir, no la garantía: el modelo cuenta de verdad con su tokenizador
/// antes de mandar ([fitSourcesToWindow]).
///
/// Hasta F30 se mandaban **todas** las fuentes de una vez, a 400 caracteres
/// cada una: con más de unas quince, el pedido no entraba en la ventana.
const kDerivedNotePartChars = 3000;

/// Cuántos pedidos al modelo, como mucho, para un derivado: cada uno escribe
/// hasta 768 tokens, y en el teléfono eso es cerca de un minuto. Con tres
/// entran unas dieciocho fuentes; de un cuaderno más grande se leen las más
/// representativas (`ItemVectorIndex.representativeOrder`).
const kDerivedNoteMaxParts = 3;

/// Cuántas fuentes se preparan, como mucho, antes de repartirlas en partes:
/// más de las que entran, para que una que no se pueda citar no deje una
/// parte corta.
const kDerivedNoteMaxSources = kDerivedNoteMaxParts * 8;

/// Lo que ocupa [source] en el pedido: su título, su fragmento y la
/// numeración que los separa.
int derivedSourceChars(ChatSource source) =>
    source.itemTitle.length + source.excerpt.length + 8;

/// Reparte [sources], en su orden, en partes de hasta [partChars] caracteres
/// (F30), y como mucho [maxParts]: las que no entran quedan afuera —van al
/// final las menos representativas—. Una fuente sola más larga que una parte
/// va sola en la suya: el modelo la recorta al mandarla
/// ([fitSourcesToWindow]).
List<List<ChatSource>> packDerivedSources(
  List<ChatSource> sources, {
  int partChars = kDerivedNotePartChars,
  int maxParts = kDerivedNoteMaxParts,
}) {
  final parts = <List<ChatSource>>[];
  var current = <ChatSource>[];
  var used = 0;
  for (final source in sources) {
    final size = derivedSourceChars(source);
    if (current.isNotEmpty && used + size > partChars) {
      parts.add(current);
      if (parts.length == maxParts) return parts;
      current = [];
      used = 0;
    }
    current.add(source);
    used += size;
  }
  if (current.isNotEmpty && parts.length < maxParts) parts.add(current);
  return parts;
}

/// Junta lo que dio cada parte en un solo derivado (F30): las secciones con
/// el mismo título —sin distinguir mayúsculas ni espacios— van juntas, en el
/// orden en que apareció cada una; las sin título, en una sola. Cada fuente
/// ancla como mucho una afirmación (`anchorDerivedClaims`): si dos partes
/// citaran la misma, la segunda se descarta —no tendría dónde guardar su
/// vínculo—.
List<DerivedSection> mergeDerivedSections(List<List<DerivedSection>> parts) {
  final order = <String>[];
  final headings = <String, String?>{};
  final claims = <String, List<DerivedClaim>>{};
  final cited = <String>{};
  for (final part in parts) {
    for (final section in part) {
      final key = section.heading?.trim().toLowerCase() ?? '';
      if (!claims.containsKey(key)) {
        order.add(key);
        headings[key] = section.heading;
        claims[key] = [];
      }
      for (final claim in section.claims) {
        if (cited.add(claim.sourceItemId)) claims[key]!.add(claim);
      }
    }
  }
  return [
    for (final key in order)
      if (claims[key]!.isNotEmpty)
        DerivedSection(heading: headings[key], claims: claims[key]!),
  ];
}

/// Cuánto más corto puede quedar un fragmento al recortarlo para que entre:
/// menos que esto no da de dónde citar, y conviene dejar la fuente afuera.
const kMinDerivedExcerptChars = 120;

/// [sources], recortadas hasta que el pedido que arma [build] ocupe a lo sumo
/// [roomTokens] según [countTokens] —el tokenizador del modelo— (F30).
///
/// Primero acorta los fragmentos, todos en la misma proporción, por el final
/// y en el borde de una palabra: cada uno sigue empezando donde empezaba, así
/// que una cita encontrada en él sigue señalando el lugar exacto de la
/// fuente. Si para entrar alguno tendría que quedar más corto que
/// [kMinDerivedExcerptChars], saca la última fuente. Vacío si ni una entra.
Future<List<ChatSource>> fitSourcesToWindow(
  List<ChatSource> sources, {
  required int roomTokens,
  required Future<int> Function(String text) countTokens,
  required String Function(List<ChatSource> sources) build,
}) async {
  var fitted = sources;
  while (fitted.isNotEmpty) {
    final used = await countTokens(build(fitted));
    if (used <= roomTokens) return fitted;

    // Un poco menos que la proporción justa: los tokens no son parejos.
    final ratio = roomTokens / used * 0.95;
    final shorter = [
      for (final source in fitted)
        _shortened(source, (_textOf(source).length * ratio).floor()),
    ];
    final tooShort = shorter.any(
      (s) => _textOf(s).length < kMinDerivedExcerptChars,
    );
    fitted = tooShort ? fitted.sublist(0, fitted.length - 1) : shorter;
  }
  return const [];
}

/// El texto real del fragmento, sin los puntos suspensivos con que
/// `buildChatSource` marca que sigue.
String _textOf(ChatSource source) {
  final excerpt = source.excerpt;
  return excerpt.endsWith('…')
      ? excerpt.substring(0, excerpt.length - 1)
      : excerpt;
}

/// [source] con su fragmento cortado a [chars] caracteres, en el borde de una
/// palabra, y su fin corrido a la par.
ChatSource _shortened(ChatSource source, int chars) {
  final text = _textOf(source);
  if (chars >= text.length) return source;
  var end = chars.clamp(0, text.length);
  final space = text.lastIndexOf(' ', end);
  if (space > end ~/ 2) end = space;
  final kept = text.substring(0, end).trimRight();
  final start = source.sourceCharStart;
  return source.copyWith(
    excerpt: '$kept…',
    sourceCharEnd: start == null ? null : start + kept.length,
  );
}
