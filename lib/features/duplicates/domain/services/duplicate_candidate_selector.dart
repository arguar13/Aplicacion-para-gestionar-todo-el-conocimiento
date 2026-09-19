import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';

export 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';

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

  /// Lo mismo que [selectCandidates], pero para un texto que todavía no es
  /// un elemento — antes de guardarlo, con su huella ya calculada en
  /// memoria (ver `DedupFingerprint`). No excluye nada, porque todavía no
  /// hay ningún `itemId` propio que excluir.
  Future<List<DuplicateCandidate>> selectCandidatesForFingerprint({
    required String dedupHash,
    required String simhash,
    int maxHammingDistance = 3,
  });
}
