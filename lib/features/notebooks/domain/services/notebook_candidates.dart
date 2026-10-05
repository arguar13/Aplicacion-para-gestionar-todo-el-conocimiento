import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/chat/domain/services/chat_passages.dart';

/// Cuántos elementos propone, como mucho, «Crear con IA» (F30).
const kNotebookCandidateLimit = 30;

/// Cuántos le muestra la IA de una vez para que diga cuáles van: con el
/// título y un fragmento corto de cada uno, el pedido ocupa menos de la mitad
/// de la ventana.
const kNotebookJudgeBatch = 8;

/// Cuántos revisa la IA, como mucho: los primeros de la lista, que son los
/// que más probablemente van. Tres pedidos; el resto queda como lo marcó la
/// búsqueda.
const kNotebookJudgeMax = 24;

/// Desde qué parecido por sentido entra un elemento entre lo propuesto, y
/// desde cuál se lo propone ya marcado cuando no hay quien lo revise.
///
/// Valores de partida, no medidos sobre una biblioteca real: con el modelo
/// de vínculos, un fragmento que habla de otra cosa suele quedar por debajo
/// de 0,4. El de los vínculos entre elementos (`selectCandidates`) parte de
/// 0,5, pero compara dos documentos; acá es una consulta de pocas palabras
/// contra un documento, que dan parecidos más bajos.
const kNotebookMinSimilarity = 0.45;
const kNotebookStrongSimilarity = 0.6;

/// Cuánto del fragmento de cada elemento se muestra y se le da a la IA.
const kNotebookExcerptChars = 240;

/// Un elemento que podría ir en el cuaderno, con por qué se lo encontró.
@immutable
class NotebookCandidate {
  const NotebookCandidate({
    required this.itemId,
    required this.title,
    required this.excerpt,
    required this.kind,
    this.matchedText = false,
    this.similarity,
  });

  final String itemId;
  final String title;

  /// El pasaje que habla de lo buscado, o el principio del texto.
  final String excerpt;
  final SourceKind kind;

  /// Si apareció buscando las palabras.
  final bool matchedText;

  /// El parecido por sentido, si se buscó así y llegó al mínimo.
  final double? similarity;

  /// Si se lo propone ya marcado cuando la IA no lo revisa: lo encontraron
  /// las palabras, o se parece mucho por sentido.
  bool get likely =>
      matchedText || (similarity ?? 0) >= kNotebookStrongSimilarity;

  @override
  bool operator ==(Object other) =>
      other is NotebookCandidate &&
      other.itemId == itemId &&
      other.title == title &&
      other.excerpt == excerpt &&
      other.kind == kind &&
      other.matchedText == matchedText &&
      other.similarity == similarity;

  @override
  int get hashCode =>
      Object.hash(itemId, title, excerpt, kind, matchedText, similarity);
}

/// Si se buscó también por sentido —con los vectores del modelo de
/// vínculos—, o por qué no.
enum SenseSearch {
  /// Por palabras y por sentido.
  used,

  /// Solo por palabras: el modelo de vínculos no está bajado.
  unavailable,

  /// Solo por palabras: buscar por sentido falló.
  failed,
}

/// Lo que encontró «Crear con IA»: los elementos, del que más probablemente
/// va al que menos, y cómo se buscó.
@immutable
class NotebookSearchResult {
  const NotebookSearchResult({
    required this.candidates,
    required this.senseSearch,
  });

  final List<NotebookCandidate> candidates;
  final SenseSearch senseSearch;
}

/// Busca en la biblioteca lo que podría ir en un cuaderno sobre un tema
/// (F30): por las palabras —el índice de texto— y, si está el modelo de
/// vínculos, también por sentido.
// ignore: one_member_abstracts
abstract interface class NotebookCandidateFinder {
  Future<NotebookSearchResult> find(
    String topic, {
    int limit = kNotebookCandidateLimit,
  });
}

/// Le pregunta a la IA cuáles elementos van en un cuaderno sobre un tema
/// (F30).
// ignore: one_member_abstracts
abstract interface class NotebookCandidateJudge {
  /// Los índices, desde 0, de los de [candidates] que van en un cuaderno
  /// sobre [topic]; `null` si la respuesta no se pudo leer —no es lo mismo
  /// que «ninguno»—.
  Future<Set<int>?> judgeNotebookCandidates({
    required String topic,
    required List<({String title, String excerpt})> candidates,
  });
}

/// Las palabras de para qué es el cuaderno, que no dicen de qué trata: «mi
/// tesis sobre Roma» busca Roma, no todo lo que dice «tesis». Ya plegadas
/// (`foldForSearch`).
const _purposeWords = <String>{
  'tesis',
  'tesina',
  'cuaderno',
  'cuadernos',
  'trabajo',
  'trabajos',
  'proyecto',
  'proyectos',
  'clase',
  'clases',
  'curso',
  'cursos',
  'materia',
  'materias',
  'examen',
  'examenes',
  'parcial',
  'parciales',
  'final',
  'finales',
  'estudiar',
  'estudio',
  'repasar',
  'repaso',
  'apuntes',
  'investigacion',
  'monografia',
  'ensayo',
  'informe',
  'charla',
  'presentacion',
  'thesis',
  'notebook',
  'project',
  'course',
  'class',
  'exam',
  'essay',
  'report',
  'study',
};

/// Lo que se busca por palabras para un cuaderno sobre [topic] (F30): sus
/// palabras de contenido (`questionTerms`), sin las de para qué es el
/// cuaderno. Si no queda ninguna —«mi tesis»—, las de contenido igual: es lo
/// único que hay.
String notebookTopicQuery(String topic) {
  final terms = questionTerms(topic, max: 12);
  final content = [
    for (final term in terms)
      if (!_purposeWords.contains(foldForSearch(term))) term,
  ];
  return (content.isEmpty ? terms : content).join(' ');
}

/// El nombre que se le propone al cuaderno: lo escrito, con la primera letra
/// en mayúscula y sin pasar de 60 caracteres.
String notebookNameFrom(String topic) {
  final trimmed = topic.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return trimmed;
  final capped = trimmed.length <= 60
      ? trimmed
      : '${trimmed.substring(0, 59).trimRight()}…';
  return capped[0].toUpperCase() + capped.substring(1);
}

/// Junta dos o más listas ordenadas en una sola (F30), por «fusión de
/// rangos recíprocos»: cada lista le da a cada id `1 / (60 + su puesto)`, y
/// se ordena por la suma. Un elemento que encuentran las dos búsquedas sube;
/// uno que solo encuentra una queda según qué tan arriba estaba en ella. No
/// necesita que los puntajes de las búsquedas sean comparables —el de BM25 y
/// un coseno no lo son—. A igual suma, el orden de la primera lista.
List<String> fuseRankings(List<List<String>> rankings) {
  const k = 60;
  final scores = <String, double>{};
  final firstSeen = <String, int>{};
  var seen = 0;
  for (final ranking in rankings) {
    for (var rank = 0; rank < ranking.length; rank++) {
      final id = ranking[rank];
      scores[id] = (scores[id] ?? 0) + 1 / (k + rank + 1);
      firstSeen.putIfAbsent(id, () => seen++);
    }
  }
  return scores.keys.toList()..sort((a, b) {
    final byScore = scores[b]!.compareTo(scores[a]!);
    return byScore != 0 ? byScore : firstSeen[a]!.compareTo(firstSeen[b]!);
  });
}

/// Lee la respuesta de la IA a cuáles van (F30): una línea
/// `VAN: 1, 3, 4` —los números de la lista— o `VAN: ninguno`. Devuelve los
/// índices desde 0, sin los que no estaban en la lista; `null` si no hay
/// ninguna línea así.
Set<int>? parseNotebookPicks(String text, {required int count}) {
  for (final raw in text.split('\n')) {
    final line = raw.replaceAll('*', '').trim();
    final match = RegExp(
      r'^VAN\s*:(.*)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) continue;
    final rest = match.group(1)!;
    if (foldForSearch(rest).contains('ninguno')) return const {};
    return {
      for (final number in RegExp(r'\d+').allMatches(rest))
        if (int.parse(number.group(0)!) case final n when n >= 1 && n <= count)
          n - 1,
    };
  }
  return null;
}
