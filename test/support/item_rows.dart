import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// Las filas de un elemento, escritas directo en las tablas y NO por
/// `LibraryRepositoryImpl.save`, para las pruebas que necesitan controlar el
/// momento exacto de cada escritura (un enlace roto que debe seguir roto hasta
/// que se pida resolverlo, un elemento renombrado a mano).
///
/// Dejan el elemento como lo deja `save()`: en las tablas viejas
/// (`items`/`sources`) y en el modelo nuevo (`item`, y `source` o `note`). Que
/// las dos escrituras vivan acá y no repartidas por los tests es lo que hará
/// barato retirar las viejas: se cambia este archivo, no cada prueba.

/// Inserta un elemento. Una nota (`SourceKind.manualNote`) no tiene fila en
/// `source`, como en la app.
Future<void> insertItemRows(
  AppDatabase db, {
  required String id,
  required String title,
  DateTime? createdAt,
  SourceKind kind = SourceKind.webPage,
  ProcessingState processingState = ProcessingState.ready,
}) async {
  final at = createdAt ?? DateTime(2026, 9, 19, 10);

  await db
      .into(db.sources)
      .insert(
        SourcesCompanion.insert(id: 'src-$id', kind: kind, capturedAt: at),
      );
  await db
      .into(db.items)
      .insert(
        ItemsCompanion.insert(
          id: id,
          title: title,
          sourceId: 'src-$id',
          processingState: processingState,
          createdAt: at,
          updatedAt: at,
        ),
      );

  final itemKind = itemKindFor(kind);
  await db
      .into(db.knowledgeEntries)
      .insert(
        KnowledgeEntriesCompanion.insert(
          id: id,
          title: title,
          kind: itemKind,
          state: nextMirrorState(
            current: null,
            processingState: processingState,
          ),
          createdAt: at,
          updatedAt: at,
          deviceId: kMirrorDeviceIdPlaceholder,
        ),
      );
  if (itemKind == ItemKind.note) {
    await db
        .into(db.knowledgeNotes)
        .insert(
          KnowledgeNotesCompanion.insert(
            itemId: id,
            noteKind: NoteKind.living,
            maturity: NoteMaturity.seed,
          ),
        );
    return;
  }
  await db
      .into(db.knowledgeSources)
      .insert(
        KnowledgeSourcesCompanion.insert(
          itemId: id,
          sourceType: kind,
          capturedAt: at,
          contentHash: '',
          processingStatus: sourceProcessingStatusFor(processingState),
        ),
      );
}

/// Cambia el título de un elemento, en los dos modelos.
Future<void> retitleItemRows(AppDatabase db, String id, String title) async {
  await (db.update(
    db.items,
  )..where((i) => i.id.equals(id))).write(ItemsCompanion(title: Value(title)));
  await (db.update(db.knowledgeEntries)..where((e) => e.id.equals(id))).write(
    KnowledgeEntriesCompanion(title: Value(title)),
  );
}

/// Borra un elemento, en los dos modelos. Sus dependientes (enlaces, chunks,
/// formas) se van por las claves foráneas, como con `delete()`.
Future<void> deleteItemRows(AppDatabase db, String id) async {
  await (db.delete(db.items)..where((i) => i.id.equals(id))).go();
  await (db.delete(db.knowledgeEntries)..where((e) => e.id.equals(id))).go();
}
