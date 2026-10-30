import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/layout_only_pages.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_tidy_providers.dart';
import 'package:sinapsis/features/transform/domain/entities/stored_video_text.dart';
import 'package:sinapsis/features/transform/domain/repositories/video_text_repository.dart';
import 'package:sinapsis/features/transform/domain/usecases/reextraction.dart';

/// Lleva al documento procesado el texto nuevo de su fuente, cuando se lo
/// cambió desde ese documento (F45, paso 4): al volver a extraerlo —desde «El
/// texto de la fuente» o desde la oferta de un video con el texto en otro
/// idioma— o al quitarle las marcas de tiempo.
///
/// El texto de un documento procesado es una copia del de su fuente, hecha al
/// triarla (F41): cambiar la fuente no lo cambia solo —de la Biblioteca a
/// Procesado nada pasa sin pedirlo—. Pedido desde el documento, sí: la
/// sección «Texto» se actualiza (`SectionEdit.update`) en ese documento y en
/// ningún otro, en cualquier fuente que lo ofrezca.
///
/// **Lo que editó la persona no se pierde nunca.** «Actualizar» deja como
/// está toda página editada. Pero una página que la IA ordenó (F45, decisión
/// B) también cuenta como editada, y con eso el texto nuevo no entraba nunca
/// en un documento ordenado. Por eso, **antes** de cambiar la fuente —cuando
/// todavía está su texto viejo para comparar— [request] anota qué páginas se
/// editaron sin cambiar ni una palabra (`layoutOnlyPages`): lo que hace la IA
/// al ordenar. Al llegar el texto nuevo ([afterProcessed]), esas páginas, si
/// nadie las tocó desde entonces, vuelven a ser de la fuente y se renuevan; y
/// el documento se vuelve a ordenar con la IA, sobre el texto nuevo. Una página
/// cuyas palabras cambió la persona se queda como está.
///
/// **Solo lo pedido**: lo que la cola procesa sin un pedido de acá no toca
/// ningún documento. Lo pedido queda guardado ([kProcessedTextRefreshKey]):
/// una transcripción de una hora puede terminar con la app cerrada y
/// retomada.
///
/// **El idioma, en un video**: si el texto nuevo de un video llegó otra vez
/// en otro idioma que el que se habla —no hubo con qué transcribir—, no se
/// trae, y el documento sigue ofreciendo volver a extraer (`checkVideoText`).
class ProcessedTextRefresh {
  ProcessedTextRefresh({
    required SharedPreferences preferences,
    required Future<Either<Failure, Object?>> Function(String sourceId) update,
    Future<List<ProcessedPart>> Function(String documentId)? textPages,
    Future<String?> Function(String sourceId)? sourceText,
    Future<void> Function(ProcessedPart page)? release,
    Future<void> Function(String documentId)? retidy,
    ProcessedWorker worker = runProcessedWork,
    void Function(String message)? log,
  }) : _preferences = preferences,
       _update = update,
       _textPages = textPages,
       _sourceText = sourceText,
       _release = release,
       _retidy = retidy,
       _worker = worker,
       _log = log;

  final SharedPreferences _preferences;
  final Future<Either<Failure, Object?>> Function(String sourceId) _update;

  /// Las páginas del texto de un documento, para anotar y renovar.
  final Future<List<ProcessedPart>> Function(String documentId)? _textPages;

  /// El texto de ahora de una fuente, para comparar.
  final Future<String?> Function(String sourceId)? _sourceText;

  /// Devuelve una página a la fuente: sin la marca de editada.
  final Future<void> Function(ProcessedPart page)? _release;

  /// Vuelve a pedir que la IA ordene el texto de un documento.
  final Future<void> Function(String documentId)? _retidy;

  final ProcessedWorker _worker;
  final void Function(String message)? _log;

  /// Las fuentes cuyo texto nuevo espera ir a su documento procesado.
  Set<String> get pending => _read().keys.toSet();

  /// Pide que el texto nuevo de [sourceId], cuando llegue, vaya a su
  /// documento. Se llama **antes** de cambiar la fuente: anota qué páginas
  /// del documento están ordenadas y no editadas, contra el texto de ahora.
  Future<void> request(String sourceId) async {
    final layoutOnly = await _layoutOnly(sourceId);
    await _write({..._read(), sourceId: layoutOnly});
  }

  /// Olvida lo pedido para [sourceId]: el cambio de la fuente no se hizo.
  Future<void> cancel(String sourceId) async {
    final waiting = _read();
    if (waiting.remove(sourceId) != null) await _write(waiting);
  }

  /// Trae ya el texto de [sourceId] a su documento, sin renovar ninguna
  /// página editada: lo que pide la oferta de un video cuya fuente ya tiene su
  /// texto bien, y no hay texto viejo con qué comparar. Devuelve si se pudo.
  Future<bool> updateNow(String sourceId) => _apply(sourceId, const {});

  /// Lo que hace la cola después de procesar [item] —y la hoja, después de
  /// quitarle las marcas de tiempo—: si se pidió traer su texto nuevo a
  /// Procesado, lo trae. El pedido se cumple igual si el texto nuevo es de un
  /// video y llegó en otro idioma: no se trae.
  Future<void> afterProcessed(KnowledgeItem item) async {
    final waiting = _read();
    final layoutOnly = waiting.remove(item.id);
    if (layoutOnly == null) return;
    await _write(waiting);
    final text = primaryTextOf(item)?.content;
    if (text == null || text.trim().isEmpty) return;
    if (_isVideo(item.source.kind)) {
      final arrived = StoredVideoText(
        sourceId: item.id,
        title: item.title,
        language: item.source.language,
        head: text.length > kStoredVideoTextHead
            ? text.substring(0, kStoredVideoTextHead)
            : text,
      );
      if (foreignVideoTextOf(arrived) != null) return;
    }
    await _apply(item.id, layoutOnly);
  }

  /// Las páginas solo ordenadas de [layoutOnly] que nadie tocó vuelven a la
  /// fuente; después, «Actualizar»; y si alguna volvió, la IA ordena de nuevo.
  Future<bool> _apply(String sourceId, Map<String, String> layoutOnly) async {
    final documentId = processedDocumentIdFor(sourceId);
    var released = 0;
    if (layoutOnly.isNotEmpty && _textPages != null && _release != null) {
      for (final page in await _textPages(documentId)) {
        final known = layoutOnly[page.id];
        // Cambió desde que se anotó: la persona la editó, y es suya.
        if (known == null || page.isPristineCopy) continue;
        if (pageFingerprint(page.content) != known) continue;
        await _release(page);
        released++;
      }
    }
    final result = await _update(sourceId);
    if (result.getLeft().toNullable() case final failure?) {
      _log?.call('No se pudo traer el texto nuevo de $sourceId: $failure');
      return false;
    }
    if (released > 0) await _retidy?.call(documentId);
    return true;
  }

  Future<Map<String, String>> _layoutOnly(String sourceId) async {
    final textPages = _textPages;
    final sourceText = _sourceText;
    if (textPages == null || sourceText == null) return const {};
    final pages = editedCopiedPages(
      await textPages(processedDocumentIdFor(sourceId)),
    );
    if (pages.isEmpty) return const {};
    final source = await sourceText(sourceId);
    if (source == null || source.isEmpty) return const {};
    return _worker(layoutOnlyPages, (
      source: source,
      pages: pages,
    ), size: source.length);
  }

  Map<String, Map<String, String>> _read() {
    final raw = _preferences.getString(kProcessedTextRefreshKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final MapEntry(:key, :value) in decoded.entries)
          key: {
            for (final MapEntry(key: page, :value) in (value as Map).entries)
              '$page': '$value',
          },
      };
      // Algo que no se puede leer —una versión de prueba lo guardó de otra
      // forma— no se cumple: no se toca ningún documento.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, Map<String, String>> waiting) =>
      waiting.isEmpty
      ? _preferences.remove(kProcessedTextRefreshKey)
      : _preferences.setString(kProcessedTextRefreshKey, jsonEncode(waiting));
}

/// Si el texto de una fuente de [kind] es el de un video: lo único cuyo
/// idioma se compara con el que se habla (`checkVideoText`).
bool _isVideo(SourceKind kind) =>
    kind == SourceKind.youtube || kind == SourceKind.video;

/// Dónde se guarda lo pedido a [ProcessedTextRefresh]: por fuente, las
/// páginas solo ordenadas con la huella de su texto.
const kProcessedTextRefreshKey = 'processed_text_follow';

final processedTextRefreshProvider = Provider<ProcessedTextRefresh>(
  (ref) => ProcessedTextRefresh(
    preferences: ref.watch(sharedPreferencesProvider),
    update: (sourceId) => ref.read(triageIntoProcessedProvider).retriage(
      sourceId,
      {ProcessedSection.text: SectionEdit.update()},
    ),
    textPages: (documentId) async {
      final parts = await ref
          .read(processedRepositoryProvider)
          .partsOf(documentId, sections: {ProcessedSection.text});
      return parts.getOrElse((_) => const []);
    },
    sourceText: (sourceId) async {
      final found = await ref
          .read(libraryRepositoryProvider)
          .findById(sourceId);
      final item = found.getRight().toNullable();
      return item == null ? null : primaryTextOf(item)?.content;
    },
    release: (page) async {
      await ref
          .read(processedRepositoryProvider)
          .restorePart(page.copyWith(edited: false));
    },
    retidy: (documentId) =>
        ref.read(processedTidyQueueProvider).enqueue(documentId),
    log: ref.read(appLoggerProvider).warning,
  ),
);
