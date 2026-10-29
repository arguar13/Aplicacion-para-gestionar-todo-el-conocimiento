import 'package:drift/drift.dart' show Variable;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/creations/data/repositories/creation_scope_resolver_impl.dart';
import 'package:sinapsis/features/creations/data/repositories/study_creation_repository_impl.dart';
import 'package:sinapsis/features/creations/domain/services/creation_material_builder.dart';
import 'package:sinapsis/features/flashcards/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_scope_resolver.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';

import '../../support/fake_id_generator.dart';
import '../processed/processed_harness.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Una bóveda de prueba con lo procesado y lo de «Lo creado» (F43), sobre
/// SQLite real: el repositorio de creaciones, el recorte de Procesado, el
/// armado del material y la cola de estudio de Repasar con el recorte nuevo.
class CreationsHarness {
  CreationsHarness._(this.processed, {ProcessedWorker? worker}) {
    final telemetry = _SilentTelemetry();
    notebooks = NotebookRepositoryImpl(
      database: processed.db,
      processed: processed.repository,
      telemetry: telemetry,
      ids: FakeIdGenerator(prefix: 'cuaderno'),
      clock: () => processed.vault.now,
    );
    scopes = CreationScopeResolverImpl(
      database: processed.db,
      processed: processed.repository,
      notebooks: notebooks,
      telemetry: telemetry,
    );
    creations = StudyCreationRepositoryImpl(
      database: processed.db,
      telemetry: telemetry,
      ids: FakeIdGenerator(prefix: 'creacion-${processed.vault.deviceId}'),
      clock: () => processed.vault.now,
    );
    material = CreationMaterialBuilder(
      processed: processed.repository,
      scopes: scopes,
      worker: worker ?? runProcessedWork,
    );
    study = StudyRepositoryImpl(
      database: processed.db,
      telemetry: telemetry,
      clock: () => processed.vault.now,
      resolver: StudyScopeResolver(
        library: processed.vault.library,
        notebooks: notebooks,
        processed: scopes,
      ),
    );
  }

  static Future<CreationsHarness> create({
    ProcessedWorker? worker,
    String deviceId = 'tel',
  }) async => CreationsHarness._(
    await ProcessedHarness.create(worker: worker, deviceId: deviceId),
    worker: worker,
  );

  final ProcessedHarness processed;
  late final NotebookRepositoryImpl notebooks;
  late final CreationScopeResolverImpl scopes;
  late final StudyCreationRepositoryImpl creations;
  late final CreationMaterialBuilder material;
  late final StudyRepositoryImpl study;

  Future<void> close() => processed.close();

  /// Guarda la fuente [sourceId] con [text] y la pasa entera a Procesado; con
  /// [summary] o [synthesis], esos tramos del texto quedan como sus oraciones.
  /// Devuelve el id del documento procesado.
  Future<String> processedDoc(
    String sourceId, {
    String? title,
    String text = 'Moisés guía al pueblo. El mar se abre. Llegan al Sinaí.',
    List<(int, int)> summary = const [],
    List<(int, int)> synthesis = const [],
  }) async {
    await processed.vault.saveSource(sourceId, title: title, text: text);
    for (final (i, (start, end)) in summary.indexed) {
      await processed.addSentence(
        '$sourceId-r$i',
        sourceId,
        text,
        start: start,
        end: end,
      );
    }
    for (final (i, (start, end)) in synthesis.indexed) {
      await processed.addSentence(
        '$sourceId-s$i',
        sourceId,
        text,
        start: start,
        end: end,
        kind: StudyMarkKind.synthesis,
      );
    }
    final result = await processed.process(sourceId, {
      ProcessedSection.text: SectionEdit.update(),
      if (summary.isNotEmpty)
        ProcessedSection.summary: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
      if (synthesis.isNotEmpty)
        ProcessedSection.synthesis: SectionEdit.add(
          const SectionInput.fromSource(),
        ),
    });
    if (result.isLeft()) throw StateError('No se procesó: $result');
    return processedDocumentIdFor(sourceId);
  }

  /// Pone a [itemId] en el tema [spaceId] (F37).
  Future<void> putInSpace(String itemId, String spaceId) =>
      processed.db.customStatement(
        'INSERT INTO item_spaces (item_id, space_id) VALUES (?, ?)',
        [itemId, spaceId],
      );

  /// Hace a [childId] rama de [parentId] en el vocabulario.
  Future<void> nest(String childId, String parentId) =>
      processed.db.customUpdate(
        'UPDATE property_values SET parent_id = ? WHERE id = ?',
        variables: [
          Variable.withString(parentId),
          Variable.withString(childId),
        ],
      );
}
