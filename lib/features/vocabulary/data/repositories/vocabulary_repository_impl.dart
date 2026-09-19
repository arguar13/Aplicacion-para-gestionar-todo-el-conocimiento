import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/property_value_merge.dart';
import 'package:sinapsis/core/database/vocabulary_lookup.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_operation.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/domain/repositories/vocabulary_repository.dart';

class VocabularyRepositoryImpl implements VocabularyRepository {
  const VocabularyRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  // ---------------------------------------------------------------------
  // Estadísticas
  // ---------------------------------------------------------------------

  @override
  Stream<List<VocabularyValueStat>> watchValueStats() {
    return watchQuery(
      db: _db,
      tables: [
        _db.propertyValues,
        _db.itemPropertyValues,
        _db.propertyAliases,
        _db.propertyDefinitions,
      ],
      read: () async {
        final definitions = {
          for (final d in await _db.select(_db.propertyDefinitions).get())
            d.id: d,
        };
        final values = await _db.select(_db.propertyValues).get();
        final usage = await _countBy(
          _db.itemPropertyValues,
          _db.itemPropertyValues.propertyValueId,
        );
        final aliases = await _countBy(
          _db.propertyAliases,
          _db.propertyAliases.propertyValueId,
        );

        final stats = [
          for (final value in values)
            if (definitions[value.definitionId] case final definition?)
              VocabularyValueStat(
                id: value.id,
                label: value.value,
                definitionId: definition.id,
                definitionName: definition.name,
                isText: definition.type == PropertyValueType.text,
                usage: usage[value.id] ?? 0,
                aliasCount: aliases[value.id] ?? 0,
              ),
        ];

        // Alfabético SIN acentos —"Época" antes que "Tema"—: ordenar por el
        // texto tal cual manda la é después de la z. La clave se calcula una
        // vez por elemento, no en cada comparación.
        final labelKey = {
          for (final s in stats) s.id: normalizeVocabularyLabel(s.label),
        };
        final categoryKey = {
          for (final d in definitions.values)
            d.id: normalizeVocabularyLabel(d.name),
        };
        stats.sort((a, b) {
          final byCategory = categoryKey[a.definitionId]!.compareTo(
            categoryKey[b.definitionId]!,
          );
          if (byCategory != 0) return byCategory;
          return labelKey[a.id]!.compareTo(labelKey[b.id]!);
        });
        return stats;
      },
      telemetry: _telemetry,
      hint: 'VocabularyRepositoryImpl.watchValueStats',
    );
  }

  @override
  Stream<List<VocabularyCategoryStat>> watchCategoryStats() {
    return watchQuery(
      db: _db,
      tables: [_db.propertyDefinitions, _db.propertyValues],
      read: () async {
        final definitions = await _db.select(_db.propertyDefinitions).get();
        final counts = await _countBy(
          _db.propertyValues,
          _db.propertyValues.definitionId,
        );
        final stats = [
          for (final d in definitions)
            VocabularyCategoryStat(
              id: d.id,
              name: d.name,
              isSystem: d.isSystem,
              valueCount: counts[d.id] ?? 0,
            ),
        ];
        final nameKey = {
          for (final c in stats) c.id: normalizeVocabularyLabel(c.name),
        };
        return stats..sort((a, b) => nameKey[a.id]!.compareTo(nameKey[b.id]!));
      },
      telemetry: _telemetry,
      hint: 'VocabularyRepositoryImpl.watchCategoryStats',
    );
  }

  /// Cuántas filas de [table] hay por cada valor de [column], en una sola
  /// consulta: pedirlo uno por uno serían miles de consultas con un
  /// vocabulario grande.
  Future<Map<String, int>> _countBy<T extends HasResultSet, D>(
    ResultSetImplementation<T, D> table,
    GeneratedColumn<String> column,
  ) async {
    final count = countAll();
    final rows =
        await (_db.selectOnly(table)
              ..addColumns([column, count])
              ..groupBy([column]))
            .get();
    return {for (final row in rows) row.read(column)!: row.read(count) ?? 0};
  }

  // ---------------------------------------------------------------------
  // Fusionar
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, MergePreview>> previewMerge({
    required String keepId,
    required List<String> discardIds,
  }) async {
    try {
      final loaded = await _loadMerge(keepId, discardIds);
      if (loaded.isLeft()) return left(loaded.getLeft().toNullable()!);
      final ids = loaded.getRight().toNullable()!.discards.map((v) => v.id);

      final rows =
          await (_db.selectOnly(_db.itemPropertyValues, distinct: true)
                ..addColumns([_db.itemPropertyValues.itemId])
                ..where(_db.itemPropertyValues.propertyValueId.isIn(ids)))
              .get();

      return right(
        MergePreview(valueCount: ids.length, affectedItems: rows.length),
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'VocabularyRepositoryImpl.previewMerge'),
      );
    }
  }

  @override
  Future<Either<Failure, VocabularyOperation>> mergeValues({
    required String keepId,
    required List<String> discardIds,
  }) async {
    try {
      final loaded = await _loadMerge(keepId, discardIds);
      if (loaded.isLeft()) return left(loaded.getLeft().toNullable()!);
      final (:keep, :discards) = loaded.getRight().toNullable()!;

      // Atómico: si una fusión del lote falla, revierte la transacción y el
      // vocabulario queda como estaba.
      final undos = await _db.transaction(() async {
        final done = <PropertyValueMergeUndo>[];
        for (final discard in discards) {
          // Se relee cada vez: una fusión anterior del lote pudo haber
          // movido cosas, y un valor que desapareció a la mitad tiene que
          // hacer fallar el lote entero, no saltearse en silencio.
          final keepNow = await _valueById(keep.id);
          final discardNow = await _valueById(discard.id);
          done.add(
            await mergePropertyValueRows(
              _db,
              keep: keepNow,
              discard: discardNow,
              ids: _ids,
              clock: _clock,
            ),
          );
        }
        return done;
      });

      return right(_MergeOperation(keepLabel: keep.value, undos: undos));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'VocabularyRepositoryImpl.mergeValues'),
      );
    }
  }

  /// Lee y valida lo que toda fusión necesita: que haya algo que fusionar,
  /// que el que se conserva no esté entre los descartados, y que todos
  /// existan y sean de la misma categoría.
  Future<
    Either<Failure, ({PropertyValueRow keep, List<PropertyValueRow> discards})>
  >
  _loadMerge(String keepId, List<String> discardIds) async {
    if (discardIds.isEmpty) {
      return left(
        const Failure.validation(
          message: 'Elegí al menos un valor para fusionar.',
        ),
      );
    }
    if (discardIds.contains(keepId)) {
      return left(
        const Failure.validation(
          message: 'Un valor no se puede fusionar consigo mismo.',
        ),
      );
    }
    final distinct = {...discardIds}.toList();

    final keep = await (_db.select(
      _db.propertyValues,
    )..where((v) => v.id.equals(keepId))).getSingleOrNull();
    final discards = await (_db.select(
      _db.propertyValues,
    )..where((v) => v.id.isIn(distinct))).get();
    if (keep == null || discards.length != distinct.length) {
      return left(
        const Failure.unexpected(
          message:
              'Uno de los valores ya no existe; puede que se haya borrado.',
        ),
      );
    }
    if (discards.any((v) => v.definitionId != keep.definitionId)) {
      return left(
        const Failure.validation(
          message: 'No se puede fusionar valores de categorías distintas.',
        ),
      );
    }

    // En el orden en que se pidieron, no en el que la base los devuelva.
    final byId = {for (final v in discards) v.id: v};
    return right((
      keep: keep,
      discards: [for (final id in distinct) byId[id]!],
    ));
  }

  // ---------------------------------------------------------------------
  // Renombrar
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, VocabularyOperation>> renameValue({
    required String id,
    required String label,
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El valor no puede quedar vacío.'),
      );
    }

    try {
      final current = await (_db.select(
        _db.propertyValues,
      )..where((v) => v.id.equals(id))).getSingleOrNull();
      if (current == null) {
        return left(
          const Failure.unexpected(
            message: 'El valor ya no existe; puede que se haya borrado.',
          ),
        );
      }

      // El propio valor queda afuera de la comparación de labels: cambiarle
      // el acento o las mayúsculas a su nombre es corregir la grafía, no
      // chocar consigo mismo. Un alias suyo sí bloquea el nombre.
      final clash = await findValueByLabelOrAlias(
        _db,
        current.definitionId,
        trimmed,
        excludingValueId: id,
      );
      if (clash != null) {
        return left(
          Failure.validation(message: 'Ya existe un valor "$trimmed".'),
        );
      }

      await (_db.update(_db.propertyValues)..where((v) => v.id.equals(id)))
          .write(PropertyValuesCompanion(value: Value(trimmed)));

      return right(
        _RenameOperation(
          valueId: id,
          oldLabel: current.value,
          newLabel: trimmed,
          affectedItems: await _usageOf(id),
        ),
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'VocabularyRepositoryImpl.renameValue'),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Borrar
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, VocabularyOperation>> deleteUnusedValues(
    List<String> ids,
  ) async {
    final distinct = {...ids}.toList();
    if (distinct.isEmpty) {
      return left(
        const Failure.validation(message: 'Elegí al menos un valor.'),
      );
    }

    try {
      final operation = await _db.transaction(() async {
        final values = await (_db.select(
          _db.propertyValues,
        )..where((v) => v.id.isIn(distinct))).get();
        if (values.length != distinct.length) {
          throw const _Rejected(
            Failure.unexpected(
              message:
                  'Uno de los valores ya no existe; puede que se haya borrado.',
            ),
          );
        }
        for (final value in values) {
          final usage = await _usageOf(value.id);
          if (usage > 0) {
            throw _Rejected(
              Failure.validation(
                message:
                    '"${value.value}" está en uso en $usage elementos: no se '
                    'borra.',
              ),
            );
          }
        }

        final aliases = await (_db.select(
          _db.propertyAliases,
        )..where((a) => a.propertyValueId.isIn(distinct))).get();
        // Los alias se borran a mano y no por la cascada de la FK: que la
        // operación sea reversible no puede depender de un pragma.
        await (_db.delete(
          _db.propertyAliases,
        )..where((a) => a.propertyValueId.isIn(distinct))).go();
        await (_db.delete(
          _db.propertyValues,
        )..where((v) => v.id.isIn(distinct))).go();

        return _DeleteOperation(values: values, aliases: aliases);
      });
      return right(operation);
    } on _Rejected catch (rejected) {
      return left(rejected.failure);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'VocabularyRepositoryImpl.deleteUnusedValues',
        ),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Alias
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, VocabularyOperation>> addAlias({
    required String valueId,
    required String alias,
  }) async {
    final trimmed = alias.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El alias no puede quedar vacío.'),
      );
    }

    try {
      final value = await (_db.select(
        _db.propertyValues,
      )..where((v) => v.id.equals(valueId))).getSingleOrNull();
      if (value == null) {
        return left(
          const Failure.unexpected(
            message: 'El valor ya no existe; puede que se haya borrado.',
          ),
        );
      }

      // Ni el nombre de un valor —el propio incluido: un alias igual a su
      // valor no agrega nada— ni otro alias de la categoría.
      final clash = await findValueByLabelOrAlias(
        _db,
        value.definitionId,
        trimmed,
      );
      if (clash != null) {
        return left(
          Failure.validation(
            message: '"$trimmed" ya existe en esta categoría.',
          ),
        );
      }

      final row = PropertyAliasRow(
        id: _ids.next(),
        propertyValueId: valueId,
        definitionId: value.definitionId,
        alias: trimmed,
        createdAt: _clock(),
      );
      await _db.into(_db.propertyAliases).insert(row);

      return right(_AliasOperation(alias: row, added: true));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'VocabularyRepositoryImpl.addAlias'),
      );
    }
  }

  @override
  Future<Either<Failure, VocabularyOperation>> removeAlias(
    String aliasId,
  ) async {
    try {
      final row = await (_db.select(
        _db.propertyAliases,
      )..where((a) => a.id.equals(aliasId))).getSingleOrNull();
      if (row == null) {
        return left(
          const Failure.unexpected(
            message: 'El alias ya no existe; puede que se haya borrado.',
          ),
        );
      }

      await (_db.delete(
        _db.propertyAliases,
      )..where((a) => a.id.equals(aliasId))).go();

      return right(_AliasOperation(alias: row, added: false));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'VocabularyRepositoryImpl.removeAlias'),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Deshacer
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, Unit>> undo(VocabularyOperation operation) async {
    try {
      await _db.transaction(() async {
        switch (operation) {
          case _MergeOperation():
            // En el orden inverso al que se hicieron.
            for (final undo in operation.undos.reversed) {
              await undoPropertyValueMerge(_db, undo);
            }
          case _RenameOperation():
            await _undoRename(operation);
          case _DeleteOperation():
            await _undoDelete(operation);
          case _AliasOperation():
            await _undoAlias(operation);
          default:
            throw const _Rejected(
              Failure.validation(
                message: 'Esta operación no viene de este repositorio.',
              ),
            );
        }
      });
      return right(unit);
    } on MergeUndoConflict catch (conflict) {
      return left(Failure.validation(message: conflict.message));
    } on _Rejected catch (rejected) {
      return left(rejected.failure);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'VocabularyRepositoryImpl.undo'));
    }
  }

  Future<void> _undoRename(_RenameOperation op) async {
    final current = await (_db.select(
      _db.propertyValues,
    )..where((v) => v.id.equals(op.valueId))).getSingleOrNull();
    if (current == null || current.value != op.newLabel) {
      throw const MergeUndoConflict(
        'El valor cambió de nombre otra vez o ya no existe.',
      );
    }
    // Solo un conflicto de INTEGRIDAD: el mismo nombre para el índice único.
    // No la comparación sin acentos: el vocabulario de antes pudo tener
    // "Roma" y "Róma" a la vez —justo lo que esta pantalla existe para
    // limpiar—, y deshacer tiene que poder volver a ese estado.
    final others =
        await (_db.select(_db.propertyValues)..where(
              (v) =>
                  v.definitionId.equals(current.definitionId) &
                  v.id.equals(op.valueId).not(),
            ))
            .get();
    if (others.any((v) => _sameForIndex(v.value, op.oldLabel))) {
      throw MergeUndoConflict(
        'Ya existe otro valor "${op.oldLabel}": no se puede volver a ese '
        'nombre.',
      );
    }
    await (_db.update(_db.propertyValues)
          ..where((v) => v.id.equals(op.valueId)))
        .write(PropertyValuesCompanion(value: Value(op.oldLabel)));
  }

  Future<void> _undoDelete(_DeleteOperation op) async {
    final ids = op.values.map((v) => v.id).toList();
    final back = await (_db.select(
      _db.propertyValues,
    )..where((v) => v.id.isIn(ids))).get();
    if (back.isNotEmpty) {
      throw const MergeUndoConflict('Un valor borrado ya fue recreado.');
    }
    // Solo un conflicto de integridad, ver `_undoRename`.
    for (final value in op.values) {
      final same = await (_db.select(
        _db.propertyValues,
      )..where((v) => v.definitionId.equals(value.definitionId))).get();
      if (same.any((v) => _sameForIndex(v.value, value.value))) {
        throw MergeUndoConflict(
          'Ya existe un valor "${value.value}": no se puede recrear.',
        );
      }
    }
    for (final value in op.values) {
      await _db.into(_db.propertyValues).insert(value);
    }
    for (final alias in op.aliases) {
      await _db.into(_db.propertyAliases).insert(alias);
    }
  }

  Future<void> _undoAlias(_AliasOperation op) async {
    if (op.added) {
      // Deshacer un alias agregado es borrarlo; si ya no está, no hay nada
      // que deshacer.
      await (_db.delete(
        _db.propertyAliases,
      )..where((a) => a.id.equals(op.alias.id))).go();
      return;
    }

    final value = await (_db.select(
      _db.propertyValues,
    )..where((v) => v.id.equals(op.alias.propertyValueId))).getSingleOrNull();
    if (value == null) {
      throw const MergeUndoConflict('El valor de ese alias ya no existe.');
    }
    // Solo un conflicto de integridad, ver `_undoRename`: un alias puede
    // haber convivido con un valor de nombre casi igual —una fusión deja el
    // "Róma" descartado como alias de "Roma"—.
    final aliases = await (_db.select(
      _db.propertyAliases,
    )..where((a) => a.definitionId.equals(op.alias.definitionId))).get();
    if (aliases.any((a) => _sameForIndex(a.alias, op.alias.alias))) {
      throw MergeUndoConflict(
        '"${op.alias.alias}" ya existe en esta categoría: no se puede '
        'volver a poner.',
      );
    }
    await _db.into(_db.propertyAliases).insert(op.alias);
  }

  // ---------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------

  /// Si el índice único de SQLite ve iguales a [a] y [b]: sin distinguir
  /// mayúsculas ASCII, y nada más —`COLLATE NOCASE` no conoce acentos ni
  /// letras fuera de ASCII—.
  bool _sameForIndex(String a, String b) => _asciiLower(a) == _asciiLower(b);

  String _asciiLower(String value) => value.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => match[0]!.toLowerCase(),
  );

  Future<PropertyValueRow> _valueById(String id) => (_db.select(
    _db.propertyValues,
  )..where((v) => v.id.equals(id))).getSingle();

  /// En cuántos elementos está puesto el valor.
  Future<int> _usageOf(String valueId) async {
    final count = _db.itemPropertyValues.itemId.count();
    final row =
        await (_db.selectOnly(_db.itemPropertyValues)
              ..addColumns([count])
              ..where(_db.itemPropertyValues.propertyValueId.equals(valueId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Catch-all deliberado, igual que en el resto de la app: un `TypeError`
  /// es un `Error`, no un `Exception`, y atrapar solo `Exception` lo dejaría
  /// escapar. Siempre es un defecto, así que se reporta.
  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}

/// Una negativa con motivo, lanzada desde adentro de una transacción para que
/// revierta: se convierte de vuelta en el [Failure] que la describe.
class _Rejected implements Exception {
  const _Rejected(this.failure);

  final Failure failure;
}

class _MergeOperation implements VocabularyOperation {
  _MergeOperation({required this.keepLabel, required this.undos});

  final String keepLabel;
  final List<PropertyValueMergeUndo> undos;

  @override
  VocabularyOperationKind get kind => VocabularyOperationKind.merge;

  @override
  int get valueCount => undos.length;

  @override
  String get label => keepLabel;

  @override
  int get affectedItems => {
    for (final undo in undos) ...[
      for (final a in undo.movedAssignments) a.itemId,
      for (final a in undo.droppedAssignments) a.itemId,
    ],
  }.length;
}

class _RenameOperation implements VocabularyOperation {
  _RenameOperation({
    required this.valueId,
    required this.oldLabel,
    required this.newLabel,
    required this.affectedItems,
  });

  final String valueId;
  final String oldLabel;
  final String newLabel;

  @override
  final int affectedItems;

  @override
  VocabularyOperationKind get kind => VocabularyOperationKind.rename;

  @override
  int get valueCount => 1;

  @override
  String get label => newLabel;
}

class _DeleteOperation implements VocabularyOperation {
  _DeleteOperation({required this.values, required this.aliases});

  final List<PropertyValueRow> values;
  final List<PropertyAliasRow> aliases;

  @override
  VocabularyOperationKind get kind => VocabularyOperationKind.delete;

  @override
  int get valueCount => values.length;

  @override
  String get label => values.first.value;

  /// Solo se borra lo que no tiene uso: no afecta a ningún elemento.
  @override
  int get affectedItems => 0;
}

class _AliasOperation implements VocabularyOperation {
  _AliasOperation({required this.alias, required this.added});

  final PropertyAliasRow alias;
  final bool added;

  @override
  VocabularyOperationKind get kind => added
      ? VocabularyOperationKind.addAlias
      : VocabularyOperationKind.removeAlias;

  @override
  int get valueCount => 1;

  @override
  String get label => alias.alias;

  @override
  int get affectedItems => 0;
}
