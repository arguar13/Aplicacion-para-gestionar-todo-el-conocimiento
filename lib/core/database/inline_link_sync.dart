import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/services/inline_link_parser.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Un elemento que puede ser el destino de un `[[Título]]`.
typedef LinkCandidate = ({String id, DateTime createdAt});

/// Los elementos de la bóveda agrupados por título normalizado, cada grupo del
/// más antiguo al más nuevo y, a igual antigüedad, por id.
///
/// La comparación se hace en Dart y no en SQL: el `lower()` de SQLite solo
/// pliega ASCII, y "Época" tiene que encontrar a "época". Por eso se traen
/// solo las tres columnas que hacen falta de todos los elementos —ni sus
/// formas ni sus textos— y se agrupan acá.
Future<Map<String, List<LinkCandidate>>> itemsByLinkTitle(
  AppDatabase db,
) async {
  final entries = db.knowledgeEntries;
  // Lo que está en la papelera no recibe enlaces: un `[[Título]]` que solo
  // coincide con un elemento borrado queda roto, y se resuelve si lo restauran.
  final rows =
      await (db.selectOnly(entries)
            ..addColumns([entries.id, entries.title, entries.createdAt])
            ..where(entries.isActive))
          .get();

  final byTitle = <String, List<LinkCandidate>>{};
  for (final row in rows) {
    byTitle
        .putIfAbsent(normalizeLinkTitle(row.read(entries.title)!), () => [])
        .add((
          id: row.read(entries.id)!,
          createdAt: row.read(entries.createdAt)!,
        ));
  }
  for (final candidates in byTitle.values) {
    candidates.sort((a, b) {
      final byAge = a.createdAt.compareTo(b.createdAt);
      return byAge != 0 ? byAge : a.id.compareTo(b.id);
    });
  }
  return byTitle;
}

/// A qué elemento apunta un `[[Título]]` escrito en [fromItemId].
///
/// Es el más antiguo con ese título que no sea la propia nota: un destino
/// estable, no el que la base devuelva primero. `id` es `null` si el enlace
/// está roto; `isSelfLink` distingue el caso en que el único elemento con ese
/// título es la propia nota, que no es un enlace roto ni uno resuelto y no se
/// registra.
({String? id, bool isSelfLink}) resolveLinkTarget(
  Map<String, List<LinkCandidate>> byTitle,
  String normalizedTitle, {
  required String fromItemId,
}) {
  final candidates = byTitle[normalizedTitle];
  final target = candidates?.where((c) => c.id != fromItemId).firstOrNull;
  return (id: target?.id, isSelfLink: candidates != null && target == null);
}

/// Deja los enlaces registrados de [itemId] iguales a los `[[ ]]` de [blocks].
///
/// Corre dentro de la transacción de guardado de la nota: no abre una propia.
///
///  * Un enlace que el texto ya no menciona se borra de `inline_link`. La
///    `Relation` que hubiera creado NO se borra: puede haberla confirmado o
///    creado a mano el usuario, y borrar un texto no es decir que dos notas
///    dejaron de estar vinculadas.
///  * Un enlace nuevo, o uno que seguía roto, se resuelve contra los títulos
///    de la bóveda; si tiene destino se crea la `Relation` `relatedTo` real.
///  * Uno que ya tenía destino no se vuelve a resolver ni a vincular: si el
///    usuario borró esa relación a propósito, guardar la nota no la resucita.
///    Si el destino se borró, la clave foránea lo dejó roto y vuelve a
///    resolverse acá.
Future<void> syncInlineLinks(
  AppDatabase db, {
  required String itemId,
  required List<ContentBlock> blocks,
  required IdGenerator ids,
  required Clock clock,
}) async {
  final mentions = extractInlineLinksFromBlocks(blocks);
  final mentioned = {for (final m in mentions) m.normalizedTitle};

  final registered = {
    for (final row in await (db.select(
      db.inlineLinks,
    )..where((l) => l.fromItemId.equals(itemId))).get())
      row.normalizedTitle: row,
  };

  final gone = [
    for (final row in registered.values)
      if (!mentioned.contains(row.normalizedTitle)) row.id,
  ];
  if (gone.isNotEmpty) {
    await (db.delete(db.inlineLinks)..where((l) => l.id.isIn(gone))).go();
  }

  final needsResolving = mentions.any(
    (m) => registered[m.normalizedTitle]?.toItemId == null,
  );
  final byTitle = needsResolving
      ? await itemsByLinkTitle(db)
      : const <String, List<LinkCandidate>>{};
  final now = clock();

  for (final mention in mentions) {
    final row = registered[mention.normalizedTitle];
    var toItemId = row?.toItemId;

    if (toItemId == null) {
      final resolution = resolveLinkTarget(
        byTitle,
        mention.normalizedTitle,
        fromItemId: itemId,
      );
      if (resolution.isSelfLink) {
        // La nota pasó a llamarse como su propio enlace: ya no es un enlace.
        if (row != null) {
          await (db.delete(
            db.inlineLinks,
          )..where((l) => l.id.equals(row.id))).go();
        }
        continue;
      }
      toItemId = resolution.id;
      if (toItemId != null) {
        await _ensureRelatedTo(
          db,
          fromItemId: itemId,
          toItemId: toItemId,
          ids: ids,
          now: now,
        );
      }
    }

    if (row == null) {
      await db
          .into(db.inlineLinks)
          .insert(
            InlineLinksCompanion.insert(
              id: ids.next(),
              fromItemId: itemId,
              targetTitle: mention.title,
              normalizedTitle: mention.normalizedTitle,
              toItemId: Value(toItemId),
              createdAt: now,
            ),
          );
    } else if (row.toItemId != toItemId || row.targetTitle != mention.title) {
      await (db.update(
        db.inlineLinks,
      )..where((l) => l.id.equals(row.id))).write(
        InlineLinksCompanion(
          targetTitle: Value(mention.title),
          toItemId: Value(toItemId),
        ),
      );
    }
  }
}

/// Resuelve los enlaces rotos de otras notas que esperaban el título de
/// [itemId], y crea la `Relation` `relatedTo` de cada uno. Devuelve cuántos
/// resolvió.
///
/// Se llama al guardar cualquier elemento —nuevo o renombrado—: escribir
/// `[[Roma]]` antes de que exista "Roma" es el flujo natural de enlazar
/// primero y crear después, y crear "Roma" tiene que completar esos enlaces.
///
/// Corre dentro de la transacción de guardado. Si el elemento se renombra, los
/// enlaces que ya apuntaban a él con su nombre anterior se dejan como están:
/// la relación existe y renombrar no la deshace.
Future<int> resolveBrokenInlineLinks(
  AppDatabase db, {
  required String itemId,
  required String title,
  required IdGenerator ids,
  required Clock clock,
}) async {
  final normalized = normalizeLinkTitle(title);
  if (normalized.isEmpty) return 0;

  final broken =
      await (db.select(db.inlineLinks)..where(
            (l) =>
                l.toItemId.isNull() &
                l.normalizedTitle.equals(normalized) &
                l.fromItemId.equals(itemId).not(),
          ))
          .get();
  if (broken.isEmpty) return 0;

  await (db.update(db.inlineLinks)
        ..where((l) => l.id.isIn([for (final row in broken) row.id])))
      .write(InlineLinksCompanion(toItemId: Value(itemId)));

  final now = clock();
  for (final row in broken) {
    await _ensureRelatedTo(
      db,
      fromItemId: row.fromItemId,
      toItemId: itemId,
      ids: ids,
      now: now,
    );
  }
  return broken.length;
}

/// Crea `from → to` de tipo `relatedTo` si no existe. El `UNIQUE` de la tabla
/// hace idempotente el `insertOrIgnore`.
Future<void> _ensureRelatedTo(
  AppDatabase db, {
  required String fromItemId,
  required String toItemId,
  required IdGenerator ids,
  required DateTime now,
}) => db
    .into(db.relations)
    .insert(
      RelationsCompanion.insert(
        id: ids.next(),
        fromItemId: fromItemId,
        toItemId: toItemId,
        kind: RelationKind.relatedTo,
        createdAt: now,
      ),
      mode: InsertMode.insertOrIgnore,
    );
