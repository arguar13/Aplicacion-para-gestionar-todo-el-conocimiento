import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/services/dedup_fingerprint.dart';
import 'package:sinapsis/features/duplicates/domain/services/duplicate_candidate_selector.dart';

/// [DuplicateCandidateSelector] contra `AppDatabase`: lee los
/// `dedupHash`/`simhash` ya persistidos en `source`/`note`, sin calcular
/// ninguno nuevo — si el semilla o un candidato todavía no los tienen,
/// simplemente no participan.
class DuplicateCandidateSelectorImpl implements DuplicateCandidateSelector {
  const DuplicateCandidateSelectorImpl({required AppDatabase database})
    : _db = database;

  final AppDatabase _db;

  @override
  Future<List<DuplicateCandidate>> selectCandidates({
    required String seedItemId,
    int maxHammingDistance = 3,
  }) async {
    final seed = await _fingerprintFor(seedItemId);
    if (seed == null) return const [];

    final others = await _allFingerprintsExcept(seedItemId);
    return _matchAgainst(
      seed: seed,
      others: others,
      maxHammingDistance: maxHammingDistance,
    );
  }

  @override
  Future<List<DuplicateCandidate>> selectCandidatesForFingerprint({
    required String dedupHash,
    required String simhash,
    int maxHammingDistance = 3,
  }) async {
    final others = await _allFingerprintsExcept(null);
    return _matchAgainst(
      seed: (dedupHash: dedupHash, simhash: simhash),
      others: others,
      maxHammingDistance: maxHammingDistance,
    );
  }

  Future<List<DuplicateCandidate>> _matchAgainst({
    required ({String dedupHash, String simhash}) seed,
    required List<({String itemId, String dedupHash, String? simhash})> others,
    required int maxHammingDistance,
  }) async {
    final candidates = <DuplicateCandidate>[];
    for (final other in others) {
      final DuplicateMatchKind matchKind;
      final int hammingDist;

      if (other.dedupHash == seed.dedupHash) {
        matchKind = DuplicateMatchKind.exact;
        hammingDist = 0;
      } else if (other.simhash != null) {
        hammingDist = hammingDistance(seed.simhash, other.simhash!);
        if (hammingDist > maxHammingDistance) continue;
        matchKind = DuplicateMatchKind.near;
      } else {
        continue;
      }

      final title = await _titleFor(other.itemId);
      if (title == null) continue;

      candidates.add(
        DuplicateCandidate(
          itemId: other.itemId,
          title: title,
          matchKind: matchKind,
          hammingDistance: hammingDist,
        ),
      );
    }

    candidates.sort((a, b) => a.hammingDistance.compareTo(b.hammingDistance));
    return candidates;
  }

  Future<({String dedupHash, String simhash})?> _fingerprintFor(
    String itemId,
  ) async {
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(itemId))).getSingleOrNull();
    if (source != null) {
      final dedupHash = source.dedupHash;
      final simhash = source.simhash;
      if (dedupHash == null || simhash == null) return null;
      return (dedupHash: dedupHash, simhash: simhash);
    }

    final note = await (_db.select(
      _db.knowledgeNotes,
    )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
    if (note == null) return null;
    final dedupHash = note.dedupHash;
    final simhash = note.simhash;
    if (dedupHash == null || simhash == null) return null;
    return (dedupHash: dedupHash, simhash: simhash);
  }

  /// `itemId` en `null` no excluye nada — el caso de un texto que todavía
  /// no es un elemento, sin ningún `itemId` propio que pudiera coincidir
  /// consigo mismo.
  Future<List<({String itemId, String dedupHash, String? simhash})>>
  _allFingerprintsExcept(String? itemId) async {
    final sources =
        await (_db.select(_db.knowledgeSources)..where(
              (s) =>
                  (itemId == null
                      ? const Constant(true)
                      : s.itemId.equals(itemId).not()) &
                  s.dedupHash.isNotNull(),
            ))
            .get();
    final notes =
        await (_db.select(_db.knowledgeNotes)..where(
              (n) =>
                  (itemId == null
                      ? const Constant(true)
                      : n.itemId.equals(itemId).not()) &
                  n.dedupHash.isNotNull(),
            ))
            .get();

    return [
      for (final source in sources)
        (
          itemId: source.itemId,
          dedupHash: source.dedupHash!,
          simhash: source.simhash,
        ),
      for (final note in notes)
        (
          itemId: note.itemId,
          dedupHash: note.dedupHash!,
          simhash: note.simhash,
        ),
    ];
  }

  Future<String?> _titleFor(String itemId) async {
    final row = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId))).getSingleOrNull();
    return row?.title;
  }
}
