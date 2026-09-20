import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/vault/data/merge/entry_merge_applier.dart';
import 'package:sinapsis/features/vault/data/merge/entry_merge_planner.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/space_merge.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';

/// Fusiona la copia de otra bóveda con esta, sin borrar nada de lo que hay
/// (F11).
///
/// Adjunta la copia a la conexión de esta bóveda y, en UNA transacción, lee las
/// dos, decide y escribe: si algo falla a la mitad no queda nada a medias. La
/// copia se adjunta antes de abrir la transacción porque SQLite no deja
/// adjuntar dentro de una, y se suelta después, pase lo que pase.
class VaultMerger {
  VaultMerger({
    required AppDatabase database,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _db = database,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  /// Fusiona [incoming] con esta bóveda. No la cierra: quien la abrió la
  /// suelta.
  Future<VaultMergeResult> merge(IncomingVault incoming) async {
    await incoming.attachTo(_db);
    try {
      return await _db.transaction(() async {
        // Los espacios primero: los elementos de la copia se acomodan en los de
        // acá.
        final spaces = await SpaceMerge.compute(_db);
        final plan = await EntryMergePlanner(_db).plan(spaces);
        return EntryMergeApplier(
          database: _db,
          ids: _ids,
          clock: _clock,
        ).apply(spaces: spaces, plan: plan);
      });
    } finally {
      await incoming.detachFrom(_db);
    }
  }
}
