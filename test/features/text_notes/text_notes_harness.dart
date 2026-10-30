import 'package:drift/drift.dart' show Value;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/text_notes/data/repositories/text_note_repository_impl.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';

import '../../support/fake_id_generator.dart';
import '../../support/test_vault.dart';
import '../creations/creations_harness.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Una bóveda de prueba con las notas en el texto (F45, mejora 19), sobre
/// SQLite real en memoria: la Biblioteca, lo procesado y lo creado —los cuatro
/// textos que llevan notas— y el repositorio de las notas, con ids y reloj de
/// la bóveda.
class TextNotesHarness {
  TextNotesHarness._(this.creations)
    : notes = TextNoteRepositoryImpl(
        database: creations.processed.db,
        telemetry: _SilentTelemetry(),
        ids: FakeIdGenerator(
          prefix: 'nota-${creations.processed.vault.deviceId}',
        ),
        clock: () => creations.processed.vault.now,
      );

  static Future<TextNotesHarness> create({String deviceId = 'tel'}) async =>
      TextNotesHarness._(await CreationsHarness.create(deviceId: deviceId));

  final CreationsHarness creations;
  final TextNoteRepositoryImpl notes;

  TestVault get vault => creations.processed.vault;
  AppDatabase get db => creations.processed.db;

  Future<void> close() => creations.close();

  /// Una fuente de la Biblioteca con [text]: el original de sus notas, sobre
  /// su forma `rend-<id>`.
  Future<SourceOriginalNotes> source(String id, {required String text}) async {
    await vault.saveSource(id, text: text);
    return SourceOriginalNotes(sourceId: id, renditionId: 'rend-$id');
  }

  /// Una creación de Repasar sobre lo procesado, lista.
  Future<CreationNotes> creation() async {
    final created = (await creations.creations.create(
      const CreationRequest(
        kind: StudyCreationKind.report,
        scope: CreationScope.allProcessed(),
        sourceIds: ['doc'],
      ),
    )).getRight().toNullable()!;
    return CreationNotes(created.id);
  }

  /// Una nota sobre la primera aparición de [excerpt] en [text].
  Future<TextNote> noteOn(
    TextNoteTarget target,
    String text,
    String excerpt, {
    String note = 'Una nota',
    HighlightColor color = HighlightColor.lime,
  }) async {
    final start = text.indexOf(excerpt);
    if (start < 0) throw ArgumentError.value(excerpt, 'excerpt', 'no está');
    return (await notes.create(
      target: target,
      start: start,
      end: start + excerpt.length,
      excerpt: excerpt,
      note: note,
      color: color,
    )).getRight().toNullable()!;
  }

  /// Un resaltado de antes (F38) sobre [excerpt] del texto de la fuente
  /// [sourceId], con su nota.
  Future<void> highlightWithNote(
    String id,
    String sourceId,
    String text,
    String excerpt, {
    String? note,
    HighlightColor? color = HighlightColor.coral,
  }) {
    final start = text.indexOf(excerpt);
    return db
        .into(db.highlights)
        .insert(
          HighlightsCompanion.insert(
            id: id,
            renditionId: 'rend-$sourceId',
            startOffset: start,
            endOffset: start + excerpt.length,
            excerpt: excerpt,
            note: Value(note),
            createdAt: vault.now,
            color: Value(color),
          ),
        );
  }

  /// Las notas de [target], de una vez.
  Future<List<TextNote>> notesOf(TextNoteTarget target) =>
      notes.watchNotes(target).first;
}
