import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/util/clock.dart';

/// El único lugar que escribe los campos de un elemento —`item`, su `note` y su
/// `source`— (F11).
///
/// Escribirlos desde varios lados dejaba tres cosas sin dueño: `rev` y
/// `deviceId` eran columnas fantasma, y no había cómo saber quién había
/// cambiado qué. Ahora cada modificación pasa por acá y hace lo mismo:
///
/// - sube `rev` y escribe el `deviceId` de esta instalación, **solo si algún
///   campo cambió de verdad**: un guardado que no cambia nada —el pipeline de
///   procesamiento guarda más de una vez el mismo elemento— no ensucia la
///   historia;
/// - y registra en `field_version` cada campo que cambió, con el linaje: sin
///   fila previa, la cadena de ediciones es propia (`base` nula); si la última
///   edición fue de este mismo dispositivo, se conserva su `base`; y si fue de
///   OTRO —una versión que llegó por una fusión—, esa versión pasa a ser la
///   `base` de la nueva. Es lo que le permite a una fusión decir «esta edición
///   partió de la tuya» en vez de marcar un conflicto.
///
/// Un test recorre `lib` y falla si otro archivo escribe estas tablas.
class KnowledgeEntryWriter {
  const KnowledgeEntryWriter(this._db, {Clock clock = DateTime.now})
    : _clock = clock;

  final AppDatabase _db;
  final Clock _clock;

  String get _deviceId => _db.deviceId;

  /// Escribe el elemento [item]: la fila de `item` y, según sea, su `source` o
  /// su `note`. Lo único que se escribe del elemento en sí.
  ///
  /// `title`/`subtitle`/`notes`/`spaceId`/`updatedAt` y los campos
  /// estructurales de `source` se sobreescriben siempre: son un reflejo directo
  /// de [item]. `state` —y, para una nota, `noteKind`/`maturity`, y
  /// `contentHash` de una fuente— se preservan si ya existían: los escribe otra
  /// cosa (la Bandeja, `createRelation`, el chunking), nunca este método. Nunca
  /// toca `deletedAt`: borrar y restaurar tienen sus propias operaciones.
  ///
  /// [changedRenditions] son los ids de las formas cuyo texto —o archivo— este
  /// guardado crea o cambia. El texto en sí lo escribe quien guarda las formas
  /// (que es también quien puede compararlo con lo que había): acá solo se
  /// versiona, para que el `rev` suba UNA vez por guardado y no una por forma.
  Future<void> upsert(
    KnowledgeItem item, {
    Iterable<String> changedRenditions = const [],
  }) async {
    await _db.transaction(() async {
      final now = _clock();
      final existing = await (_db.select(
        _db.knowledgeEntries,
      )..where((e) => e.id.equals(item.id))).getSingleOrNull();
      final existingSource = await (_db.select(
        _db.knowledgeSources,
      )..where((s) => s.itemId.equals(item.id))).getSingleOrNull();

      final kind = itemKindFor(item.source.kind);
      final state = nextMirrorState(
        current: existing?.state,
        processingState: item.processingState,
      );

      // Lo que cambió, por campo. Contra «nada» —un elemento nuevo— cambia todo
      // lo que tiene un valor: crearlo es la primera versión de cada campo.
      final changed = <String>[
        if (existing?.title != item.title) EntryField.title,
        if (existing?.subtitle != item.subtitle) EntryField.subtitle,
        if (existing?.notes != item.notes) EntryField.notes,
        if (existing?.spaceId != item.spaceId) EntryField.spaceId,
        if (existing?.state != state) EntryField.state,
        ..._changedSourceFields(item, existingSource),
        for (final id in changedRenditions) EntryField.rendition(id),
      ];

      if (existing == null) {
        await _db
            .into(_db.knowledgeEntries)
            .insert(
              KnowledgeEntriesCompanion.insert(
                id: item.id,
                title: item.title,
                subtitle: Value(item.subtitle),
                notes: Value(item.notes),
                spaceId: Value(item.spaceId),
                kind: kind,
                state: state,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                deviceId: _deviceId,
              ),
            );
      } else {
        await (_db.update(
          _db.knowledgeEntries,
        )..where((e) => e.id.equals(item.id))).write(
          KnowledgeEntriesCompanion(
            title: Value(item.title),
            subtitle: Value(item.subtitle),
            notes: Value(item.notes),
            spaceId: Value(item.spaceId),
            kind: Value(kind),
            state: Value(state),
            createdAt: Value(item.createdAt),
            updatedAt: Value(item.updatedAt),
            // Solo si algo cambió: ver la documentación de la clase.
            rev: changed.isEmpty
                ? const Value.absent()
                : Value(existing.rev + 1),
            deviceId: changed.isEmpty ? const Value.absent() : Value(_deviceId),
          ),
        );
      }

      await _writeTypedRow(item, kind, existingSource);
      for (final field in changed) {
        await _touch(item.id, field, now);
      }
    });
  }

  /// Cambia el espacio de [itemIds]. Solo los que de verdad lo cambian suben su
  /// `rev` y registran la versión.
  Future<void> setSpace(Iterable<String> itemIds, String? spaceId) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return;
    await _db.transaction(() async {
      final now = _clock();
      for (var start = 0; start < ids.length; start += _idsPerQuery) {
        final slice = ids.skip(start).take(_idsPerQuery).toList();
        final rows = await (_db.select(
          _db.knowledgeEntries,
        )..where((e) => e.id.isIn(slice))).get();
        final changing = [
          for (final row in rows)
            if (row.spaceId != spaceId) row,
        ];
        for (final row in changing) {
          await _writeEntry(
            row,
            KnowledgeEntriesCompanion(spaceId: Value(spaceId)),
          );
          await _touch(row.id, EntryField.spaceId, now);
        }
      }
    });
  }

  /// Cambia el estado de trabajo intelectual de [itemId]. Devuelve `false` si
  /// el elemento no existe.
  Future<bool> setState(String itemId, ItemState to) async {
    return _db.transaction(() async {
      final row = await _entry(itemId);
      if (row == null) return false;
      if (row.state == to) return true;
      await _writeEntry(row, KnowledgeEntriesCompanion(state: Value(to)));
      await _touch(itemId, EntryField.state, _clock());
      return true;
    });
  }

  /// Cambia el subtipo de la nota [itemId]. Devuelve `false` si no existe.
  Future<bool> setNoteKind(String itemId, NoteKind kind) async {
    return _db.transaction(() async {
      final note = await (_db.select(
        _db.knowledgeNotes,
      )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
      if (note == null) return false;
      if (note.noteKind == kind) return true;
      await (_db.update(_db.knowledgeNotes)
            ..where((n) => n.itemId.equals(itemId)))
          .write(KnowledgeNotesCompanion(noteKind: Value(kind)));
      await _bumpEntry(itemId);
      await _touch(itemId, EntryField.noteKind, _clock());
      return true;
    });
  }

  /// Cambia la madurez de la nota [itemId]. Devuelve `false` si no existe.
  Future<bool> setMaturity(String itemId, NoteMaturity maturity) async {
    return _db.transaction(() async {
      final note = await (_db.select(
        _db.knowledgeNotes,
      )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
      if (note == null) return false;
      if (note.maturity == maturity) return true;
      await (_db.update(_db.knowledgeNotes)
            ..where((n) => n.itemId.equals(itemId)))
          .write(KnowledgeNotesCompanion(maturity: Value(maturity)));
      await _bumpEntry(itemId);
      await _touch(itemId, EntryField.maturity, _clock());
      return true;
    });
  }

  /// Cambia el subtítulo y/o las notas libres de [itemId]; lo que no se pasa
  /// no se toca. Devuelve `false` si el elemento no existe.
  ///
  /// Aparte de [upsert] porque quien lo necesita —la fusión de duplicados, que
  /// junta lo que el usuario escribió en los dos— no tiene un `KnowledgeItem`
  /// armado ni tiene por qué volver a escribir sus formas.
  Future<bool> setFreeText(
    String itemId, {
    Value<String?> subtitle = const Value.absent(),
    Value<String?> notes = const Value.absent(),
  }) async {
    return _db.transaction(() async {
      final row = await _entry(itemId);
      if (row == null) return false;
      final changed = [
        if (subtitle.present && row.subtitle != subtitle.value)
          EntryField.subtitle,
        if (notes.present && row.notes != notes.value) EntryField.notes,
      ];
      if (changed.isEmpty) return true;
      final now = _clock();
      await _writeEntry(
        row,
        KnowledgeEntriesCompanion(
          subtitle: subtitle,
          notes: notes,
          updatedAt: Value(now),
        ),
      );
      for (final field in changed) {
        await _touch(itemId, field, now);
      }
      return true;
    });
  }

  /// Manda a la papelera los elementos VIVOS de [itemIds]: les pone
  /// `deletedAt`. Devuelve los que de verdad se mandaron —uno que no existe o
  /// que ya estaba en la papelera no cuenta, y no cambia su fecha—.
  ///
  /// No se borra nada: ni la fila, ni el texto, ni lo que cuelga del elemento,
  /// ni el archivo original. Sube el `rev`, escribe el dispositivo y versiona
  /// `deletedAt`, como cualquier otro cambio: una fusión tiene que poder
  /// distinguir «lo borró el otro» de «lo edité yo».
  Future<List<String>> trash(Iterable<String> itemIds) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return const [];
    return _db.transaction(() async {
      final now = _clock();
      final trashed = <String>[];
      for (var start = 0; start < ids.length; start += _idsPerQuery) {
        final slice = ids.skip(start).take(_idsPerQuery).toList();
        final rows = await (_db.select(
          _db.knowledgeEntries,
        )..where((e) => e.id.isIn(slice) & e.deletedAt.isNull())).get();
        for (final row in rows) {
          await _writeEntry(
            row,
            KnowledgeEntriesCompanion(deletedAt: Value(now)),
          );
          await _touch(row.id, EntryField.deletedAt, now);
          trashed.add(row.id);
        }
      }
      return trashed;
    });
  }

  /// Saca de la papelera los elementos de [itemIds] que están en ella: les
  /// quita `deletedAt`. Devuelve los que de verdad se restauraron.
  Future<List<String>> restore(Iterable<String> itemIds) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return const [];
    return _db.transaction(() async {
      final now = _clock();
      final restored = <String>[];
      for (var start = 0; start < ids.length; start += _idsPerQuery) {
        final slice = ids.skip(start).take(_idsPerQuery).toList();
        final rows = await (_db.select(
          _db.knowledgeEntries,
        )..where((e) => e.id.isIn(slice) & e.deletedAt.isNotNull())).get();
        for (final row in rows) {
          await _writeEntry(
            row,
            const KnowledgeEntriesCompanion(deletedAt: Value(null)),
          );
          await _touch(row.id, EntryField.deletedAt, now);
          restored.add(row.id);
        }
      }
      return restored;
    });
  }

  /// Borra [itemId] de la base, para siempre: la fila de `item` y, por las
  /// cascadas del esquema, todo lo que cuelga de ella —su fuente o nota, sus
  /// formas, subrayados, chunks, vínculos, tarjetas y versiones por campo—.
  ///
  /// SOLO si ya está en la papelera: es lo único que borra un elemento de
  /// verdad, y lo hace únicamente cuando el usuario lo pide sobre algo que ya
  /// había borrado. Devuelve `false` —y no toca nada— si el elemento no existe
  /// o sigue vivo.
  ///
  /// El archivo original en el disco NO se toca: el disco no tiene cascadas, y
  /// decidir si otro elemento todavía lo usa es cosa de quien llama.
  Future<bool> purge(String itemId) async {
    final removed = await (_db.delete(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId) & e.deletedAt.isNotNull())).go();
    return removed > 0;
  }

  // ---------------------------------------------------------------------

  /// Cuántos ids entran en una sola consulta: por debajo del tope de parámetros
  /// de SQLite.
  static const _idsPerQuery = 400;

  Future<KnowledgeEntryRow?> _entry(String itemId) => (_db.select(
    _db.knowledgeEntries,
  )..where((e) => e.id.equals(itemId))).getSingleOrNull();

  /// Escribe [change] sobre [row] y sube su `rev` con el `deviceId` de acá.
  Future<void> _writeEntry(
    KnowledgeEntryRow row,
    KnowledgeEntriesCompanion change,
  ) => (_db.update(_db.knowledgeEntries)..where((e) => e.id.equals(row.id)))
      .write(
        change.copyWith(rev: Value(row.rev + 1), deviceId: Value(_deviceId)),
      );

  /// Sube el `rev` de [itemId] cuando lo que cambió no está en `item` sino en
  /// `note` o en una forma.
  Future<void> _bumpEntry(String itemId) async {
    final row = await _entry(itemId);
    if (row == null) return;
    await _writeEntry(row, const KnowledgeEntriesCompanion());
  }

  /// Los campos de `source` que cambian con [item]. Sin fila previa cambia cada
  /// metadato que tiene un valor.
  List<String> _changedSourceFields(
    KnowledgeItem item,
    KnowledgeSourceRow? existing,
  ) {
    if (itemKindFor(item.source.kind) == ItemKind.note) return const [];
    final source = item.source;
    return [
      if (existing?.originUrl != source.url) EntryField.originUrl,
      if (existing?.authorName != source.authorName) EntryField.authorName,
      if (existing?.authorUrl != source.authorUrl) EntryField.authorUrl,
      if (existing?.publishedAt != source.publishedAt) EntryField.publishedAt,
      if (existing?.originalBlobPath != source.originalFilePath)
        EntryField.originalBlobPath,
    ];
  }

  /// La fila de `note` —con sus valores de partida— o la de `source`.
  Future<void> _writeTypedRow(
    KnowledgeItem item,
    ItemKind kind,
    KnowledgeSourceRow? existingSource,
  ) async {
    if (kind == ItemKind.note) {
      await _db
          .into(_db.knowledgeNotes)
          .insert(
            KnowledgeNotesCompanion.insert(
              itemId: item.id,
              noteKind: NoteKind.living,
              maturity: NoteMaturity.seed,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      return;
    }

    await _db
        .into(_db.knowledgeSources)
        .insertOnConflictUpdate(
          KnowledgeSourcesCompanion.insert(
            itemId: item.id,
            sourceType: item.source.kind,
            originUrl: Value(item.source.url),
            authorName: Value(item.source.authorName),
            authorUrl: Value(item.source.authorUrl),
            publishedAt: Value(item.source.publishedAt),
            capturedAt: item.source.capturedAt,
            originalBlobPath: Value(item.source.originalFilePath),
            contentHash: existingSource?.contentHash ?? '',
            processingStatus: sourceProcessingStatusFor(item.processingState),
          ),
        );
  }

  /// Registra que [field] de [itemId] cambió ahora, en este dispositivo.
  Future<void> _touch(String itemId, String field, DateTime now) async {
    final previous =
        await (_db.select(_db.fieldVersions)..where(
              (f) => f.itemId.equals(itemId) & f.fieldName.equals(field),
            ))
            .getSingleOrNull();

    // El linaje: qué versión ajena parte esta edición.
    final DateTime? baseAt;
    final String? baseDevice;
    if (previous == null) {
      baseAt = null;
      baseDevice = null;
    } else if (previous.deviceId == _deviceId) {
      baseAt = previous.baseUpdatedAt;
      baseDevice = previous.baseDeviceId;
    } else {
      baseAt = previous.updatedAt;
      baseDevice = previous.deviceId;
    }

    await _db
        .into(_db.fieldVersions)
        .insertOnConflictUpdate(
          FieldVersionsCompanion.insert(
            itemId: itemId,
            fieldName: field,
            updatedAt: now,
            deviceId: _deviceId,
            baseUpdatedAt: Value(baseAt),
            baseDeviceId: Value(baseDevice),
          ),
        );
  }
}
