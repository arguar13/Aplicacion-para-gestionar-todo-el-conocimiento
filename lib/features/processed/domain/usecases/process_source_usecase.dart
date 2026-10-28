import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/domain/services/text_parts.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_source_material.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_images_planner.dart';
import 'package:sinapsis/features/processed/domain/services/processed_section_planner.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';

/// Procesar una fuente (F41): armar —o cambiar, al volver a triar— su
/// documento procesado con las partes que la persona eligió, sección por
/// sección, con agregar, actualizar, reemplazar y quitar, y con «Deshacer».
///
/// **Nunca toca la fuente** (decisión G y el principio de F41: «de la
/// Biblioteca nada se borra»). La lee —su texto, su resumen, su síntesis— para
/// copiar de ella, y nada más: ni su texto, ni su estado de la Bandeja, ni sus
/// marcas. Marcarla como triada es cosa de la Bandeja (paso 3).
///
/// Lo pesado —paginar un libro, comparar sus páginas— corre en otro hilo
/// cuando el texto es largo ([runProcessedWork]): procesar un libro no frena la
/// interfaz.
///
/// **Las imágenes** (decisión L) son una sección más para quien pide: entran,
/// se reemplazan y se quitan como las demás, en el mismo guardado y con el
/// mismo «Deshacer». Lo que cambia es que cada una es una copia propia de un
/// archivo: las copias se hacen antes de guardar, fuera de la base, y si el
/// guardado no llega se borran.
class ProcessSourceUseCase {
  const ProcessSourceUseCase(
    this._repository, {
    ProcessedWorker worker = runProcessedWork,
  }) : _worker = worker;

  final ProcessedRepository _repository;

  /// Dónde se hace lo pesado: [runProcessedWork] —en otro hilo si el texto es
  /// largo—. Las pruebas lo cambian para ver qué pasa por ahí.
  final ProcessedWorker _worker;

  /// Procesa [sourceItemId] con [edits]: una entrada por sección que se toca;
  /// las demás quedan como están. Con [original], también la copia del
  /// original (decisión H): agregar o reemplazar la copian, actualizar la
  /// vuelve a copiar solo si el archivo de la fuente cambió, quitar la manda a
  /// la papelera del contenido.
  ///
  /// La copia del archivo se hace antes de guardar, en el disco y en otro
  /// hilo; si guardar no llega, la copia se borra.
  ///
  /// Falla, sin escribir nada, si algún pedido no vale para su sección
  /// (`SectionEdit.problemFor`), si la fuente no es una fuente viva, si un
  /// corte no cae dentro de un texto de la fuente o si una oración elegida no
  /// es de ella, si se pide copiar un original que la fuente no ofrece, si
  /// una imagen elegida ya no está en la fuente o no se pudo copiar; y, para
  /// un documento que todavía no existe, si no queda nada que guardar.
  Future<Either<Failure, ProcessOutcome>> call(
    String sourceItemId,
    Map<ProcessedSection, SectionEdit> edits, {
    OriginalEdit? original,
  }) async {
    final planned = await _plan(sourceItemId, edits, original);
    return planned.match(left, (planned) async {
      StagedOriginal? stagedOriginal;
      if (planned.original == _OriginalStep.copy) {
        final copy = await _repository.stageOriginal(sourceItemId);
        if (copy.isLeft()) return left(copy.getLeft().toNullable()!);
        stagedOriginal = copy.getRight().toNullable();
      }
      final images = planned.images;
      final fresh = images?.fresh ?? const <SourceImage>[];
      final stagedImages = fresh.isEmpty
          ? right<Failure, List<StagedImage>>(const [])
          : await _repository.stageImages(sourceItemId, fresh);
      if (stagedImages.isLeft()) {
        if (stagedOriginal != null) {
          await _repository.discardStagedOriginal(stagedOriginal);
        }
        return left(stagedImages.getLeft().toNullable()!);
      }
      final staged = stagedImages.getRight().toNullable()!;
      final committed = await _repository.commit(
        ProcessedCommit(
          sourceItemId: sourceItemId,
          plans: planned.plans.values.toList(),
          expectedStatus: planned.status,
          original: switch (planned.original) {
            _OriginalStep.none => null,
            _OriginalStep.copy => PutOriginal(stagedOriginal!),
            _OriginalStep.refresh => const RefreshOriginal(),
            _OriginalStep.remove => const RemoveOriginal(),
          },
          images: images == null
              ? null
              : ProcessedImagesCommit(
                  plan: images,
                  staged: {for (final copy in staged) copy.source.path: copy},
                ),
        ),
      );
      if (committed.isLeft()) {
        if (stagedOriginal != null) {
          await _repository.discardStagedOriginal(stagedOriginal);
        }
        if (staged.isNotEmpty) await _repository.discardStagedImages(staged);
      }
      return committed.map(
        (undo) => ProcessOutcome(
          documentId: planned.documentId,
          created: planned.status == ProcessedDocumentStatus.absent,
          sections: {
            for (final plan in planned.plans.values)
              plan.section: SectionChangeTally(
                added: plan.added,
                removed: plan.removed.length,
                kept: plan.kept,
              ),
            if (images != null)
              ProcessedSection.images: SectionChangeTally(
                added: images.added,
                removed: images.removed.length,
                kept: images.kept,
              ),
          },
          undo: undo,
          original: switch (undo.original) {
            null => OriginalOutcome.untouched,
            ProcessedOriginalUndo(refreshed: true) => OriginalOutcome.refreshed,
            ProcessedOriginalUndo(copiedPath: _?) => OriginalOutcome.copied,
            _ => OriginalOutcome.removed,
          },
        ),
      );
    });
  }

  /// Qué pasaría con la copia del original si se procesa [sourceItemId] con
  /// [original], sin copiar nada: la línea «el original ocupa …» de la hoja.
  Future<Either<Failure, OriginalPreview>> previewOriginal(
    String sourceItemId,
    OriginalEdit original,
  ) async {
    final material = await _repository.materialOf(
      sourceItemId,
      countWords: false,
    );
    return material.match(left, (material) async {
      final documentId = processedDocumentIdFor(sourceItemId);
      final current = await _repository.originalOf(documentId);
      return current.match(left, (current) {
        final step = _originalStepFor(original, material, current);
        return step.map(
          (step) => OriginalPreview(
            outcome: switch (step) {
              _OriginalStep.none => OriginalOutcome.untouched,
              _OriginalStep.copy => OriginalOutcome.copied,
              _OriginalStep.refresh => OriginalOutcome.refreshed,
              _OriginalStep.remove => OriginalOutcome.removed,
            },
            sizeBytes: switch (step) {
              _OriginalStep.copy => material.original!.sizeBytes,
              _OriginalStep.remove => 0,
              _ => current?.sizeBytes ?? 0,
            },
          ),
        );
      });
    });
  }

  /// «Pasar todo sin modificar» (F41): el documento guarda el texto original
  /// entero de la fuente, con su enlace, y nada más —ni resumen, ni síntesis,
  /// ni notas, ni audio, ni video, ni la ficha—. Si el documento ya existe,
  /// trae la versión de ahora del texto conservando lo editado
  /// ([ProcessedChange.update]) y no toca las otras secciones.
  Future<Either<Failure, ProcessOutcome>> passUnchanged(String sourceItemId) =>
      call(sourceItemId, {ProcessedSection.text: SectionEdit.update()});

  /// Cómo quedaría cada sección de [edits], sin guardar nada: la vista previa
  /// en vivo de la hoja «¿Qué va a Procesado?», con las mismas reglas que
  /// [call].
  Future<Either<Failure, Map<ProcessedSection, SectionPreview>>> preview(
    String sourceItemId,
    Map<ProcessedSection, SectionEdit> edits,
  ) async {
    final planned = await _plan(sourceItemId, edits, null);
    return planned.match(left, (planned) async {
      final previews = <ProcessedSection, SectionPreview>{};
      for (final plan in planned.plans.values) {
        final contents = plan.contents;
        final size = contents.fold<int>(0, (sum, c) => sum + c.length);
        previews[plan.section] = SectionPreview(
          parts: plan.parts.length,
          words: await _worker(_wordsOf, contents, size: size),
          tally: SectionChangeTally(
            added: plan.added,
            removed: plan.removed.length,
            kept: plan.kept,
          ),
        );
      }
      if (planned.images case final images?) {
        previews[ProcessedSection.images] = SectionPreview(
          parts: images.images.length,
          words: 0,
          tally: SectionChangeTally(
            added: images.added,
            removed: images.removed.length,
            kept: images.kept,
          ),
          sizeBytes: images.sizeBytes,
          addedBytes: images.addedBytes,
        );
      }
      return right(previews);
    });
  }

  /// Deshace lo que dejó un [call]: ver `ProcessedRepository.undo`.
  Future<Either<Failure, Unit>> undo(ProcessUndo undo) =>
      _repository.undo(undo);

  // ---------------------------------------------------------------------

  /// Qué hacer con la copia del original, según lo pedido, lo que la fuente
  /// ofrece y la que ya hay.
  static Either<Failure, _OriginalStep> _originalStepFor(
    OriginalEdit? edit,
    ProcessedSourceMaterial material,
    ProcessedOriginal? current,
  ) {
    if (edit == null) return right(_OriginalStep.none);
    final offer = material.original;
    const notOffered = Failure.validation(
      message: 'Esta fuente no tiene un original que copiar.',
    );
    switch (edit.change) {
      case ProcessedChange.remove:
        return right(
          current == null ? _OriginalStep.none : _OriginalStep.remove,
        );
      case ProcessedChange.add:
        if (current != null) return right(_OriginalStep.none);
        return offer == null ? left(notOffered) : right(_OriginalStep.copy);
      case ProcessedChange.replace:
        return offer == null ? left(notOffered) : right(_OriginalStep.copy);
      case ProcessedChange.update:
        if (offer == null) {
          // La fuente ya no tiene su archivo: la copia es propia y se queda.
          return current == null ? left(notOffered) : right(_OriginalStep.none);
        }
        if (current == null) return right(_OriginalStep.copy);
        // Un original de la Biblioteca no se reescribe: otro archivo es otra
        // ruta. El mismo archivo con el mismo peso es el mismo: solo puede
        // haber cambiado su texto extraído.
        final same =
            current.sourceFilePath == offer.relativePath &&
            current.sizeBytes == offer.sizeBytes;
        return right(same ? _OriginalStep.refresh : _OriginalStep.copy);
    }
  }

  Future<Either<Failure, _Planned>> _plan(
    String sourceItemId,
    Map<ProcessedSection, SectionEdit> edits,
    OriginalEdit? original,
  ) async {
    if (edits.isEmpty && original == null) {
      return left(const Failure.validation(message: 'No se pidió nada.'));
    }
    for (final MapEntry(key: section, value: edit) in edits.entries) {
      final problem = edit.problemFor(section);
      if (problem != null) return left(Failure.validation(message: problem));
    }

    final material = await _repository.materialOf(
      sourceItemId,
      countWords: false,
    );
    return material.match(left, (material) async {
      final documentId = processedDocumentIdFor(sourceItemId);
      final status = await _repository.statusOf(documentId);
      return status.match(left, (status) async {
        final current = status == ProcessedDocumentStatus.absent
            ? null
            : (await _repository.originalOf(documentId)).getOrElse((_) => null);
        final originalStep = _originalStepFor(original, material, current);
        if (originalStep.isLeft()) {
          return left(originalStep.getLeft().toNullable()!);
        }
        final step = originalStep.getRight().toNullable()!;
        // Las imágenes no son partes de texto: se planean aparte.
        final textEdits = {
          for (final MapEntry(key: section, value: edit) in edits.entries)
            if (!section.holdsFiles) section: edit,
        };
        final existing =
            status == ProcessedDocumentStatus.absent || textEdits.isEmpty
            ? const <ProcessedPart>[]
            : await _repository
                  .partsOf(documentId, sections: textEdits.keys.toSet())
                  .then((parts) => parts.getOrElse((_) => const []));
        final texts = _SourceTexts(_repository, sourceItemId, material);
        final plans = <ProcessedSection, SectionPlan>{};
        for (final MapEntry(key: section, value: edit) in textEdits.entries) {
          final current = [
            for (final part in existing)
              if (part.section == section) part,
          ];
          final fresh = await _candidates(
            section,
            edit,
            current: current,
            material: material,
            texts: texts,
          );
          if (fresh.isLeft()) return left(fresh.getLeft().toNullable()!);
          final candidates = fresh.getRight().toNullable()!;
          final size =
              candidates.fold<int>(0, (sum, c) => sum + c.content.length) +
              current.fold<int>(0, (sum, p) => sum + p.content.length);
          plans[section] = await _worker(
            _planInWorker,
            _PlanRequest(section, current, edit.change, candidates),
            size: size,
          );
        }
        ImagesPlan? images;
        if (edits[ProcessedSection.images] case final edit?) {
          final planned = await _imagesPlan(
            sourceItemId,
            documentId,
            status,
            edit,
          );
          if (planned.isLeft()) return left(planned.getLeft().toNullable()!);
          images = planned.getRight().toNullable();
        }
        if (status == ProcessedDocumentStatus.absent &&
            step != _OriginalStep.copy &&
            plans.values.every((plan) => plan.parts.isEmpty) &&
            (images?.images.isEmpty ?? true)) {
          return left(
            const Failure.validation(
              message: 'No hay nada que procesar todavía en esta fuente.',
            ),
          );
        }
        return right(
          _Planned(
            documentId: documentId,
            status: status,
            plans: plans,
            original: step,
            images: images,
          ),
        );
      });
    });
  }

  /// Cómo queda la galería de [documentId] con [edit]: lo elegido se lee de la
  /// lista de la fuente —«Todas» no enumera nada hasta acá—, en su orden.
  Future<Either<Failure, ImagesPlan>> _imagesPlan(
    String sourceItemId,
    String documentId,
    ProcessedDocumentStatus status,
    SectionEdit edit,
  ) async {
    final existing = status == ProcessedDocumentStatus.absent
        ? right<Failure, List<ProcessedImage>>(const [])
        : await _repository.imagesOf(documentId);
    return existing.match(left, (existing) async {
      final choice = switch (edit.input) {
        FromImages(:final choice) => choice,
        _ => null,
      };
      if (choice == null) {
        return right(
          planImagesChange(
            existing: existing,
            change: edit.change,
            chosen: const [],
          ),
        );
      }
      final offered = await _repository.sourceImages(sourceItemId);
      return offered.match(left, (offered) {
        if (choice case SomeImages(:final paths)) {
          final known = {for (final image in offered) image.path};
          if (!known.containsAll(paths)) {
            return left(
              const Failure.validation(
                message: 'Una imagen elegida ya no está en esta fuente.',
              ),
            );
          }
        }
        return right(
          planImagesChange(
            existing: existing,
            change: edit.change,
            chosen: [
              for (final image in offered)
                if (choice.includes(image.path)) image,
            ],
          ),
        );
      });
    });
  }

  /// Lo nuevo de [section], resuelto contra la fuente.
  Future<Either<Failure, List<ProcessedCandidate>>> _candidates(
    ProcessedSection section,
    SectionEdit edit, {
    required List<ProcessedPart> current,
    required ProcessedSourceMaterial material,
    required _SourceTexts texts,
  }) async {
    final input = edit.input;
    switch (input) {
      case null:
        return right(const []);
      // Las imágenes no son partes de texto: las planea `_imagesPlan`.
      case FromImages():
        return left(
          const Failure.validation(
            message: 'Las imágenes no son partes de texto.',
          ),
        );
      case FromSource() when section == ProcessedSection.text:
        final text = await texts.main();
        return text.match(left, (text) async {
          if (text == null) return right(const <ProcessedCandidate>[]);
          // Al actualizar, lo que la persona editó no se vuelve a paginar: el
          // texto de ahora se corta alrededor (ver `processedTextPages`).
          final excluded = edit.change == ProcessedChange.update
              ? _editedRanges(current, text.renditionId)
              : const <ProcessedRange>[];
          final pages = await _worker(
            _pagesInWorker,
            _PagesRequest(text.text, excluded),
            size: text.text.length,
          );
          return right([
            for (final page in pages)
              if (page.text.isNotEmpty)
                ProcessedCandidate(
                  content: page.text,
                  origin: ProcessedPartOrigin.copied,
                  anchor: ProcessedAnchor(
                    renditionId: text.renditionId,
                    start: page.start,
                    end: page.end,
                  ),
                ),
          ]);
        });
      case FromSource() when section == ProcessedSection.keywords:
        return right(_keywordCandidates(material.keywords));
      case FromSource():
        return right(_sentences(_sentencesOf(section, material)));
      case FromSentences(:final studyMarkIds)
          when section == ProcessedSection.keywords:
        final offered = {
          for (final sentence in material.keywords)
            for (final keyword in sentence.keywords) keyword.studyMarkId,
        };
        if (!offered.containsAll(studyMarkIds)) {
          return left(
            const Failure.validation(
              message: 'Una palabra clave elegida ya no está en esta fuente.',
            ),
          );
        }
        return right(_keywordCandidates(material.keywords, only: studyMarkIds));
      case FromSentences(:final studyMarkIds):
        final offered = {
          for (final sentence in _sentencesOf(section, material))
            sentence.studyMarkId: sentence,
        };
        final missing = studyMarkIds.difference(offered.keys.toSet());
        if (missing.isNotEmpty) {
          return left(
            const Failure.validation(
              message: 'Una oración elegida ya no está en esta fuente.',
            ),
          );
        }
        return right(
          _sentences([
            for (final sentence in offered.values)
              if (studyMarkIds.contains(sentence.studyMarkId)) sentence,
          ]),
        );
      case FromDrafts(:final drafts):
        final candidates = <ProcessedCandidate>[];
        for (final draft in drafts) {
          final resolved = await _resolveDraft(draft, texts);
          if (resolved.isLeft()) return left(resolved.getLeft().toNullable()!);
          candidates.add(resolved.getRight().toNullable()!);
        }
        return right(candidates);
    }
  }

  Future<Either<Failure, ProcessedCandidate>> _resolveDraft(
    ProcessedDraft draft,
    _SourceTexts texts,
  ) async {
    final anchor = switch (draft) {
      ProcessedCut(:final anchor) => anchor,
      ProcessedWritten(:final anchor) => anchor,
    };
    String? excerpt;
    if (anchor != null) {
      final text = await texts.of(anchor.renditionId);
      final failure = text.match(
        (failure) => failure,
        (text) => text == null || anchor.end > text.text.length
            ? const Failure.validation(
                message: 'El pasaje elegido no está en el texto de la fuente.',
              )
            : null,
      );
      if (failure != null) return left(failure);
      excerpt = text.getRight().toNullable()!.text.substring(
        anchor.start,
        anchor.end,
      );
    }
    return switch (draft) {
      ProcessedCut() when excerpt!.trim().isEmpty => left(
        const Failure.validation(message: 'El pasaje elegido está vacío.'),
      ),
      ProcessedCut() => right(
        ProcessedCandidate(
          content: excerpt!,
          origin: ProcessedPartOrigin.copied,
          anchor: anchor,
        ),
      ),
      ProcessedWritten(:final content) => right(
        ProcessedCandidate(
          content: content.trim(),
          origin: ProcessedPartOrigin.user,
          anchor: anchor,
        ),
      ),
    };
  }

  static List<ProcessedSentence> _sentencesOf(
    ProcessedSection section,
    ProcessedSourceMaterial material,
  ) => section == ProcessedSection.summary
      ? material.summary
      : material.synthesis;

  /// Las oraciones con palabras clave de la fuente, cada una con los tramos de
  /// sus palabras adentro; con [only], solo esas palabras —y solo las
  /// oraciones que tienen alguna—.
  static List<ProcessedCandidate> _keywordCandidates(
    List<ProcessedKeywordSentence> sentences, {
    Set<String>? only,
  }) => [
    for (final sentence in sentences)
      if ([
            for (final keyword in sentence.keywords)
              if (only == null || only.contains(keyword.studyMarkId)) keyword,
          ]
          case final keywords when keywords.isNotEmpty)
        ProcessedCandidate(
          content: sentence.content,
          origin: ProcessedPartOrigin.copied,
          anchor: sentence.anchor,
          spans: [
            for (final keyword in keywords)
              ProcessedSpan(
                start: keyword.start - sentence.anchor.start,
                end: keyword.end - sentence.anchor.start,
              ),
          ],
        ),
  ];

  static List<ProcessedCandidate> _sentences(List<ProcessedSentence> list) => [
    for (final sentence in list)
      ProcessedCandidate(
        content: sentence.content,
        origin: ProcessedPartOrigin.copied,
        anchor: sentence.anchor,
      ),
  ];

  /// Los tramos del texto [renditionId] que ocupan las páginas que la persona
  /// editó, ordenados y sin solaparse.
  static List<ProcessedRange> _editedRanges(
    List<ProcessedPart> parts,
    String renditionId,
  ) {
    final ranges = [
      for (final part in parts)
        if (!part.isPristineCopy && part.anchor?.renditionId == renditionId)
          (start: part.anchor!.start, end: part.anchor!.end),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final merged = <ProcessedRange>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.start <= merged.last.end) {
        final last = merged.removeLast();
        merged.add((
          start: last.start,
          end: range.end > last.end ? range.end : last.end,
        ));
      } else {
        merged.add(range);
      }
    }
    return merged;
  }
}

/// Los textos de la fuente que se leen al procesar, cada uno una sola vez.
class _SourceTexts {
  _SourceTexts(this._repository, this._sourceItemId, this._material);

  final ProcessedRepository _repository;
  final String _sourceItemId;
  final ProcessedSourceMaterial _material;
  final _cache = <String, Either<Failure, ProcessedSourceText?>>{};

  /// El texto del que sale todo; `null` si la fuente todavía no tiene.
  Future<Either<Failure, ProcessedSourceText?>> main() async {
    final id = _material.textRenditionId;
    return id == null ? right(null) : of(id);
  }

  Future<Either<Failure, ProcessedSourceText?>> of(String renditionId) async =>
      _cache[renditionId] ??= await _repository.sourceText(
        _sourceItemId,
        renditionId: renditionId,
      );
}

class _Planned {
  const _Planned({
    required this.documentId,
    required this.status,
    required this.plans,
    required this.original,
    this.images,
  });

  final String documentId;
  final ProcessedDocumentStatus status;
  final Map<ProcessedSection, SectionPlan> plans;
  final _OriginalStep original;

  /// Cómo queda la galería, si se pidió.
  final ImagesPlan? images;
}

/// Qué se le va a hacer a la copia del original.
enum _OriginalStep { none, copy, refresh, remove }

class _PlanRequest {
  const _PlanRequest(this.section, this.existing, this.change, this.fresh);

  final ProcessedSection section;
  final List<ProcessedPart> existing;
  final ProcessedChange change;
  final List<ProcessedCandidate> fresh;
}

SectionPlan _planInWorker(_PlanRequest request) => planSectionChange(
  section: request.section,
  existing: request.existing,
  change: request.change,
  fresh: request.fresh,
);

class _PagesRequest {
  const _PagesRequest(this.text, this.excluded);

  final String text;
  final List<ProcessedRange> excluded;
}

List<TextPart> _pagesInWorker(_PagesRequest request) =>
    processedTextPages(request.text, excluded: request.excluded);

int _wordsOf(List<String> contents) =>
    contents.fold(0, (sum, content) => sum + processedWordCount(content));
