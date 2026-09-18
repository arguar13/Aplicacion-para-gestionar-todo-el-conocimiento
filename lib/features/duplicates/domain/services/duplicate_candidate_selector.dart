/// Qué tan cerca está un [DuplicateCandidate] del elemento semilla.
enum DuplicateMatchKind {
  /// `dedupHash` igual: mismo texto normalizado, byte a byte.
  exact,

  /// Distancia de Hamming del `simhash` dentro del umbral, pero
  /// `dedupHash` distinto — casi-duplicado, no exacto.
  near,
}

/// Un candidato a ser el mismo elemento que el semilla —fuente o nota,
/// cualquiera de las dos—.
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.itemId,
    required this.title,
    required this.matchKind,
    required this.hammingDistance,
  });

  final String itemId;
  final String title;
  final DuplicateMatchKind matchKind;

  /// `0` para [DuplicateMatchKind.exact].
  final int hammingDistance;
}

/// Preselecciona candidatos a ser el mismo elemento que un semilla, por
/// `dedupHash`/`simhash` — ver `DedupFingerprint` en
/// `lib/core/domain/services/dedup_fingerprint.dart`.
///
/// Determinístico, sin modelo de IA: a diferencia de
/// `RelationCandidateSelector` (F5), acá no hay ningún LLM que juzgue
/// después — el hash/simhash ES el juicio, no una preselección para que
/// otra cosa decida.
// ignore: one_member_abstracts
abstract interface class DuplicateCandidateSelector {
  /// Candidatos que podrían ser el mismo elemento que [seedItemId], entre
  /// fuentes y notas —cualquier combinación, no solo mismo tipo contra
  /// mismo tipo—, excluyendo al propio [seedItemId]. Lista vacía si el
  /// semilla no tiene `dedupHash` calculado todavía, o si ningún otro
  /// elemento coincide — no es un error, es que no hay nada que
  /// preseleccionar todavía.
  Future<List<DuplicateCandidate>> selectCandidates({
    required String seedItemId,
    int maxHammingDistance = 3,
  });
}
