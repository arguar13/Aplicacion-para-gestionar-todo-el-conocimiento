import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/transform/domain/entities/stored_video_text.dart';
import 'package:sinapsis/features/transform/domain/repositories/video_text_repository.dart';
import 'package:sinapsis/features/transform/domain/usecases/reextraction.dart';

/// Lleva a Procesado el texto nuevo de un video que se volvió a extraer desde
/// ahí (F45, paso 4).
///
/// El texto de un documento procesado es una copia del de su fuente, hecha al
/// triarla (F41): volver a extraer la fuente no lo cambia —de la Biblioteca a
/// Procesado nada pasa solo—. Por eso un video con el texto en árabe seguía
/// en árabe en Procesado aunque se hubiera vuelto a extraer en la Biblioteca.
/// «Volver a extraer» desde Procesado pide las dos cosas: la fuente vuelve a
/// la cola y, cuando su texto nuevo llega en su idioma, la sección «Texto» del
/// documento se actualiza (`SectionEdit.update`, que conserva lo editado a
/// mano).
///
/// Lo pedido queda guardado ([kProcessedTextRefreshKey]): una transcripción
/// de una hora puede terminar con la app cerrada y retomada; al terminar, la
/// cola avisa ([afterProcessed]) y se actualiza igual.
class ProcessedTextRefresh {
  ProcessedTextRefresh({
    required SharedPreferences preferences,
    required Future<Either<Failure, Object?>> Function(String sourceId) update,
    void Function(String message)? log,
  }) : _preferences = preferences,
       _update = update,
       _log = log;

  final SharedPreferences _preferences;
  final Future<Either<Failure, Object?>> Function(String sourceId) _update;
  final void Function(String message)? _log;

  /// Las fuentes cuyo texto nuevo espera ir a su documento procesado.
  Set<String> get pending =>
      (_preferences.getStringList(kProcessedTextRefreshKey) ?? const [])
          .toSet();

  /// Pide que el texto nuevo de [sourceId], cuando llegue, vaya a su
  /// documento.
  Future<void> request(String sourceId) => _save({...pending, sourceId});

  /// Trae ya el texto de [sourceId] a su documento: su fuente ya lo tiene en
  /// su idioma. Devuelve si se pudo.
  Future<bool> updateNow(String sourceId) async {
    final result = await _update(sourceId);
    return result.match((failure) {
      _log?.call('No se pudo traer el texto nuevo de $sourceId: $failure');
      return false;
    }, (_) => true);
  }

  /// Lo que hace la cola después de procesar [item]: si se pidió traer su
  /// texto nuevo a Procesado y llegó en su idioma, lo trae. Si llegó en otro
  /// idioma otra vez —no hubo con qué transcribir—, no lo trae: el documento
  /// sigue ofreciendo volver a extraer. En los dos casos el pedido se cumple.
  Future<void> afterProcessed(KnowledgeItem item) async {
    final waiting = pending;
    if (!waiting.remove(item.id)) return;
    await _save(waiting);
    final text = primaryTextOf(item)?.content;
    if (text == null || text.trim().isEmpty) return;
    final arrived = StoredVideoText(
      sourceId: item.id,
      title: item.title,
      language: item.source.language,
      head: text.length > kStoredVideoTextHead
          ? text.substring(0, kStoredVideoTextHead)
          : text,
    );
    if (foreignVideoTextOf(arrived) != null) return;
    await updateNow(item.id);
  }

  Future<void> _save(Set<String> ids) => ids.isEmpty
      ? _preferences.remove(kProcessedTextRefreshKey)
      : _preferences.setStringList(kProcessedTextRefreshKey, ids.toList());
}

/// Dónde se guarda lo pedido a [ProcessedTextRefresh].
const kProcessedTextRefreshKey = 'processed_text_refresh';

final processedTextRefreshProvider = Provider<ProcessedTextRefresh>(
  (ref) => ProcessedTextRefresh(
    preferences: ref.watch(sharedPreferencesProvider),
    update: (sourceId) => ref.read(triageIntoProcessedProvider).retriage(
      sourceId,
      {ProcessedSection.text: SectionEdit.update()},
    ),
    log: ref.read(appLoggerProvider).warning,
  ),
);
