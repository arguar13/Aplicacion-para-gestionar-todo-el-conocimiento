import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';

/// Un espacio de la copia que esta bóveda no tiene.
class IncomingSpace {
  const IncomingSpace({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// Tal como está guardado: segundos desde 1970.
  final int createdAt;
}

/// Cómo se unen los espacios de la copia con los de esta bóveda (F11).
///
/// Un espacio es el mismo si tiene el mismo identificador o el mismo nombre
/// —sin distinguir mayúsculas ni espacios de los bordes—: dos con el mismo
/// nombre no pueden convivir, y dos bóvedas pudieron crear «Historia» cada una
/// por su cuenta, con identificadores distintos. Un elemento de la copia que
/// estaba en el espacio «Historia» de ellos queda en el «Historia» de acá.
///
/// Se calcula leyendo los dos —hay pocos— y sin escribir: la vista previa y la
/// fusión parten del mismo resultado.
class SpaceMerge {
  const SpaceMerge({required this.remap, required this.toAdd});

  /// Los espacios de la copia que se llaman como uno de acá pero con otro
  /// identificador: identificador de la copia → identificador de acá. Un
  /// espacio con el mismo identificador en las dos no aparece: es el mismo.
  final Map<String, String> remap;

  /// Los que esta bóveda no tiene por ningún concepto, y hay que crear con el
  /// identificador que traen.
  final List<IncomingSpace> toAdd;

  /// El identificador de acá del espacio [incomingId] de la copia.
  String? localIdOf(String? incomingId) =>
      incomingId == null ? null : remap[incomingId] ?? incomingId;

  /// Lee los espacios de las dos bóvedas. La copia tiene que estar adjuntada.
  static Future<SpaceMerge> compute(AppDatabase database) async {
    final localIds = <String>{};
    final localByName = <String, String>{};
    for (final row
        in await database
            .customSelect('SELECT id, name FROM main.spaces')
            .get()) {
      final id = row.read<String>('id');
      localIds.add(id);
      localByName[_key(row.read<String>('name'))] = id;
    }

    final incoming = await database.customSelect('''
      SELECT id, name, created_at FROM $kIncomingSchema.spaces
       ORDER BY created_at, id''').get();

    final remap = <String, String>{};
    final toAdd = <IncomingSpace>[];
    for (final row in incoming) {
      final id = row.read<String>('id');
      if (localIds.contains(id)) continue;

      final name = row.read<String>('name');
      final sameName = localByName[_key(name)];
      if (sameName != null) {
        remap[id] = sameName;
        continue;
      }
      toAdd.add(
        IncomingSpace(
          id: id,
          name: name,
          createdAt: row.read<int>('created_at'),
        ),
      );
      // Dos de la copia con el mismo nombre se unen entre sí igual que con uno
      // de acá.
      localByName[_key(name)] = id;
    }
    return SpaceMerge(remap: remap, toAdd: toAdd);
  }

  static String _key(String name) => name.trim().toLowerCase();
}
