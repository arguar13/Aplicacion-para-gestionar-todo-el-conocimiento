import 'package:drift/drift.dart' show QueryRow, Value, Variable;
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/domain/services/reference_codec.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/vault/data/merge/derived_rebuild.dart';
import 'package:sinapsis/features/vault/data/merge/merge_fields.dart';
import 'package:sinapsis/features/vault/domain/entities/merge_conflict.dart';
import 'package:sinapsis/features/vault/domain/repositories/merge_conflict_repository.dart';

/// [MergeConflictRepository] sobre `merge_conflict` (F11).
///
/// Resolver un conflicto es una edición del usuario y se escribe como tal: un
/// campo pasa por `KnowledgeEntryWriter` —con su versión nueva, que una fusión
/// posterior lee como una edición y no como el mismo conflicto—, y el texto
/// cambia cuál de las dos formas es la principal, sin borrar ninguna.
class MergeConflictRepositoryImpl implements MergeConflictRepository {
  MergeConflictRepositoryImpl({
    required AppDatabase database,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _db = database,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  KnowledgeEntryWriter get _writer => KnowledgeEntryWriter(_db, clock: _clock);

  /// Cuánto de un texto se trae para mostrarlo: el resto no cabe en una
  /// tarjeta.
  static const _excerptLength = 600;

  @override
  Stream<List<MergeConflict>> watchPending() {
    // Qué tablas cambian lo que se muestra: el conflicto, el título del
    // elemento, lo que está en uso hoy y los nombres de los espacios.
    final query = _db.customSelect(
      '''
      SELECT c.id AS id, c.item_id AS item_id, c.field_name AS field_name,
             c.local_value AS local_value, c.incoming_value AS incoming_value,
             c.other_rendition_id AS other_rendition_id,
             c.local_updated_at AS local_at, c.local_device_id AS local_dev,
             c.incoming_updated_at AS incoming_at,
             c.incoming_device_id AS incoming_dev,
             c.detected_at AS detected_at,
             i.title AS title, i.deleted_at IS NOT NULL AS in_trash
        FROM merge_conflict c JOIN item i ON i.id = c.item_id
       WHERE c.resolved_at IS NULL
       ORDER BY c.detected_at DESC, c.id''',
      readsFrom: {
        _db.mergeConflicts,
        _db.knowledgeEntries,
        _db.knowledgeNotes,
        _db.knowledgeSources,
        _db.sourceReferences,
        _db.sourceContributors,
        _db.renditions,
        _db.spaces,
      },
    );
    return query.watch().asyncMap(
      (rows) async => [for (final row in rows) await _conflict(row)],
    );
  }

  Future<MergeConflict> _conflict(QueryRow row) async {
    final field = row.read<String>('field_name');
    final itemId = row.read<String>('item_id');
    final isText = EntryField.isRendition(field);

    final MergeConflictVersion local;
    final MergeConflictVersion incoming;
    if (isText) {
      local = await _textVersion(
        EntryField.renditionIdOf(field),
        row.read<String?>('local_dev'),
        _at(row.read<int?>('local_at')),
      );
      incoming = await _textVersion(
        row.read<String?>('other_rendition_id'),
        row.read<String?>('incoming_dev'),
        _at(row.read<int?>('incoming_at')),
      );
    } else {
      final live = await _liveValue(itemId, field);
      local = await _fieldVersion(
        field,
        row.read<String?>('local_value'),
        row.read<String?>('local_dev'),
        _at(row.read<int?>('local_at')),
        live,
      );
      incoming = await _fieldVersion(
        field,
        row.read<String?>('incoming_value'),
        row.read<String?>('incoming_dev'),
        _at(row.read<int?>('incoming_at')),
        live,
      );
    }

    return MergeConflict(
      id: row.read<String>('id'),
      itemId: itemId,
      itemTitle: row.read<String>('title'),
      fieldName: field,
      kind: isText ? MergeConflictKind.text : MergeConflictKind.field,
      local: local,
      incoming: incoming,
      detectedAt: _at(row.read<int>('detected_at'))!,
      itemInTrash: row.read<int>('in_trash') == 1,
    );
  }

  Future<MergeConflictVersion> _textVersion(
    String? renditionId,
    String? deviceId,
    DateTime? at,
  ) async {
    if (renditionId == null) {
      return MergeConflictVersion(deviceId: deviceId, at: at);
    }
    final rows = await _db
        .customSelect(
          'SELECT substr(content, 1, $_excerptLength) AS excerpt, '
          'length(content) AS length, is_primary FROM renditions WHERE id = ?',
          variables: [Variable<String>(renditionId)],
        )
        .get();
    if (rows.isEmpty) return MergeConflictVersion(deviceId: deviceId, at: at);
    final row = rows.single;
    return MergeConflictVersion(
      text: row.read<String?>('excerpt'),
      length: row.read<int?>('length'),
      deviceId: deviceId,
      at: at,
      inUse: row.read<int>('is_primary') == 1,
    );
  }

  Future<MergeConflictVersion> _fieldVersion(
    String field,
    String? value,
    String? deviceId,
    DateTime? at,
    String? live,
  ) async {
    DateTime? date;
    if (field == EntryField.deletedAt || field == EntryField.publishedAt) {
      final seconds = value == null ? null : int.tryParse(value);
      date = _at(seconds);
    }
    String? spaceName;
    if (field == EntryField.spaceId && value != null) {
      final rows = await _db
          .customSelect(
            'SELECT name FROM spaces WHERE id = ?',
            variables: [Variable<String>(value)],
          )
          .get();
      spaceName = rows.isEmpty ? null : rows.single.read<String>('name');
    }
    return MergeConflictVersion(
      text: value,
      date: date,
      spaceName: spaceName,
      deviceId: deviceId,
      at: at,
      inUse: value == live,
    );
  }

  /// El valor que tiene ahora el campo del elemento, como texto.
  Future<String?> _liveValue(String itemId, String field) async {
    final mapped = mergeFieldNamed(field);
    if (mapped == null) return null;
    // Los datos bibliográficos no son una columna: se comparan como el texto
    // con que se guardó la versión.
    if (mapped.isComposite) {
      final reference = await ReferenceReader(_db).read(itemId);
      return reference.isEmpty ? null : encodeReference(reference);
    }
    final rows = await _db
        .customSelect(
          'SELECT CAST(t.${mapped.column} AS TEXT) AS value '
          'FROM ${mapped.table} t WHERE t.${mapped.keyColumn} = ?',
          variables: [Variable<String>(itemId)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<String?>('value');
  }

  @override
  Future<Either<Failure, Unit>> resolve(
    String conflictId,
    MergeConflictChoice choice,
  ) async {
    try {
      await _db.transaction(() async {
        final conflict = await (_db.select(
          _db.mergeConflicts,
        )..where((c) => c.id.equals(conflictId))).getSingleOrNull();
        if (conflict == null || conflict.resolvedAt != null) return;

        if (EntryField.isRendition(conflict.fieldName)) {
          if (choice == MergeConflictChoice.useIncoming) {
            await _useOtherText(conflict);
          }
        } else {
          await _writer.setFieldFromText(
            conflict.itemId,
            conflict.fieldName,
            _valueFor(conflict, choice),
          );
        }

        await (_db.update(
          _db.mergeConflicts,
        )..where((c) => c.id.equals(conflictId))).write(
          MergeConflictsCompanion(
            resolvedAt: Value(_clock()),
            resolution: Value(choice.name),
          ),
        );
      });
      return right(unit);
    } on _NotApplicable catch (e) {
      return left(Failure.validation(message: e.message));
      // Cualquier otra cosa es un fallo de la base: la transacción se revirtió
      // y el conflicto sigue pendiente.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.unexpected(message: '$e'));
    }
  }

  /// El valor que deja [choice] en un campo corto.
  String? _valueFor(MergeConflictRow conflict, MergeConflictChoice choice) {
    switch (choice) {
      case MergeConflictChoice.keepLocal:
        return conflict.localValue;
      case MergeConflictChoice.useIncoming:
        return conflict.incomingValue;
      case MergeConflictChoice.keepBoth:
        if (conflict.fieldName != EntryField.notes &&
            conflict.fieldName != EntryField.subtitle) {
          throw const _NotApplicable(
            'Solo un texto libre puede quedarse con las dos versiones.',
          );
        }
        final parts = <String>[
          for (final part in [conflict.localValue, conflict.incomingValue])
            if (part != null && part.trim().isNotEmpty) part,
        ];
        return parts.toSet().join('\n\n');
    }
  }

  /// Pasa a ser el texto en uso el de la otra versión, y el de acá queda como
  /// otra forma: se intercambian cuál de las dos es la principal. Ninguna se
  /// borra.
  Future<void> _useOtherText(MergeConflictRow conflict) async {
    final otherId = conflict.otherRenditionId;
    // La otra versión ya no está: no hay a qué pasar.
    if (otherId == null) return;
    final currentId = EntryField.renditionIdOf(conflict.fieldName);

    final rows = await (_db.select(
      _db.renditions,
    )..where((r) => r.id.isIn([currentId, otherId]))).get();
    final current = rows.where((r) => r.id == currentId).firstOrNull;
    final other = rows.where((r) => r.id == otherId).firstOrNull;
    if (current == null || other == null) return;

    await (_db.update(_db.renditions)..where((r) => r.id.equals(currentId)))
        .write(RenditionsCompanion(isPrimary: Value(other.isPrimary)));
    await (_db.update(_db.renditions)..where((r) => r.id.equals(otherId)))
        .write(RenditionsCompanion(isPrimary: Value(current.isPrimary)));

    // Cambió el texto de la fuente o de la nota: lo derivado de él se rehace,
    // igual que al guardar.
    final item =
        (await _db
                .customSelect(
                  'SELECT kind, title FROM item WHERE id = ?',
                  variables: [Variable<String>(conflict.itemId)],
                )
                .get())
            .firstOrNull;
    if (item == null) return;
    if (item.read<String>('kind') == 'note') {
      await relinkNoteLinks(
        _db,
        itemId: conflict.itemId,
        title: item.read<String>('title'),
        ids: _ids,
        clock: _clock,
      );
    } else {
      await chunkAndPersistSource(
        _db,
        itemId: conflict.itemId,
        ids: _ids,
        reportedBy: 'f11_conflict',
      );
    }
  }

  static DateTime? _at(int? seconds) => seconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

/// Se pidió algo que no tiene sentido para ese conflicto.
class _NotApplicable implements Exception {
  const _NotApplicable(this.message);

  final String message;
}
