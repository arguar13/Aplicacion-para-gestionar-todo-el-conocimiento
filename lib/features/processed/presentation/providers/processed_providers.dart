import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_source_material.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_study_text.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';

/// Los documentos procesados (F41).
final processedRepositoryProvider = Provider<ProcessedRepository>(
  (ref) => ProcessedRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    files: ref.watch(fileStoreProvider),
  ),
);

/// Procesar una fuente: crear o cambiar su documento procesado, con deshacer.
final processSourceUseCaseProvider = Provider<ProcessSourceUseCase>(
  (ref) => ProcessSourceUseCase(ref.watch(processedRepositoryProvider)),
);

/// La lista de «Procesado» para [ProcessedQuery], y cada cambio.
final processedDocumentsProvider = StreamProvider.autoDispose
    .family<List<ProcessedDocumentSummary>, ProcessedQuery>(
      (ref, query) =>
          ref.watch(processedRepositoryProvider).watchDocuments(query),
    );

/// Cuántos documentos cumplen [ProcessedQuery], sin paginar.
final processedCountProvider = StreamProvider.autoDispose
    .family<int, ProcessedQuery>(
      (ref, query) => ref.watch(processedRepositoryProvider).watchCount(query),
    );

/// Un documento procesado por su id —vivo o en la papelera—, o `null`.
final processedDocumentProvider = StreamProvider.autoDispose
    .family<ProcessedDocument?, String>(
      (ref, documentId) =>
          ref.watch(processedRepositoryProvider).watchDocument(documentId),
    );

/// El documento procesado de una fuente, o `null` si no tiene.
final processedDocumentForSourceProvider = StreamProvider.autoDispose
    .family<ProcessedDocument?, String>(
      (ref, sourceItemId) =>
          ref.watch(processedRepositoryProvider).watchForSource(sourceItemId),
    );

/// Las fuentes que ya tienen su procesado vivo: el chip «Procesado».
final processedSourceIdsProvider = StreamProvider.autoDispose<Set<String>>(
  (ref) => ref.watch(processedRepositoryProvider).watchProcessedSourceIds(),
);

/// Qué partes de un documento pedir: una sección y, para las páginas del
/// texto de un libro, un tramo.
typedef ProcessedPartsKey = ({
  String documentId,
  ProcessedSection section,
  int offset,
  int? limit,
});

/// Las partes de una sección —o un tramo de ellas—, y cada cambio.
final processedPartsProvider = StreamProvider.autoDispose
    .family<List<ProcessedPart>, ProcessedPartsKey>(
      (ref, key) => ref
          .watch(processedRepositoryProvider)
          .watchParts(
            key.documentId,
            key.section,
            offset: key.offset,
            limit: key.limit,
          ),
    );

/// La copia del original de un documento procesado, o `null` si no tiene
/// (decisión H).
final processedOriginalProvider = StreamProvider.autoDispose
    .family<ProcessedOriginal?, String>(
      (ref, documentId) =>
          ref.watch(processedRepositoryProvider).watchOriginal(documentId),
    );

/// Lo que se pinta sobre la copia del original —lo elegido del procesado, con
/// las posiciones del texto de la fuente—, o `null` si no hay qué pintar. El
/// visor de la copia lo usa en lugar de lo estudiado de la fuente:
/// `documentStudyProvider(marks.sourceKey).overrideWith(...)` con
/// `marks.study`, en el `ProviderScope` del visor.
final processedOriginalMarksProvider = StreamProvider.autoDispose
    .family<ProcessedOriginalMarks?, String>(
      (ref, documentId) =>
          ref.watch(processedRepositoryProvider).watchOriginalMarks(documentId),
    );

/// El texto propio de un documento procesado para estudiarlo en él (decisión
/// I) —o por qué no—; `null` adentro si no tiene texto que estudiar. Su
/// `asStudyText` va a la tarjeta de estudiar de siempre.
final processedStudyTextProvider = FutureProvider.autoDispose
    .family<Either<Failure, ProcessedStudyText?>, String>(
      (ref, documentId) =>
          ref.watch(processedRepositoryProvider).studyTextOf(documentId),
    );

/// Lo que una fuente ofrece para procesar —o por qué no se puede—: la hoja
/// «¿Qué va a Procesado?».
final processedSourceMaterialProvider = FutureProvider.autoDispose
    .family<Either<Failure, ProcessedSourceMaterial>, String>(
      (ref, sourceItemId) =>
          ref.watch(processedRepositoryProvider).materialOf(sourceItemId),
    );
