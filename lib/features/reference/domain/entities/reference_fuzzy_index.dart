import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';

/// Una obra ya guardada, con lo mínimo para compararla por título, año y
/// primer autor (F15, D9): sin `dedupHash` ni `simhash` —una referencia
/// recién importada no tiene texto que comparar—.
@immutable
class ReferenceFuzzyCandidate {
  const ReferenceFuzzyCandidate({
    required this.itemId,
    required this.title,
    this.year,
    this.firstAuthorFamily,
  });

  final String itemId;

  /// Tal como se guarda, sin normalizar: es lo que se muestra en la
  /// sugerencia de duplicado, no lo que se compara.
  final String title;

  final int? year;

  /// Ya normalizado (sin mayúsculas ni acentos), o `null` si la obra no
  /// tiene ningún autor asignado.
  final String? firstAuthorFamily;
}

/// Quién ya tiene un título parecido, para proponer un posible duplicado al
/// importar una referencia sin identificador que la vincule de forma exacta
/// (F15, D9): nunca fusiona sola, solo propone —a la pantalla de duplicados
/// de F7—.
///
/// «Difusa» acá es «sin distinguir mayúsculas ni acentos», con
/// `normalizeVocabularyLabel` —el mismo plegado que ya usa el vocabulario
/// controlado—, no una distancia de edición: dos títulos genuinamente
/// distintos con una palabra de diferencia NO coinciden. Es la lectura más
/// simple y verificable de «coincidencia difusa (título + año + primer
/// autor)»; si hiciera falta algo más laxo, se amplía después con lo que se
/// vea en la práctica, no de entrada.
@immutable
class ReferenceFuzzyIndex {
  const ReferenceFuzzyIndex(Map<String, List<ReferenceFuzzyCandidate>> byTitle)
    : _byTitle = byTitle;

  final Map<String, List<ReferenceFuzzyCandidate>> _byTitle;

  /// Los candidatos con el mismo título normalizado que [title], y que no
  /// contradicen a [year] ni a [authorFamily] —un dato ausente de cualquiera
  /// de los dos lados no descarta la coincidencia, porque «no cargado» no es
  /// «distinto»—.
  List<ReferenceFuzzyCandidate> find({
    required String title,
    int? year,
    String? authorFamily,
  }) {
    final key = normalizeVocabularyLabel(title);
    if (key.isEmpty) return const [];

    return [
      for (final candidate
          in _byTitle[key] ?? const <ReferenceFuzzyCandidate>[])
        if ((year == null ||
                candidate.year == null ||
                candidate.year == year) &&
            (authorFamily == null ||
                candidate.firstAuthorFamily == null ||
                candidate.firstAuthorFamily == authorFamily))
          candidate,
    ];
  }
}
