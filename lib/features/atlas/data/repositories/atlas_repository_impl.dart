import 'dart:async';

import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/atlas/data/repositories/atlas_query_sql.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';
import 'package:sinapsis/features/atlas/domain/repositories/atlas_repository.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_aggregator.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';

class AtlasRepositoryImpl implements AtlasRepository {
  AtlasRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _clock = clock {
    // Suscripta desde el nacimiento, ANTES que cualquier `watchAtlas`: drift
    // avisa a sus oyentes en el orden en que se suscribieron, así que cuando
    // un `watchAtlas` se entera de una escritura y vuelve a leer, la caché ya
    // sabe que no vale.
    _writes = _db
        .tableUpdates(TableUpdateQuery.onAllTables(_tables))
        .listen((_) => _generation++);
  }

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final Clock _clock;

  late final StreamSubscription<void> _writes;

  /// Cuántas veces cambió algo que afecta al Atlas desde que nació el
  /// repositorio. Una entrada de la caché vale solo si se calculó con la misma
  /// cuenta que hay ahora.
  int _generation = 0;

  final Map<String, ({int generation, AtlasSnapshot snapshot})> _cache = {};

  /// Cuántas veces se calculó un Atlas de verdad, sin contar los que salieron
  /// de la caché. Existe para que las pruebas y las mediciones puedan decir
  /// «no se recalculó».
  int computations = 0;

  late final List<TableInfo<dynamic, dynamic>> _tables = atlasTables(_db);

  /// Deja de escuchar las escrituras. Lo llama quien creó el repositorio al
  /// terminar.
  Future<void> dispose() => _writes.cancel();

  @override
  Stream<AtlasSnapshot> watchAtlas(String definitionId) {
    return watchQuery(
      db: _db,
      tables: _tables,
      read: () => snapshot(definitionId),
      telemetry: _telemetry,
      hint: 'AtlasRepositoryImpl.watchAtlas',
    );
  }

  @override
  Future<AtlasSnapshot> snapshot(String definitionId) async {
    // El aviso de una escritura llega un instante DESPUÉS de que la escritura
    // termina —medido: a quien escribe y en seguida pide el Atlas, la cuenta
    // todavía no le refleja su propio cambio—. Un turno del bucle de eventos
    // deja entregar los avisos en camino; sin él, la caché devolvería el Atlas
    // de antes de lo que se acaba de guardar.
    await Future<void>.delayed(Duration.zero);

    final cached = _cache[definitionId];
    if (cached != null && cached.generation == _generation) {
      return cached.snapshot;
    }

    // La cuenta de ANTES de leer: si algo cambia mientras se calcula, la
    // entrada queda vieja de nacimiento y la próxima lectura la recalcula.
    final generation = _generation;
    final computed = await _compute(definitionId);
    _cache[definitionId] = (generation: generation, snapshot: computed);
    return computed;
  }

  Future<AtlasSnapshot> _compute(String definitionId) async {
    computations++;

    final definitions = _db.propertyDefinitions;
    final definition = await (_db.select(
      definitions,
    )..where((d) => d.id.equals(definitionId))).getSingleOrNull();
    if (definition == null) return AtlasSnapshot.empty(definitionId);

    final values = await _readValues(definitionId);
    final counts = aggregateBranches(
      values: values,
      items: await _readItems(definitionId),
    );
    final mapNotes = await _readMapNotes(definitionId);

    return buildAtlas(
      definitionId: definitionId,
      definitionName: definition.name,
      values: values,
      counts: counts,
      mapNotes: mapNotes,
      now: _clock(),
    );
  }

  Future<List<AtlasValueRow>> _readValues(String definitionId) async {
    final values = _db.propertyValues;
    final rows =
        await (_db.selectOnly(values)
              ..addColumns([values.id, values.value, values.parentId])
              ..where(values.definitionId.equals(definitionId)))
            .get();
    return [
      for (final row in rows)
        AtlasValueRow(
          id: row.read(values.id)!,
          label: row.read(values.value)!,
          parentId: row.read(values.parentId),
        ),
    ];
  }

  /// Cada elemento vivo con lo que el Atlas necesita de él: una fila por
  /// elemento.
  Future<List<AtlasItemFacts>> _readItems(String definitionId) async {
    final rows = await _db
        .customSelect(
          atlasItemsSql,
          variables: [
            Variable.withString(definitionId),
            Variable.withString(kFechaDelHechoCategoryName),
          ],
          readsFrom: _tables.toSet(),
        )
        .get();
    // Las columnas se toman de `data` y no con `read`: con 10.000 filas, la
    // conversión tipada de cada columna era una parte grande del tiempo.
    final items = <AtlasItemFacts>[];
    for (final row in rows) {
      final data = row.data;
      // Sin ningún valor de la categoría, no cuenta en ninguna rama.
      final valueIds = data['value_ids'] as String?;
      if (valueIds == null) continue;
      items.add(
        AtlasItemFacts(
          isSource: data['kind'] == ItemKind.source.name,
          noteKind: _named(NoteKind.values, data['note_kind'] as String?),
          maturity: _named(NoteMaturity.values, data['maturity'] as String?),
          // La fecha sí por `read`: cómo se guarda un instante lo sabe drift.
          updatedAt: row.read<DateTime>('updated_at'),
          firstYear: data['year_from'] as int?,
          lastYear: data['year_to'] as int?,
          valueIds: valueIds.split(atlasValueIdSeparator),
        ),
      );
    }
    return items;
  }

  /// Las notas mapa vivas, con el valor de la categoría al que están
  /// asignadas: una fila por cada asignación.
  Future<List<AtlasMapNoteRow>> _readMapNotes(String definitionId) async {
    final rows = await _db
        .customSelect(
          atlasMapNotesSql,
          variables: [Variable.withString(definitionId)],
          readsFrom: _tables.toSet(),
        )
        .get();
    return [
      for (final row in rows)
        AtlasMapNoteRow(
          noteId: row.data['note_id'] as String,
          title: row.data['title'] as String,
          valueId: row.data['value_id'] as String,
        ),
    ];
  }
}

/// El valor de [values] que se llama [name], o `null` si [name] es `null`.
T? _named<T extends Enum>(List<T> values, String? name) =>
    name == null ? null : values.byName(name);
