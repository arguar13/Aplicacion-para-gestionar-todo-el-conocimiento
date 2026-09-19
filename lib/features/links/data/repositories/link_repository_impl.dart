import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/inline_link_sync.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/inline_link_parser.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/links/domain/entities/broken_link.dart';
import 'package:sinapsis/features/links/domain/repositories/link_repository.dart';

class LinkRepositoryImpl implements LinkRepository {
  const LinkRepositoryImpl({
    required AppDatabase database,
    required LibraryRepository library,
    required InboxRepository inbox,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _library = library,
       _inbox = inbox,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final LibraryRepository _library;
  final InboxRepository _inbox;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Either<Failure, Set<String>>> findMissingTitles(
    Set<String> normalizedTitles, {
    String? excludingItemId,
  }) async {
    try {
      final byTitle = await itemsByLinkTitle(_db);
      final missing = <String>{};
      for (final title in normalizedTitles) {
        final resolution = resolveLinkTarget(
          byTitle,
          title,
          fromItemId: excludingItemId ?? '',
        );
        if (resolution.id == null && !resolution.isSelfLink) missing.add(title);
      }
      return right(missing);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'LinkRepositoryImpl.findMissingTitles'),
      );
    }
  }

  @override
  Future<Either<Failure, KnowledgeItem>> createNoteForLink({
    required String title,
    NoteKind kind = NoteKind.living,
  }) async {
    final outcome = await _createOrFind(title, kind);
    return outcome.map((found) => found.item);
  }

  @override
  Future<Either<Failure, int>> createNotesForLinks(
    List<String> titles, {
    NoteKind kind = NoteKind.living,
  }) async {
    try {
      var created = 0;
      await _db.transaction(() async {
        for (final title in titles) {
          final outcome = await _createOrFind(title, kind);
          final failure = outcome.getLeft().toNullable();
          // Lanzar es lo que deshace la transacción entera: las notas ya
          // creadas antes de la que falló no pueden quedar a medias.
          if (failure != null) throw _BatchAborted(failure);
          if (outcome.getRight().toNullable()!.created) created++;
        }
      });
      return right(created);
    } on _BatchAborted catch (aborted) {
      return left(aborted.failure);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'LinkRepositoryImpl.createNotesForLinks'),
      );
    }
  }

  @override
  Stream<List<BrokenLink>> watchBrokenLinks() {
    return watchQuery(
      db: _db,
      tables: [_db.inlineLinks, _db.items],
      read: _readBrokenLinks,
      telemetry: _telemetry,
      hint: 'LinkRepositoryImpl.watchBrokenLinks',
    );
  }

  Future<List<BrokenLink>> _readBrokenLinks() async {
    final links = _db.inlineLinks;
    final items = _db.items;
    final rows =
        await (_db.select(links).join([
                innerJoin(items, items.id.equalsExp(links.fromItemId)),
              ])
              ..where(links.toItemId.isNull())
              ..orderBy([
                OrderingTerm(expression: links.createdAt),
                OrderingTerm(expression: links.id),
              ]))
            .get();

    final titles = <String, String>{};
    final sources = <String, List<BrokenLinkSource>>{};
    for (final row in rows) {
      final link = row.readTable(links);
      titles.putIfAbsent(link.normalizedTitle, () => link.targetTitle);
      (sources[link.normalizedTitle] ??= []).add(
        BrokenLinkSource(
          itemId: link.fromItemId,
          title: row.readTable(items).title,
        ),
      );
    }

    // Se ordena sobre el texto sin acentos: "Época" va con las E, no después
    // de la Z.
    final broken = [
      for (final entry in sources.entries)
        BrokenLink(
          title: titles[entry.key]!,
          normalizedTitle: entry.key,
          sources: entry.value
            ..sort(
              (a, b) => normalizeVocabularyLabel(
                a.title,
              ).compareTo(normalizeVocabularyLabel(b.title)),
            ),
        ),
    ]..sort(_byMentionsThenTitle);
    return broken;
  }

  static int _byMentionsThenTitle(BrokenLink a, BrokenLink b) {
    final byCount = b.sources.length.compareTo(a.sources.length);
    if (byCount != 0) return byCount;
    return normalizeVocabularyLabel(
      a.title,
    ).compareTo(normalizeVocabularyLabel(b.title));
  }

  /// Crea la nota de [title], o devuelve la que ya existe con ese título.
  Future<Either<Failure, ({KnowledgeItem item, bool created})>> _createOrFind(
    String title,
    NoteKind kind,
  ) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(
          message: 'El título de la nota no puede estar vacío.',
        ),
      );
    }

    try {
      final byTitle = await itemsByLinkTitle(_db);
      final existing = byTitle[normalizeLinkTitle(trimmed)]?.firstOrNull;
      if (existing != null) {
        final found = await _findExisting(existing.id);
        return found.map((item) => (item: item, created: false));
      }

      final now = _clock();
      final itemId = _ids.next();
      final note = KnowledgeItem(
        id: itemId,
        title: trimmed,
        source: Source(
          id: _ids.next(),
          kind: SourceKind.manualNote,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        // Lo mismo que escribe el editor para una nota sin tocar: un párrafo
        // vacío, así que abrirla después en el editor no tiene nada distinto.
        renditions: [
          Rendition.text(
            id: _ids.next(),
            itemId: itemId,
            kind: RenditionKind.blocks,
            content: encodeContentBlocks(const [
              ContentBlock.paragraph(text: ''),
            ]),
            isPrimary: true,
            createdAt: now,
          ),
        ],
      );

      final saved = await _library.save(note);
      final saveFailure = saved.getLeft().toNullable();
      if (saveFailure != null) return left(saveFailure);

      // Una nota nace `living` en el espejo: solo hay que escribir el
      // subtipo cuando el usuario eligió otro.
      if (kind != NoteKind.living) {
        final kindResult = await _inbox.setNoteKind(itemId: itemId, kind: kind);
        final kindFailure = kindResult.getLeft().toNullable();
        if (kindFailure != null) return left(kindFailure);
      }

      return right((item: note, created: true));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'LinkRepositoryImpl.createNoteForLink'),
      );
    }
  }

  Future<Either<Failure, KnowledgeItem>> _findExisting(String id) async {
    final found = await _library.findById(id);
    final failure = found.getLeft().toNullable();
    if (failure != null) return left(failure);

    final item = found.getRight().toNullable();
    if (item == null) {
      return left(
        const Failure.unexpected(
          message: 'La nota ya no existe; puede que se haya borrado.',
        ),
      );
    }
    return right(item);
  }

  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}

/// Una nota del lote falló: deshace la transacción del lote entero.
class _BatchAborted implements Exception {
  const _BatchAborted(this.failure);

  final Failure failure;
}
