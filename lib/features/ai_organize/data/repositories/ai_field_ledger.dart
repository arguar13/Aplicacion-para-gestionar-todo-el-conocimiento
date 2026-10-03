import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';

/// El tema y los datos de la referencia que la IA completa en una pasada
/// (F27, v35), con lo que hace falta para deshacerlos: `ai_field_changes`.
///
/// Un vínculo, una tarjeta o una propiedad son filas que llevan su pasada;
/// el tema y la referencia son columnas del elemento. Lo que se guarda de
/// cada uno es el valor de antes y el que puso la IA, como texto
/// ([_encode]); con eso:
///
/// - **deshacer** devuelve cada dato a como estaba **solo si sigue con lo que
///   puso la IA** —si la persona lo cambió después, ya es suyo—;
/// - **lo que todavía es de la IA** se cuenta comparando con el valor de hoy,
///   igual que los vínculos y las tarjetas que la persona no adoptó.
///
/// Escribe por `KnowledgeEntryWriter`, como cualquier edición: cada cambio
/// queda versionado para la fusión de bóvedas.
///
/// Lee el elemento y su referencia por su clave, esté vivo o en la papelera:
/// deshacer devuelve el dato a como estaba en cualquier caso, y no lista nada.
class AiFieldLedger {
  const AiFieldLedger(
    this._db, {
    required IdGenerator ids,
    required Clock clock,
  }) : _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  KnowledgeEntryWriter get _writer =>
      KnowledgeEntryWriter(_db, clock: _clock, ids: _ids);

  /// Pone a [itemId] en el tema [spaceId] dentro de la pasada [runId], si
  /// todavía no tiene ninguno: lo que la persona eligió —también mientras el
  /// modelo pensaba— no se toca. Devuelve si lo puso. Corre dentro de la
  /// transacción de quien llama.
  Future<bool> applySpace({
    required String runId,
    required String itemId,
    required String spaceId,
  }) async {
    final before = await _spaceOf(itemId);
    if (before.missing || before.spaceId != null) return false;
    await _writer.setSpace([itemId], spaceId);
    await _record(runId, AiChangedField.space, null, spaceId);
    return true;
  }

  /// Completa, dentro de la pasada [runId], **solo los datos vacíos** de la
  /// referencia de [itemId] con lo que se leyó de su archivo o su página:
  /// nunca pisa lo que la persona escribió. Devuelve cuántos completó.
  ///
  /// Lo que una pasada anterior ya completó, y sigue en pie, no se repite: si
  /// la persona borró después un dato, fue a propósito. La sugerencia de
  /// datos que hubiera dejado pendiente el procesamiento queda aceptada: es
  /// la misma lectura, ya aplicada. Corre dentro de la transacción de quien
  /// llama.
  Future<int> completeReference({
    required String runId,
    required String itemId,
    required ExtractedMetadata extracted,
  }) async {
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(itemId))).getSingleOrNull();
    // Una nota no tiene referencia.
    if (source == null) return 0;
    if (await _referenceCompletedBefore(itemId, exceptRun: runId)) return 0;

    final before = await ReferenceReader(_db).read(itemId);
    final wanted = _fillEmpty(before, extracted.reference);
    final datesFilled =
        source.publishedAt == null && extracted.publishedAt != null;
    final reference = datesFilled
        ? _withPrecision(wanted, extracted.publicationPrecision)
        : wanted;

    if (reference != before) {
      await _writer.setReference(itemId, reference);
    }
    if (datesFilled) {
      await _writer.setFieldFromText(
        itemId,
        EntryField.publishedAt,
        '${extracted.publishedAt!.millisecondsSinceEpoch ~/ 1000}',
      );
    }

    // Lo que quedó de verdad —el escritor normaliza los textos y resuelve las
    // personas—: eso es lo que hay que reconocer después como de la IA.
    final after = await ReferenceReader(_db).read(itemId);
    final publishedAfter = (await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(itemId))).getSingle()).publishedAt;

    var completed = 0;
    for (final field in AiChangedField.values.where((f) => f.isReference)) {
      final was = _encode(field, before, source.publishedAt);
      final now = _encode(field, after, publishedAfter);
      if (now == null || now == was) continue;
      await _record(runId, field, was, now);
      completed++;
    }

    await (_db.update(_db.suggestions)..where(
          (s) =>
              s.targetItemId.equals(itemId) &
              s.kind.equalsValue(SuggestionKind.metadata) &
              s.status.equalsValue(SuggestionStatus.pending),
        ))
        .write(
          const SuggestionsCompanion(status: Value(SuggestionStatus.accepted)),
        );
    return completed;
  }

  /// Devuelve a como estaban el tema y los datos de la referencia que
  /// completó la pasada [runId] y que siguen con lo que puso la IA. Devuelve
  /// cuántos de cada uno. Corre dentro de la transacción de quien llama.
  Future<AiRunTally> undo(String runId) async {
    final itemId = await _itemOf(runId);
    if (itemId == null) return const AiRunTally();
    final changes = await _changesOf([runId]);
    if (changes.isEmpty) return const AiRunTally();

    final current = await _currentOf(itemId);
    var spaces = 0;
    var reference = current.reference;
    var publishedAt = current.publishedAt;
    var referenceFields = 0;
    var dateRestored = false;
    for (final change in changes) {
      if (_encode(
            change.field,
            current.reference,
            current.publishedAt,
            spaceId: current.spaceId,
          ) !=
          change.afterValue) {
        continue;
      }
      if (change.field == AiChangedField.space) {
        await _writer.setSpace([itemId], change.beforeValue);
        spaces++;
        continue;
      }
      if (change.field == AiChangedField.publishedAt) {
        final was = _decodeDate(change.beforeValue);
        publishedAt = was.publishedAt;
        reference = _rebuild(
          reference,
          AiChangedField.publishedAt,
          precision: was.precision,
        );
        dateRestored = true;
      } else {
        reference = _rebuild(reference, change.field);
      }
      referenceFields++;
    }

    if (reference != current.reference) {
      await _writer.setReference(itemId, reference);
    }
    if (dateRestored && publishedAt != current.publishedAt) {
      await _writer.setFieldFromText(
        itemId,
        EntryField.publishedAt,
        publishedAt == null
            ? null
            : '${publishedAt.millisecondsSinceEpoch ~/ 1000}',
      );
    }
    return AiRunTally(spaces: spaces, referenceFields: referenceFields);
  }

  /// Lo que completó cada una de [runIds] —el tema y los datos de la
  /// referencia—, contado de su historia: lo que se recordó al completarlo.
  Future<Map<String, AiRunTally>> created(Iterable<String> runIds) async {
    final byRun = <String, AiRunTally>{};
    for (final change in await _changesOf(runIds)) {
      byRun[change.aiRunId] =
          (byRun[change.aiRunId] ?? const AiRunTally()) + _one(change.field);
    }
    return byRun;
  }

  /// Lo que de cada una de [runIds] todavía es de la IA: lo que sigue con el
  /// valor que puso. Las pasadas deshechas no se cuentan: lo suyo ya se
  /// devolvió, y si hoy tiene el mismo valor es porque alguien lo volvió a
  /// poner.
  Future<Map<String, AiRunTally>> remaining(Iterable<String> runIds) async {
    final changes = await _changesOf(runIds);
    if (changes.isEmpty) return const {};

    final runs =
        await (_db.select(_db.aiRuns)..where(
              (r) =>
                  r.id.isIn(changes.map((c) => c.aiRunId).toSet()) &
                  r.undoneAt.isNull(),
            ))
            .get();
    final itemOfRun = {for (final run in runs) run.id: run.itemId};

    final currentByItem = <String, _Current>{};
    final byRun = <String, AiRunTally>{};
    for (final change in changes) {
      final itemId = itemOfRun[change.aiRunId];
      if (itemId == null) continue;
      final current = currentByItem[itemId] ??= await _currentOf(itemId);
      if (_encode(
            change.field,
            current.reference,
            current.publishedAt,
            spaceId: current.spaceId,
          ) !=
          change.afterValue) {
        continue;
      }
      byRun[change.aiRunId] =
          (byRun[change.aiRunId] ?? const AiRunTally()) + _one(change.field);
    }
    return byRun;
  }

  static AiRunTally _one(AiChangedField field) => field == AiChangedField.space
      ? const AiRunTally(spaces: 1)
      : const AiRunTally(referenceFields: 1);

  Future<void> _record(
    String runId,
    AiChangedField field,
    String? before,
    String after,
  ) => _db
      .into(_db.aiFieldChanges)
      .insert(
        AiFieldChangesCompanion.insert(
          id: _ids.next(),
          aiRunId: runId,
          field: field,
          beforeValue: Value(before),
          afterValue: after,
        ),
      );

  Future<List<AiFieldChangeRow>> _changesOf(Iterable<String> runIds) {
    final ids = runIds.toSet();
    if (ids.isEmpty) return Future.value(const []);
    return (_db.select(_db.aiFieldChanges)
          ..where((c) => c.aiRunId.isIn(ids))
          ..orderBy([(c) => OrderingTerm.asc(c.id)]))
        .get();
  }

  /// Si otra pasada de [itemId], que sigue en pie, ya completó algún dato de
  /// su referencia.
  Future<bool> _referenceCompletedBefore(
    String itemId, {
    required String exceptRun,
  }) async {
    final row = await _db
        .customSelect(
          '''
          SELECT 1 FROM ai_field_changes c
            JOIN ai_runs r ON r.id = c.ai_run_id
           WHERE r.item_id = ? AND r.id <> ? AND r.undone_at IS NULL
             AND c.field <> ?
           LIMIT 1''',
          variables: [
            Variable.withString(itemId),
            Variable.withString(exceptRun),
            Variable.withString(AiChangedField.space.name),
          ],
          readsFrom: {_db.aiFieldChanges, _db.aiRuns},
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<String?> _itemOf(String runId) async => (await (_db.select(
    _db.aiRuns,
  )..where((r) => r.id.equals(runId))).getSingleOrNull())?.itemId;

  Future<({bool missing, String? spaceId})> _spaceOf(String itemId) async {
    final row = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId))).getSingleOrNull();
    return (missing: row == null, spaceId: row?.spaceId);
  }

  Future<_Current> _currentOf(String itemId) async {
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(itemId))).getSingleOrNull();
    return _Current(
      spaceId: (await _spaceOf(itemId)).spaceId,
      reference: await ReferenceReader(_db).read(itemId),
      publishedAt: source?.publishedAt,
    );
  }
}

/// Cómo está hoy un elemento en lo que la IA puede completar.
class _Current {
  const _Current({
    required this.spaceId,
    required this.reference,
    required this.publishedAt,
  });

  final String? spaceId;
  final ReferenceData reference;
  final DateTime? publishedAt;
}

/// [current] con cada dato vacío completado con el de [found]. Las personas
/// van enteras o no van: mezclar dos elencos daría uno que nadie propuso.
ReferenceData _fillEmpty(ReferenceData current, ReferenceData found) =>
    ReferenceData(
      type: current.type ?? found.type,
      contributors: current.contributors.isEmpty
          ? found.contributors
          : current.contributors,
      containerTitle: _blank(current.containerTitle)
          ? found.containerTitle
          : current.containerTitle,
      publisher: _blank(current.publisher)
          ? found.publisher
          : current.publisher,
      publisherPlace: _blank(current.publisherPlace)
          ? found.publisherPlace
          : current.publisherPlace,
      edition: _blank(current.edition) ? found.edition : current.edition,
      volume: _blank(current.volume) ? found.volume : current.volume,
      issue: _blank(current.issue) ? found.issue : current.issue,
      pages: _blank(current.pages) ? found.pages : current.pages,
      isbn: _blank(current.isbn) ? found.isbn : current.isbn,
      issn: _blank(current.issn) ? found.issn : current.issn,
      doi: _blank(current.doi) ? found.doi : current.doi,
      // Lo que la lectura de un archivo no trae se conserva tal cual.
      accessedAt: current.accessedAt,
      citationKey: current.citationKey,
      publicationPrecision: current.publicationPrecision,
    );

bool _blank(String? text) => text == null || text.trim().isEmpty;

/// [reference] con la exactitud de la fecha [precision]: va con la fecha que
/// la IA completó.
ReferenceData _withPrecision(
  ReferenceData reference,
  PublicationPrecision? precision,
) => _rebuild(reference, AiChangedField.publishedAt, precision: precision);

/// [reference] con [field] vacío —o, en la fecha, con [precision]—. Hace
/// falta armarla de nuevo: en `copyWith`, un `null` es «dejalo como estaba».
ReferenceData _rebuild(
  ReferenceData reference,
  AiChangedField field, {
  PublicationPrecision? precision,
}) {
  String? keep(AiChangedField f, String? value) => field == f ? null : value;
  return ReferenceData(
    type: field == AiChangedField.referenceType ? null : reference.type,
    contributors: field == AiChangedField.contributors
        ? const []
        : reference.contributors,
    containerTitle: keep(
      AiChangedField.containerTitle,
      reference.containerTitle,
    ),
    publisher: keep(AiChangedField.publisher, reference.publisher),
    publisherPlace: keep(
      AiChangedField.publisherPlace,
      reference.publisherPlace,
    ),
    edition: keep(AiChangedField.edition, reference.edition),
    volume: keep(AiChangedField.volume, reference.volume),
    issue: keep(AiChangedField.issue, reference.issue),
    pages: keep(AiChangedField.pages, reference.pages),
    isbn: keep(AiChangedField.isbn, reference.isbn),
    issn: keep(AiChangedField.issn, reference.issn),
    doi: keep(AiChangedField.doi, reference.doi),
    accessedAt: reference.accessedAt,
    citationKey: reference.citationKey,
    publicationPrecision: field == AiChangedField.publishedAt
        ? precision
        : reference.publicationPrecision,
  );
}

/// El valor de [field] como texto, para compararlo con lo que puso la IA:
/// `null` si está vacío. Las personas, por su identidad en el vocabulario y
/// su rol, en orden —renombrar a una persona no la cambia—; la fecha, en
/// segundos y con su exactitud, que van juntas.
String? _encode(
  AiChangedField field,
  ReferenceData reference,
  DateTime? publishedAt, {
  String? spaceId,
}) {
  String? text(String? value) =>
      value == null || value.trim().isEmpty ? null : value;
  return switch (field) {
    AiChangedField.space => spaceId,
    AiChangedField.referenceType => reference.type?.name,
    AiChangedField.contributors =>
      reference.contributors.isEmpty
          ? null
          : jsonEncode([
              for (final c in reference.contributors)
                [c.role.name, c.personId ?? c.name.label],
            ]),
    AiChangedField.containerTitle => text(reference.containerTitle),
    AiChangedField.publisher => text(reference.publisher),
    AiChangedField.publisherPlace => text(reference.publisherPlace),
    AiChangedField.edition => text(reference.edition),
    AiChangedField.volume => text(reference.volume),
    AiChangedField.issue => text(reference.issue),
    AiChangedField.pages => text(reference.pages),
    AiChangedField.isbn => text(reference.isbn),
    AiChangedField.issn => text(reference.issn),
    AiChangedField.doi => text(reference.doi),
    AiChangedField.publishedAt =>
      publishedAt == null && reference.publicationPrecision == null
          ? null
          : '${_seconds(publishedAt)}'
                '|${reference.publicationPrecision?.name ?? ''}',
  };
}

/// [at] en segundos, como lo guarda drift; vacío si no hay.
String _seconds(DateTime? at) =>
    at == null ? '' : '${at.millisecondsSinceEpoch ~/ 1000}';

/// La fecha de antes, de como la guarda [_encode]: sin fecha, con la
/// exactitud que hubiera.
({DateTime? publishedAt, PublicationPrecision? precision}) _decodeDate(
  String? encoded,
) {
  if (encoded == null) return (publishedAt: null, precision: null);
  final [seconds, precision] = encoded.split('|');
  return (
    publishedAt: seconds.isEmpty
        ? null
        : DateTime.fromMillisecondsSinceEpoch(int.parse(seconds) * 1000),
    precision: PublicationPrecision.values.asNameMap()[precision],
  );
}
