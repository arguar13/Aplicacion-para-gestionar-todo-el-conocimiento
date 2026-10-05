import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/chat_source_builder.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';
import 'package:sinapsis/features/notes/domain/repositories/derived_note_repository.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_parts.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/relations/domain/services/item_vector_index.dart';

/// A qué generar un derivado (F16, 12b): de todo lo que resuelve un
/// cuaderno, o de un único elemento. Nunca los dos ni ninguno —lo exige el
/// `assert`, no un tipo sellado, para no sumar una clase nueva por una
/// disyunción de dos campos—.
class GenerateDerivedNoteParams {
  GenerateDerivedNoteParams({
    required this.type,
    required this.title,
    required this.model,
    this.notebookId,
    this.itemId,
    this.onProgress,
  }) : assert(
         (notebookId == null) != (itemId == null),
         'un derivado sale de un cuaderno o de un elemento, nunca los dos ni '
         'ninguno',
       );

  final DerivedNoteType type;

  /// El título de la nota nueva: ya traducido por quien pide el derivado
  /// —una pantalla, con su `l10n`—, no acá: un caso de uso de `domain` no
  /// depende de las traducciones.
  final String title;

  /// Qué modelo genera, tal como lo identifica `ChatModelOption` (F16,
  /// D3): viene de afuera, no de acá, porque hay más de uno posible y solo
  /// quien maneja la selección del modelo sabe cuál está activo ahora.
  final String model;

  final String? notebookId;
  final String? itemId;

  /// Cuántas partes leyó el modelo de cuántas (F30), antes de cada una y al
  /// final: un cuaderno grande se lee en varios pedidos, y esperar sin saber
  /// cuánto falta es peor que esperar.
  final void Function(int read, int total)? onProgress;
}

/// Genera un derivado —guía de estudio, preguntas abiertas, esquema o
/// cronología— desde un cuaderno o un elemento, y lo guarda como una nota
/// nueva, marcada, con sus afirmaciones ancladas a sus fuentes (F16, 12b).
///
/// Junta lo de los commits anteriores: [DerivedNoteGenerator] (D5/D6, 11)
/// propone y ancla; acá se resuelve DE DÓNDE salen las fuentes, se arma el
/// contenido de la nota con esas afirmaciones, y se guarda todo junto —la
/// nota y cada relación `extractedFrom`— en una sola transacción. Si nada
/// del modelo se pudo anclar, no se crea nada: "mejor ninguno que uno
/// equivocado" (F11) también vale acá, un paso más arriba.
///
/// **Por partes** (F30). Hasta acá se le mandaban al modelo todas las fuentes
/// de un cuaderno de una vez: con más de unas quince, el pedido no entraba en
/// su ventana. Ahora:
///
/// - Solo van las fuentes que se pueden citar —con texto propio y su
///   posición: una nota no se fragmenta, y lo que el modelo dijera de ella se
///   descartaría igual al anclar—.
/// - De un cuaderno grande, las más representativas primero
///   ([ItemVectorIndex.representativeOrder]): lo más central y lo más
///   distinto, no las primeras de la lista.
/// - Se reparten en hasta [kDerivedNoteMaxParts] pedidos que entran en la
///   ventana ([packDerivedSources]), y lo que dio cada uno se junta en una
///   sola nota ([mergeDerivedSections]).
class GenerateDerivedNoteUseCase
    implements UseCase<KnowledgeItem, GenerateDerivedNoteParams> {
  const GenerateDerivedNoteUseCase({
    required LibraryRepository library,
    required NotebookRepository notebooks,
    required OrganizeRepository organize,
    required DerivedNoteRepository derivedNotes,
    required DerivedNoteGenerator generator,
    required ItemVectorIndex vectors,
    required IdGenerator ids,
    required Clock clock,
  }) : _library = library,
       _notebooks = notebooks,
       _organize = organize,
       _derivedNotes = derivedNotes,
       _generator = generator,
       _vectors = vectors,
       _ids = ids,
       _clock = clock;

  final LibraryRepository _library;
  final NotebookRepository _notebooks;
  final OrganizeRepository _organize;
  final DerivedNoteRepository _derivedNotes;
  final DerivedNoteGenerator _generator;
  final ItemVectorIndex _vectors;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Either<Failure, KnowledgeItem>> call(
    GenerateDerivedNoteParams params,
  ) async {
    final sources = await _resolveSources(params);
    if (sources.isEmpty) {
      return left(
        const Failure.validation(
          message:
              'No hay fuentes que se puedan citar para generar un derivado.',
        ),
      );
    }

    final parts = packDerivedSources(sources);
    final sections = <List<DerivedSection>>[];
    try {
      for (var i = 0; i < parts.length; i++) {
        params.onProgress?.call(i, parts.length);
        final draft = await _generator.generateDerivedNote(
          type: params.type,
          sources: parts[i],
        );
        sections.add(draft.sections);
      }
      // El motor de inferencia es de terceros (flutter_gemma); puede fallar
      // de formas que no tienen un tipo propio en Dart —memoria
      // insuficiente, un error nativo de la biblioteca de inferencia—,
      // mismo criterio que `AskVaultQuestionUseCase`.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.unexpected(message: e.toString()));
    }
    params.onProgress?.call(parts.length, parts.length);
    final draft = DerivedNoteDraft(
      type: params.type,
      sections: mergeDerivedSections(sections),
    );
    if (draft.isEmpty) {
      return left(
        const Failure.validation(
          message:
              'Ninguna afirmación se pudo anclar a un fragmento real de '
              'las fuentes.',
        ),
      );
    }

    final now = _clock();
    final itemId = _ids.next();
    final item = KnowledgeItem(
      id: itemId,
      title: params.title,
      source: Source(
        id: _ids.next(),
        kind: SourceKind.manualNote,
        capturedAt: now,
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [
        Rendition.text(
          id: _ids.next(),
          itemId: itemId,
          kind: RenditionKind.blocks,
          content: encodeContentBlocks(_blocksOf(draft)),
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );

    return _library.runInTransaction<Either<Failure, KnowledgeItem>>(() async {
      final saveResult = await _library.save(item);
      final saved = saveResult.getRight().toNullable();
      if (saved == null) return saveResult;

      await _derivedNotes.markGenerated(saved.id, model: params.model, at: now);

      // Una relación `extractedFrom` por afirmación anclada: el generador
      // (D6) ya garantiza como mucho una por fuente, así que ninguna de
      // estas puede chocar con `UNIQUE(from_item_id, to_item_id, kind)`.
      for (final section in draft.sections) {
        for (final claim in section.claims) {
          await _organize.createRelation(
            fromItemId: saved.id,
            toItemId: claim.sourceItemId,
            kind: RelationKind.extractedFrom,
            sourceCharStart: claim.sourceCharStart,
            sourceCharEnd: claim.sourceCharEnd,
          );
        }
      }

      return right(saved);
    });
  }

  /// Las fuentes que se pueden citar de un cuaderno —las más representativas
  /// primero, como mucho [kDerivedNoteMaxSources]— o de un único elemento.
  ///
  /// Los ids salen sin traer los elementos (`matchingIds`), y se trae de a
  /// uno solo lo que se va a leer: un cuaderno de cien libros no se carga
  /// entero en memoria para usar el principio de dieciocho.
  Future<List<ChatSource>> _resolveSources(
    GenerateDerivedNoteParams params,
  ) async {
    final notebookId = params.notebookId;
    if (notebookId == null) {
      final source = await _citableSource(params.itemId!);
      return source == null ? const [] : [source];
    }

    final query = await _notebooks.resolveQuery(notebookId);
    final ids = (await _library.matchingIds(query)).getOrElse((_) => const []);
    final ordered = ids.length <= kDerivedNoteMaxSources
        ? ids
        : await _vectors.representativeOrder(ids, take: kDerivedNoteMaxSources);
    final sources = <ChatSource>[];
    for (final id in ordered) {
      if (sources.length == kDerivedNoteMaxSources) break;
      final source = await _citableSource(id);
      if (source != null) sources.add(source);
    }
    return sources;
  }

  /// La fuente de [itemId], si se puede citar: con texto y con su posición en
  /// él —una nota no tiene, y lo que el modelo dijera de ella no se anclaría—.
  Future<ChatSource?> _citableSource(String itemId) async {
    final item = (await _library.findById(itemId)).getOrElse((_) => null);
    if (item == null) return null;
    final source = buildChatSource(item);
    if (source.sourceCharStart == null || source.excerpt.trim().isEmpty) {
      return null;
    }
    return source;
  }

  List<ContentBlock> _blocksOf(DerivedNoteDraft draft) {
    final blocks = <ContentBlock>[];
    for (final section in draft.sections) {
      final heading = section.heading;
      if (heading != null) {
        blocks.add(ContentBlock.heading(text: heading, level: 2));
      }
      for (final claim in section.claims) {
        blocks.add(ContentBlock.bulletItem(text: claim.text));
      }
    }
    return blocks;
  }
}
