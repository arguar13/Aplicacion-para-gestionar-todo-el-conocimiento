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
/// Dejan el elemento como lo deja `save()`: la fila de `item` y, según sea, su
/// `source` o su `note`. Que estas escrituras vivan acá y no repartidas por los
/// tests es lo que hace barato cambiar el modelo: se cambia este archivo, no
/// cada prueba.

/// Inserta un elemento. Una nota (`SourceKind.manualNote`) no tiene fila en
/// `source`, como en la app.
Future<void> insertItemRows(
  AppDatabase db, {
  required String id,
  required String title,
  String? subtitle,
  DateTime? createdAt,
  SourceKind kind = SourceKind.webPage,
  ProcessingState processingState = ProcessingState.ready,
}) async {
  final at = createdAt ?? DateTime(2026, 9, 19, 10);

  final itemKind = itemKindFor(kind);
  await db
      .into(db.knowledgeEntries)
      .insert(
        KnowledgeEntriesCompanion.insert(
          id: id,
          title: title,
          subtitle: Value(subtitle),
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

/// Cambia el título de un elemento.
Future<void> retitleItemRows(AppDatabase db, String id, String title) async {
  await (db.update(db.knowledgeEntries)..where((e) => e.id.equals(id))).write(
    KnowledgeEntriesCompanion(title: Value(title)),
  );
}

/// Borra un elemento. Sus dependientes (enlaces, chunks, formas, la fuente o la
/// nota) se van por las claves foráneas, como con `delete()`.
Future<void> deleteItemRows(AppDatabase db, String id) async {
  await (db.delete(db.knowledgeEntries)..where((e) => e.id.equals(id))).go();
}

/// Manda un elemento a la papelera —le pone `deleted_at`— sin pasar por el
/// repositorio: para las pruebas que solo necesitan que ya esté ahí y ver qué
/// hace con eso lo que se lee.
Future<void> trashItemRows(AppDatabase db, String id, {DateTime? at}) async {
  await (db.update(db.knowledgeEntries)..where((e) => e.id.equals(id))).write(
    KnowledgeEntriesCompanion(deletedAt: Value(at ?? DateTime(2026, 9, 20))),
  );
}

/// Lo saca de la papelera: el elemento vuelve tal cual estaba.
Future<void> restoreItemRows(AppDatabase db, String id) async {
  await (db.update(db.knowledgeEntries)..where((e) => e.id.equals(id))).write(
    const KnowledgeEntriesCompanion(deletedAt: Value(null)),
  );
}
