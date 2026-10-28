import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';

import '../../../support/library_harness.dart';

/// Lo que las pruebas de las pantallas de «Procesado» (F41) necesitan armar:
/// fuentes con texto y sus documentos procesados, por el caso de uso real y
/// sobre la base real en memoria de [LibraryHarness].
extension ProcessedUiFixture on LibraryHarness {
  /// Guarda una fuente con [text] en su forma `rend-<id>` y, con
  /// [originalName], su archivo original —con [originalBytes]— en el almacén
  /// de prueba: lo que se puede copiar a Procesado (decisión H).
  Future<void> saveTextSource(
    String id, {
    String? title,
    String text = 'La república romana cayó. César cruzó el Rubicón.',
    SourceKind kind = SourceKind.webPage,
    DateTime? at,
    String? originalName,
    List<int> originalBytes = const [60, 104, 116, 109, 108, 62],
  }) async {
    final when = at ?? DateTime(2026, 10, 20, 12);
    final originalPath = originalName == null
        ? null
        : await files.save(
            bytes: Uint8List.fromList(originalBytes),
            suggestedName: originalName,
            id: id,
          );
    final item = KnowledgeItem(
      id: id,
      title: title ?? 'Fuente $id',
      source: Source(
        id: id,
        kind: kind,
        capturedAt: when,
        url: 'https://ejemplo.org/$id',
        originalFilePath: originalPath,
      ),
      processingState: ProcessingState.ready,
      createdAt: when,
      updatedAt: when,
      renditions: [
        Rendition.text(
          id: 'rend-$id',
          itemId: id,
          kind: RenditionKind.markdown,
          content: text,
          isPrimary: true,
          createdAt: when,
        ),
      ],
    );
    final saved = await container.read(libraryRepositoryProvider).save(item);
    saved.getOrElse((failure) => throw StateError('$failure'));
  }

  /// Guarda una imagen [id] —sin texto— con [extra] fotos más en su
  /// «Contenido» (decisión L), y devuelve las rutas de todas, en orden.
  Future<List<String>> saveImageSource(String id, {int extra = 2}) async {
    final when = DateTime(2026, 10, 28, 12);
    final own = await files.save(
      bytes: Uint8List(100),
      suggestedName: 'foto.png',
      id: id,
    );
    final saved = await container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: 'Imagen $id',
            source: Source(
              id: id,
              kind: SourceKind.image,
              capturedAt: when,
              originalFilePath: own,
            ),
            processingState: ProcessingState.ready,
            createdAt: when,
            updatedAt: when,
          ),
        );
    saved.getOrElse((failure) => throw StateError('$failure'));
    final paths = [own];
    for (var i = 0; i < extra; i++) {
      final path = await files.saveStream(
        bytes: Stream.value(List.filled(10, 0)),
        suggestedName: 'f$i.jpg',
        id: id,
        folder: 'contenido',
      );
      await database
          .into(database.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'foto-$id-$i',
              itemId: id,
              kind: RenditionKind.image,
              relativePath: Value(path),
              isPrimary: false,
              createdAt: when,
              position: Value(i),
              sizeBytes: const Value(10),
              title: Value('Foto $i'),
            ),
          );
      paths.add(path);
    }
    return paths;
  }

  /// Procesa [sourceId] con [edits] y devuelve el id del documento.
  Future<String> process(
    String sourceId,
    Map<ProcessedSection, SectionEdit> edits, {
    OriginalEdit? original,
  }) async {
    final result = await container.read(processSourceUseCaseProvider)(
      sourceId,
      edits,
      original: original,
    );
    return result
        .getOrElse((failure) => throw StateError('$failure'))
        .documentId;
  }

  /// El texto entero de la fuente y, además, las [notes] escritas.
  Future<String> processTextAndNotes(
    String sourceId, {
    List<String> notes = const [],
  }) => process(sourceId, {
    ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
    if (notes.isNotEmpty)
      ProcessedSection.notes: SectionEdit.add(
        SectionInput.drafts([for (final n in notes) ProcessedDraft.written(n)]),
      ),
  });

  /// Un fragmento cortado de [text] —el texto de la fuente— en [passage].
  SectionEdit fragmentOf(String sourceId, String text, String passage) {
    final start = text.indexOf(passage);
    return SectionEdit.add(
      SectionInput.drafts([
        ProcessedDraft.cut(
          ProcessedAnchor(
            renditionId: 'rend-$sourceId',
            start: start,
            end: start + passage.length,
          ),
        ),
      ]),
    );
  }

  /// Una oración del resumen de [sourceId] —una marca de estudio— sobre
  /// [passage] de [text].
  Future<String> addSummarySentence(
    String sourceId,
    String text,
    String passage, {
    StudyMarkKind kind = StudyMarkKind.summary,
  }) async {
    final start = text.indexOf(passage);
    final id = 'marca-${passage.hashCode}';
    await database
        .into(database.studyMarks)
        .insert(
          StudyMarksCompanion.insert(
            id: id,
            renditionId: 'rend-$sourceId',
            kind: kind,
            origin: ContentOrigin.ai,
            startOffset: start,
            endOffset: start + passage.length,
            excerpt: passage,
            createdAt: DateTime(2026, 10, 20, 12),
          ),
        );
    return id;
  }

  /// Cambia el texto de la fuente [id] en la base sin tocar la copia de su
  /// original: lo que pasa al volver a extraerlo. Lo elegido ya no se marca
  /// sobre la copia.
  Future<void> changeSourceTextHash(String id) =>
      (database.update(database.knowledgeSources)
            ..where((s) => s.itemId.equals(id)))
          .write(const KnowledgeSourcesCompanion(contentHash: Value('otro')));

  /// Deja la fuente [id] triada, como la dejaba la Bandeja antes de F41.
  Future<void> markTriaged(String id) =>
      (database.update(
        database.knowledgeEntries,
      )..where((e) => e.id.equals(id))).write(
        const KnowledgeEntriesCompanion(state: Value(ItemState.triaged)),
      );

  /// El id del documento procesado de [sourceId].
  String documentOf(String sourceId) => processedDocumentIdFor(sourceId);
}

/// Monta la app con su router de verdad, en un ancho de escritorio y alto de
/// sobra, y espera a que se asiente.
Future<void> pumpApp(WidgetTester tester, LibraryHarness harness) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness.wrapWithAppRouter());
  await tester.pumpAndSettle();
}

/// Lo mismo que [pumpApp], en un teléfono angosto y con la letra al doble: lo
/// que no puede desbordar.
Future<void> pumpPhoneWithLargeText(
  WidgetTester tester,
  LibraryHarness harness,
) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(harness.wrapWithAppRouter());
  await tester.pumpAndSettle();
}

/// Lleva el router a [location], apilando, y espera.
Future<void> pushAndSettle(
  WidgetTester tester,
  LibraryHarness harness,
  String location,
) async {
  harness.pushTo(location);
  await tester.pumpAndSettle();
}

/// Va a [location] reemplazando la pila, y espera.
Future<void> goAndSettle(
  WidgetTester tester,
  LibraryHarness harness,
  String location,
) async {
  harness.container.read(goRouterProvider).go(location);
  await tester.pumpAndSettle();
}
