import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/services/inline_link_parser.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';

const _migrationName = 'f9_inline_links';
const _brokenLinkStage = 'broken_inline_link';
const _unreadableStage = 'unreadable_blocks';

/// Cuántas notas se leen por vez: los bloques de una bóveda grande no se
/// cargan enteros en memoria de una sola consulta.
const _pageSize = 200;

/// Un enlace que el backfill va a registrar.
class InlineLinkPlanRow {
  const InlineLinkPlanRow({
    required this.fromItemId,
    required this.title,
    required this.normalizedTitle,
    required this.toItemId,
  });

  final String fromItemId;
  final String title;
  final String normalizedTitle;

  /// `null` si ningún elemento se llama así: el enlace está roto.
  final String? toItemId;
}

/// Qué hará el backfill, calculado SIN escribir nada: el dry-run.
class InlineLinkBackfillPlan {
  const InlineLinkBackfillPlan({
    required this.notesScanned,
    required this.links,
    required this.alreadyRegistered,
    required this.selfLinks,
    required this.unreadable,
  });

  /// Notas con bloques que se revisaron.
  final int notesScanned;

  /// Los enlaces nuevos que se registran.
  final List<InlineLinkPlanRow> links;

  /// Enlaces que ya estaban registrados: no se repiten.
  final int alreadyRegistered;

  /// Notas que se enlazan a sí mismas por título: no son un enlace roto ni
  /// uno resuelto, y no se registran.
  final int selfLinks;

  /// Notas cuyos bloques no se pudieron leer: ids. No se pierde nada —los
  /// enlaces se registran de nuevo al guardar la nota—, pero se informa.
  final List<String> unreadable;

  int get resolved => links.where((l) => l.toItemId != null).length;
  int get broken => links.length - resolved;

  bool get hasWork => links.isNotEmpty;

  String summary() =>
      'Enlaces en línea: $notesScanned notas revisadas; ${links.length} '
      'enlaces por registrar ($resolved con destino, $broken rotos); '
      '$alreadyRegistered ya estaban registrados; $selfLinks a sí mismas; '
      '${unreadable.length} notas con bloques ilegibles.';
}

/// Calcula qué registraría [applyInlineLinkBackfill], sin escribir NADA.
///
/// Recorre los bloques de toda nota y resuelve cada `[[Título]]` con la misma
/// regla que usa el editor al guardar: recorte y minúsculas, contra el título
/// de cualquier otro elemento. Si varios elementos se llaman igual gana el
/// más antiguo, con el id de desempate: un destino estable, no el que la base
/// devuelva primero.
Future<InlineLinkBackfillPlan> planInlineLinkBackfill(AppDatabase db) async {
  // Los títulos de todos los elementos, por forma normalizada.
  final items = await (db.selectOnly(
    db.items,
  )..addColumns([db.items.id, db.items.title, db.items.createdAt])).get();
  final byTitle = <String, List<({String id, DateTime createdAt})>>{};
  for (final row in items) {
    final id = row.read(db.items.id)!;
    final normalized = normalizeLinkTitle(row.read(db.items.title)!);
    byTitle.putIfAbsent(normalized, () => []).add((
      id: id,
      createdAt: row.read(db.items.createdAt)!,
    ));
  }
  for (final candidates in byTitle.values) {
    candidates.sort((a, b) {
      final byAge = a.createdAt.compareTo(b.createdAt);
      return byAge != 0 ? byAge : a.id.compareTo(b.id);
    });
  }

  final registered = {
    for (final row in await db.select(db.inlineLinks).get())
      (row.fromItemId, row.normalizedTitle),
  };

  final links = <InlineLinkPlanRow>[];
  final unreadable = <String>[];
  var notesScanned = 0;
  var alreadyRegistered = 0;
  var selfLinks = 0;

  var offset = 0;
  while (true) {
    final page =
        await (db.select(db.renditions)
              ..where((r) => r.kind.equalsValue(RenditionKind.blocks))
              ..orderBy([(r) => OrderingTerm(expression: r.id)])
              ..limit(_pageSize, offset: offset))
            .get();
    if (page.isEmpty) break;
    offset += page.length;

    for (final rendition in page) {
      final content = rendition.content;
      if (content == null) continue;
      notesScanned++;

      final blocks = tryDecodeContentBlocks(content);
      if (blocks == null) {
        unreadable.add(rendition.itemId);
        continue;
      }
      final mentions = extractInlineLinksFromBlocks(blocks);

      for (final mention in mentions) {
        if (registered.contains((rendition.itemId, mention.normalizedTitle))) {
          alreadyRegistered++;
          continue;
        }
        // Los candidatos van del más antiguo al más nuevo: el primero que no
        // sea la propia nota es el destino.
        final candidates = byTitle[mention.normalizedTitle];
        final target = candidates
            ?.where((c) => c.id != rendition.itemId)
            .firstOrNull;
        if (candidates != null && target == null) {
          // El único elemento con ese título es la propia nota.
          selfLinks++;
          continue;
        }
        links.add(
          InlineLinkPlanRow(
            fromItemId: rendition.itemId,
            title: mention.title,
            normalizedTitle: mention.normalizedTitle,
            toItemId: target?.id,
          ),
        );
      }
    }
  }

  return InlineLinkBackfillPlan(
    notesScanned: notesScanned,
    links: links,
    alreadyRegistered: alreadyRegistered,
    selfLinks: selfLinks,
    unreadable: unreadable,
  );
}

/// Aplica [plan]: registra cada enlace en `inline_link`.
///
/// No abre transacción: en la migración ya hay una. `insertOrIgnore`, así que
/// correrla dos veces no duplica nada. No crea `Relations`: las que
/// correspondían se crearon al guardar cada nota, y esto solo registra lo que
/// el texto dice.
Future<void> applyInlineLinkBackfill(
  AppDatabase db,
  InlineLinkBackfillPlan plan, {
  required IdGenerator ids,
  Clock clock = DateTime.now,
}) async {
  final now = clock();
  for (final link in plan.links) {
    await db
        .into(db.inlineLinks)
        .insert(
          InlineLinksCompanion.insert(
            id: ids.next(),
            fromItemId: link.fromItemId,
            targetTitle: link.title,
            normalizedTitle: link.normalizedTitle,
            toItemId: Value(link.toItemId),
            createdAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}

/// El paso completo de la migración v15: calcula el plan, deja el informe
/// —los enlaces rotos y las notas ilegibles, en `MigrationIssues` y en el
/// registro— y recién entonces lo aplica.
///
/// Idempotente: una segunda corrida no encuentra nada por registrar, y una
/// nota ilegible que ya se informó no se informa otra vez.
Future<InlineLinkBackfillPlan> backfillInlineLinks(
  AppDatabase db, {
  required IdGenerator ids,
  required AppLogger logger,
  Clock clock = DateTime.now,
}) async {
  final plan = await planInlineLinkBackfill(db);

  // Los enlaces rotos no se repiten solos —el plan solo trae los que aún no
  // están registrados—, pero una nota ilegible sigue ilegible en cada corrida.
  final alreadyReported = {
    for (final issue in await (db.select(
      db.migrationIssues,
    )..where((i) => i.migration.equals(_migrationName))).get())
      if (issue.stage == _unreadableStage) issue.itemId,
  };
  final newlyUnreadable = [
    for (final itemId in plan.unreadable)
      if (!alreadyReported.contains(itemId)) itemId,
  ];
  if (!plan.hasWork && newlyUnreadable.isEmpty) return plan;

  logger.info(plan.summary());
  final now = clock();

  Future<void> report(String itemId, String stage, String message) => db
      .into(db.migrationIssues)
      .insert(
        MigrationIssuesCompanion.insert(
          id: ids.next(),
          migration: _migrationName,
          itemId: itemId,
          stage: stage,
          message: message,
          createdAt: now,
        ),
      );

  for (final link in plan.links) {
    if (link.toItemId != null) continue;
    await report(
      link.fromItemId,
      _brokenLinkStage,
      'El enlace [[${link.title}]] no tiene ningún elemento con ese título.',
    );
  }
  for (final itemId in newlyUnreadable) {
    await report(
      itemId,
      _unreadableStage,
      'Los bloques de la nota no se pudieron leer: sus enlaces se '
      'registran al volver a guardarla.',
    );
  }

  await applyInlineLinkBackfill(db, plan, ids: ids, clock: clock);
  return plan;
}
