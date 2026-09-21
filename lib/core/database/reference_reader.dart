import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_row_mapping.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';

/// Lee los datos bibliográficos de las fuentes (F15): por una, o por muchas a
/// la vez.
///
/// Es la lectura liviana que usan la cita y la bibliografía: una consulta por
/// lote de fuentes para la referencia y otra para sus personas, sin cargar
/// texto, formas ni chunks. Una bibliografía de miles de fuentes es un puñado
/// de consultas, no una por fuente.
///
/// Lee por identificador: quien lo llama ya decidió qué elementos son visibles
/// —la Biblioteca y la consulta de la bibliografía dejan afuera la papelera—, y
/// este lector no vuelve a decidirlo. Lo que pida se lo da, esté vivo o no.
class ReferenceReader {
  const ReferenceReader(this._db);

  final AppDatabase _db;

  /// Cuántos ids entran en una sola consulta: por debajo del tope de parámetros
  /// de SQLite.
  static const _idsPerQuery = 400;

  /// Los datos de [itemId]. Una fuente sin nada guardado devuelve una
  /// referencia vacía, no `null`: quien cita marca lo que falta.
  Future<ReferenceData> read(String itemId) async =>
      (await readMany([itemId]))[itemId] ?? const ReferenceData();

  /// Los datos de cada uno de [itemIds] que tenga algo guardado, por
  /// identificador. Los que no tienen ni referencia ni personas no figuran.
  Future<Map<String, ReferenceData>> readMany(Iterable<String> itemIds) async {
    final ids = itemIds.toSet().toList();
    final result = <String, ReferenceData>{};
    for (var start = 0; start < ids.length; start += _idsPerQuery) {
      final slice = ids.skip(start).take(_idsPerQuery).toList();
      final rows = await (_db.select(
        _db.sourceReferences,
      )..where((r) => r.itemId.isIn(slice))).get();
      final people = await _contributorsOf(slice);
      for (final row in rows) {
        result[row.itemId] = referenceFor(row, people[row.itemId] ?? const []);
      }
      // Una fuente con personas y sin fila de referencia: no debería pasar —el
      // escritor las crea juntas—, pero una fusión de bóvedas escribe con SQL
      // crudo, y perder sus autores en silencio sería peor que mostrarlos.
      for (final entry in people.entries) {
        result.putIfAbsent(entry.key, () => referenceFor(null, entry.value));
      }
    }
    return result;
  }

  /// Las personas de cada obra de [itemIds], en su orden.
  Future<Map<String, List<Contributor>>> _contributorsOf(
    List<String> itemIds,
  ) async {
    final contributors = _db.sourceContributors;
    final values = _db.propertyValues;
    final query =
        _db.select(contributors).join([
            innerJoin(
              values,
              values.id.equalsExp(contributors.propertyValueId),
            ),
          ])
          ..where(contributors.itemId.isIn(itemIds))
          ..orderBy([
            OrderingTerm.asc(contributors.itemId),
            OrderingTerm.asc(contributors.position),
          ]);

    final byItem = <String, List<Contributor>>{};
    for (final row in await query.get()) {
      final link = row.readTable(contributors);
      final person = row.readTable(values);
      (byItem[link.itemId] ??= []).add(
        Contributor(
          name: personNameFor(person),
          role: link.role,
          personId: person.id,
        ),
      );
    }
    return byItem;
  }
}
