import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
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
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';
import 'package:sinapsis/features/notes/domain/repositories/derived_note_repository.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_parts.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/relations/domain/services/item_vector_index.dart';

/// Cuántas partes de cada sección se miran, como mucho, buscando una que se
/// pueda citar: lo copiado tal cual suele estar al principio, y un libro no
/// se recorre página por página.
const _kCitablePartsLooked = 8;

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

/// Lo que dejó un derivado: la nota, y si quedó adentro del cuaderno del que
/// salió (F30).
@immutable
class DerivedNoteResult {
  const DerivedNoteResult({required this.note, this.inNotebook});

  final KnowledgeItem note;

  /// `false` si salió de un cuaderno: un cuaderno tiene solo documentos
  /// procesados (F41, paso 5), así que la nota queda en la Biblioteca y la
  /// hoja lo dice; `null` si salió de un elemento.
  final bool? inNotebook;
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
/// - Se reparten en hasta [kDerivedNoteMaxParts] pedidos del largo que lee el
///   modelo elegido ([packDerivedSources]; con uno en la nube, casi siempre
///   uno solo), y lo que dio cada uno se junta en una
///   sola nota ([mergeDerivedSections]).
///
/// **De un cuaderno, lee sus documentos procesados** (F41, paso 5): de cada
/// uno, lo primero que copió tal cual de su fuente, con su ancla en el texto
/// principal de la fuente. Las afirmaciones se anclan a la fuente de la
/// Biblioteca, que es donde está el original. La nota **queda en la
/// Biblioteca**: un cuaderno tiene solo procesados, y el resultado lo dice
/// ([DerivedNoteResult.inNotebook]).
class GenerateDerivedNoteUseCase
    implements UseCase<DerivedNoteResult, GenerateDerivedNoteParams> {
  const GenerateDerivedNoteUseCase({
    required LibraryRepository library,
    required NotebookRepository notebooks,
    required ProcessedRepository processed,
    required OrganizeRepository organize,
    required DerivedNoteRepository derivedNotes,
    required DerivedNoteGenerator generator,
    required ItemVectorIndex vectors,
    required IdGenerator ids,
    required Clock clock,
    required ModelTextBudget Function() textBudget,
  }) : _library = library,
       _notebooks = notebooks,
       _processed = processed,
       _organize = organize,
       _derivedNotes = derivedNotes,
       _generator = generator,
       _vectors = vectors,
       _ids = ids,
       _clock = clock,
       _textBudget = textBudget;

  final LibraryRepository _library;
  final NotebookRepository _notebooks;
  final ProcessedRepository _processed;
  final OrganizeRepository _organize;
  final DerivedNoteRepository _derivedNotes;
  final DerivedNoteGenerator _generator;
  final ItemVectorIndex _vectors;
  final IdGenerator _ids;
  final Clock _clock;

  /// Cuánto lee por pedido el modelo elegido (F32), al pedir el derivado.
  final ModelTextBudget Function() _textBudget;

  @override
  Future<Either<Failure, DerivedNoteResult>> call(
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

    final parts = packDerivedSources(
      sources,
      partChars: _textBudget().partChars,
    );
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

    // La de un elemento va a sus temas (F37): es material del mismo asunto, y
    // así queda al lado de lo que resume en vez de suelta.
    final itemId = params.itemId;
    final fromItem = itemId == null
        ? null
        : (await _library.findById(itemId)).getOrElse((_) => null);

    final now = _clock();
    final noteId = _ids.next();
    final item = KnowledgeItem(
      id: noteId,
      title: params.title,
      source: Source(
        id: _ids.next(),
        kind: SourceKind.manualNote,
        capturedAt: now,
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      spaceIds: {...?fromItem?.spaceIds},
      renditions: [
        Rendition.text(
          id: _ids.next(),
          itemId: noteId,
          kind: RenditionKind.blocks,
          content: encodeContentBlocks(_blocksOf(draft)),
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );

    final saved = await _library
        .runInTransaction<Either<Failure, KnowledgeItem>>(() async {
          final saveResult = await _library.save(item);
          final saved = saveResult.getRight().toNullable();
          if (saved == null) return saveResult;

          await _derivedNotes.markGenerated(
            saved.id,
            model: params.model,
            at: now,
          );

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

    final failure = saved.getLeft().toNullable();
    if (failure != null) return left(failure);
    final note = saved.getRight().toNullable()!;
    return right(
      DerivedNoteResult(
        note: note,
        inNotebook: params.notebookId == null ? null : false,
      ),
    );
  }

  /// Las fuentes que se pueden citar de un cuaderno —las más representativas
  /// primero, como mucho [kDerivedNoteMaxSources]— o de un único elemento.
  ///
  /// Los ids salen sin traer los documentos (`memberIds`), y se lee de a uno
  /// solo lo que se va a citar: un cuaderno de cien libros no se carga entero
  /// en memoria para usar el principio de dieciocho.
  Future<List<ChatSource>> _resolveSources(
    GenerateDerivedNoteParams params,
  ) async {
    final notebookId = params.notebookId;
    if (notebookId == null) {
      final source = await _citableSource(params.itemId!);
      return source == null ? const [] : [source];
    }

    final ids = (await _notebooks.memberIds(
      notebookId,
    )).getOrElse((_) => const []);
    // Lo representativo lo dicen los vectores, que son de las fuentes.
    final sourceOf = <String, String>{};
    for (final id in ids) {
      final document = await _processed.watchDocument(id).first;
      final sourceId = document?.summary.sourceItemId;
      if (sourceId != null) sourceOf[sourceId] = id;
    }
    final sourceIds = sourceOf.keys.toList();
    final ordered = sourceIds.length <= kDerivedNoteMaxSources
        ? sourceIds
        : await _vectors.representativeOrder(
            sourceIds,
            take: kDerivedNoteMaxSources,
          );
    final sources = <ChatSource>[];
    for (final sourceId in ordered) {
      if (sources.length == kDerivedNoteMaxSources) break;
      final source = await _citableProcessed(sourceOf[sourceId]!, sourceId);
      if (source != null) sources.add(source);
    }
    return sources;
  }

  /// Lo que se puede citar del documento procesado [documentId], de la fuente
  /// [sourceItemId]: la primera parte —en el orden en que se lee el
  /// documento— que sigue siendo, letra por letra, el texto principal de la
  /// fuente, con su posición ahí. Es la misma coordenada que usa una cita
  /// (`buildChatSource`), así que la afirmación se ancla al original.
  ///
  /// Una parte editada, una nota escrita o una sin ancla no se pueden citar:
  /// lo que el modelo dijera de ellas no tendría dónde anclarse. Si no queda
  /// ninguna, o la fuente ya no está, el documento no se cita.
  Future<ChatSource?> _citableProcessed(
    String documentId,
    String sourceItemId,
  ) async {
    final material = (await _processed.materialOf(
      sourceItemId,
      countWords: false,
    )).getRight().toNullable();
    final renditionId = material?.textRenditionId;
    if (material == null || renditionId == null) return null;
    for (final section in ProcessedSection.values) {
      final parts = await _processed
          .watchParts(documentId, section, limit: _kCitablePartsLooked)
          .first;
      for (final part in parts) {
        final anchor = part.anchor;
        if (!part.isPristineCopy || anchor?.renditionId != renditionId) {
          continue;
        }
        final raw = part.content;
        final trimmed = raw.trim();
        if (trimmed.isEmpty) continue;
        final start = anchor!.start + raw.indexOf(trimmed);
        final sliced = trimmed.length <= kChatSourceExcerptLength
            ? trimmed
            : trimmed.substring(0, kChatSourceExcerptLength);
        return ChatSource(
          itemId: sourceItemId,
          itemTitle: material.title,
          excerpt: sliced.length < trimmed.length ? '$sliced…' : sliced,
          sourceCharStart: start,
          sourceCharEnd: start + sliced.length,
        );
      }
    }
    return null;
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
