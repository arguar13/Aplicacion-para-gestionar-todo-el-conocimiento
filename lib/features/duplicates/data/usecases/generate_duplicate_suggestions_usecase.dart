import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/domain/services/dedup_fingerprint.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/duplicates/domain/services/duplicate_candidate_selector.dart';
import 'package:sinapsis/features/duplicates/domain/services/duplicate_suggestion_generator.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

/// [DuplicateSuggestionGenerator] — F7, deduplicación.
///
/// Vive en `data/`, no en `domain/`: orquesta `AppDatabase` directo para
/// persistir el fingerprint —mismo criterio que
/// `GenerateRelationSuggestionsUseCase` de F5—.
class GenerateDuplicateSuggestionsUseCase
    implements DuplicateSuggestionGenerator {
  const GenerateDuplicateSuggestionsUseCase({
    required AppDatabase database,
    required DuplicateCandidateSelector selector,
    required SuggestionRepository suggestions,
    required TelemetryService telemetry,
  }) : _db = database,
       _selector = selector,
       _suggestions = suggestions,
       _telemetry = telemetry;

  final AppDatabase _db;
  final DuplicateCandidateSelector _selector;
  final SuggestionRepository _suggestions;
  final TelemetryService _telemetry;

  @override
  Future<void> generate(KnowledgeItem item) async {
    try {
      await _persistFingerprint(item);

      final candidates = await _selector.selectCandidates(seedItemId: item.id);
      if (candidates.isEmpty) return;

      final candidate = candidates.first;
      final alreadyPending = await _hasPendingDuplicateSuggestion(
        itemId: item.id,
        otherItemId: candidate.itemId,
      );
      if (alreadyPending) return;

      // Este generador corre fire-and-forget (D7), así que puede seguir
      // trabajando después de que `item` ya haya dejado de existir —el
      // caso real: el diálogo de duplicado (C6) fusiona el elemento
      // recién guardado con `candidate` casi enseguida, borrándolo—. Sin
      // este chequeo, la inserción de abajo rompe una restricción de
      // llave foránea: no es un error de la app, es una carrera
      // benigna, así que se resuelve en silencio, no con telemetría.
      //
      // Y sigue vivo: uno que fue a la papelera en el medio tampoco se propone.
      final stillExist =
          await (_db.select(_db.knowledgeEntries)..where(
                (e) => e.id.isIn([item.id, candidate.itemId]) & e.isActive,
              ))
              .get();
      if (stillExist.length != 2) return;

      await _suggestions.createDuplicateSuggestion(
        targetItemId: item.id,
        duplicateItemId: candidate.itemId,
        duplicateItemTitle: candidate.title,
        matchKind: candidate.matchKind,
      );
      // Nunca deja escapar un error: una sugerencia que no se pudo generar
      // degrada a "no se generó nada", no a un error visible en ningún
      // lado.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'GenerateDuplicateSuggestionsUseCase.generate',
      );
    }
  }

  /// Sobre `KnowledgeSources`/`KnowledgeNotes`, según de cuál de las dos
  /// se trate (D8) — el mismo criterio de clasificación que usa todo el
  /// resto de la app, `itemKindFor`.
  Future<void> _persistFingerprint(KnowledgeItem item) async {
    final normalized = normalizeForDedup(item.searchableText);
    if (normalized.isEmpty) return;

    final dedupHash = contentHashOf(normalized);
    final simhash = simhashOf(normalized);

    if (itemKindFor(item.source.kind) == ItemKind.note) {
      await (_db.update(
        _db.knowledgeNotes,
      )..where((n) => n.itemId.equals(item.id))).write(
        KnowledgeNotesCompanion(
          dedupHash: Value(dedupHash),
          simhash: Value(simhash),
        ),
      );
    } else {
      await (_db.update(
        _db.knowledgeSources,
      )..where((s) => s.itemId.equals(item.id))).write(
        KnowledgeSourcesCompanion(
          dedupHash: Value(dedupHash),
          simhash: Value(simhash),
        ),
      );
    }
  }

  /// Ya hay una sugerencia `pending` para exactamente este par, en
  /// cualquiera de las dos direcciones —sin importar quién haya quedado
  /// como `targetItemId` la primera vez—: no tiene sentido ofrecer
  /// "fusionar con X" dos veces. Hace falta mirar las dos direcciones
  /// porque un elemento puede volver a pasar por acá —una nota editada
  /// de nuevo, D7— después de que el otro ya generó la sugerencia.
  ///
  /// Consulta directa contra `AppDatabase`, no
  /// `SuggestionRepository.watchPendingSuggestions`: ese método arma un
  /// stream con `watchQuery`, pensado para que lo mire un widget —leerlo
  /// una sola vez con `.first` desde acá, fuera del árbol de widgets,
  /// mientras este mismo generador corre en paralelo con otra operación
  /// que también toca la tabla (la fusión que `CaptureScreen`/
  /// `BlockEditorScreen` disparan justo después de guardar, C6), es el
  /// mismo patrón que ya colgó un test en F6.
  Future<bool> _hasPendingDuplicateSuggestion({
    required String itemId,
    required String otherItemId,
  }) async {
    final rows =
        await (_db.select(_db.suggestions)..where(
              (s) =>
                  s.status.equalsValue(SuggestionStatus.pending) &
                  (s.targetItemId.equals(itemId) |
                      s.targetItemId.equals(otherItemId)),
            ))
            .get();

    for (final row in rows) {
      if (row.kind != SuggestionKind.duplicate) continue;
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      final duplicateItemId = payload['duplicateItemId'] as String;
      if (row.targetItemId == itemId && duplicateItemId == otherItemId) {
        return true;
      }
      if (row.targetItemId == otherItemId && duplicateItemId == itemId) {
        return true;
      }
    }
    return false;
  }
}
