import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/inline_link_sync.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/inline_link_parser.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
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
      if (existing != null) return await _findExisting(existing.id);

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

      return saved;
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
