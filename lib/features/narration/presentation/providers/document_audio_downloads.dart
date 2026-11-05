import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/narration/domain/audio/document_audio.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/providers/document_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/speech_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// En qué está la descarga del audio de un documento.
enum DocumentAudioJobPhase {
  /// Espera a que termine la de otro documento: se generan de a una.
  waiting,

  /// Se está generando.
  running,

  /// No se pudo: [DocumentAudioJob.failure] dice por qué. Lo hecho quedó
  /// para el próximo intento.
  failed,
}

/// La descarga del audio de un documento, mientras dura (F47, paso 5).
@immutable
class DocumentAudioJob {
  const DocumentAudioJob({
    required this.document,
    required this.phase,
    this.done = 0,
    this.total = 0,
    this.failure,
  });

  /// Lo que se descarga, como estaba al pedirlo.
  final ReadableDocument document;
  final DocumentAudioJobPhase phase;

  /// Cuántos pasos van de [total]: un tramo cada uno, y el armado al final.
  final int done;
  final int total;

  final SpeechAudioException? failure;

  /// Cuánto va, de 0 a 1; `null` si todavía no se sabe.
  double? get fraction => total <= 0 ? null : (done / total).clamp(0, 1);

  /// Cuánto va, en por ciento.
  int get percent => ((fraction ?? 0) * 100).floor();

  DocumentAudioJob copyWith({
    DocumentAudioJobPhase? phase,
    int? done,
    int? total,
    SpeechAudioException? failure,
  }) => DocumentAudioJob(
    document: document,
    phase: phase ?? this.phase,
    done: done ?? this.done,
    total: total ?? this.total,
    failure: failure ?? this.failure,
  );
}

/// Lo que mantiene viva la app mientras se genera un audio (F21): el
/// servicio en primer plano de Android, con «Sinapsis está generando el
/// audio de un documento» y su avance. Las pruebas lo cambian.
final documentAudioKeeperProvider = Provider<LongWorkKeeper>(
  (ref) => ref
      .watch(longWorkCoordinatorProvider)
      .keeperFor(LongWorkOwner.speechAudio),
);

/// **Descargar el audio de un documento** (F47, paso 5, punto 6 del plan):
/// lo genera en el teléfono la pieza común (`SpeechAudioRenderer`) con el
/// plan del documento ([DocumentAudioPlan]: un tramo por pedazo, con la voz
/// de su idioma y su pausa), lo guarda en la bóveda —nunca en la nube,
/// decisión F— y suelta el trabajo (`discard`).
///
/// - **De a una**: un audio por vez, en el orden en que se pidieron; los
///   demás esperan ([DocumentAudioJobPhase.waiting]). El motor sin conexión
///   es uno solo, y dos a la vez se pelearían por él.
/// - **Con su avance**, aquí ([DocumentAudioJob]) y en la notificación del
///   servicio en primer plano, que mantiene viva la app si se sale de ella.
/// - **Cancelable** ([cancel]), y **retomable**: el trabajo de la pieza común
///   es `doc-<clave>` ([documentAudioWorkKey]), el mismo en cada intento,
///   así que lo ya generado de uno cortado —se canceló, se cerró la app, faltó
///   una voz— no se vuelve a generar.
/// - **Lo que no se puede** —una voz que falta, un motor, el disco— queda
///   como [DocumentAudioJobPhase.failed], con su porqué, hasta que se
///   reintente o se descarte ([dismiss]).
///
/// El costo de una voz de la nube se pregunta antes de pedirlo, en la
/// pantalla (`speechAudioApprovalProvider`): acá ya está aprobado.
class DocumentAudioDownloads extends Notifier<Map<String, DocumentAudioJob>> {
  final _signals = <String, CancellationSignal>{};
  final _pending = <String, Future<DocumentAudio?>>{};

  /// La última descarga pedida: la siguiente espera a que termine.
  Future<void> _tail = Future.value();

  @override
  Map<String, DocumentAudioJob> build() => const {};

  /// Genera y guarda el audio de [document] con [plan]. Devuelve su ficha, o
  /// `null` si se canceló; lanza [SpeechAudioException] si no se pudo. Si ya
  /// se estaba descargando, es esa misma descarga.
  Future<DocumentAudio?> download(
    ReadableDocument document,
    DocumentAudioPlan plan,
  ) {
    final id = document.id;
    final pending = _pending[id];
    if (pending != null) return pending;
    final signal = CancellationSignal();
    _signals[id] = signal;
    _set(
      id,
      DocumentAudioJob(
        document: document,
        phase: DocumentAudioJobPhase.waiting,
      ),
    );
    final previous = _tail;
    final run = () async {
      await previous;
      return _run(document, plan, signal);
    }();
    _pending[id] = run;
    // La siguiente espera a esta, haya salido como haya salido.
    _tail = run.then<void>((_) {}, onError: (Object _) {})..ignore();
    return run;
  }

  /// Lo que se generaría hoy para el audio de [document]: un tramo por
  /// pedazo, con la voz con que el lector lo diría ahora (decisión L). Con
  /// esto se pide la descarga y se sabe si la descargada quedó vieja.
  DocumentAudioPlan planOf(ReadableDocument document) {
    final segments = document.segments;
    return DocumentAudioPlan.of(
      segments,
      ref.read(readAloudControllerProvider.notifier).voicesFor(segments),
      fallbackLocale: ref.read(speechFallbackLocaleProvider),
    );
  }

  /// Corta la descarga de [documentId]: lo ya generado queda para seguir
  /// después.
  void cancel(String documentId) => _signals[documentId]?.cancel();

  /// Saca la descarga fallida de [documentId].
  void dismiss(String documentId) {
    if (state[documentId]?.phase != DocumentAudioJobPhase.failed) return;
    _remove(documentId);
  }

  Future<DocumentAudio?> _run(
    ReadableDocument document,
    DocumentAudioPlan plan,
    CancellationSignal signal,
  ) async {
    final id = document.id;
    final workKey = documentAudioWorkKey(id);
    final renderer = ref.read(speechAudioRendererProvider);
    final keeper = ref.read(documentAudioKeeperProvider);
    try {
      signal.throwIfCancelled();
      _set(
        id,
        DocumentAudioJob(
          document: document,
          phase: DocumentAudioJobPhase.running,
        ),
      );
      final result = await renderer.render(
        SpeechAudioRequest(workKey: workKey, pieces: plan.pieces),
        cancellation: signal,
        onProgress: (done, total) {
          final job = state[id];
          if (job != null) _set(id, job.copyWith(done: done, total: total));
          keeper.working(
            done: done,
            total: total,
            kind: LongWorkKind.mediaProcessing,
          );
        },
      );
      signal.throwIfCancelled();
      final DocumentAudio audio;
      try {
        audio = await ref
            .read(documentAudioStoreProvider)
            .save(
              documentId: id,
              title: document.title,
              plan: plan,
              result: result,
              bytes: File(result.path).openRead(),
              now: ref.read(clockProvider)(),
            );
      } on Exception catch (e) {
        // El disco, al copiarlo a la bóveda: lo generado queda en el trabajo
        // para el próximo intento.
        throw SpeechAudioException(SpeechAudioFailure.file, detail: '$e');
      }
      // Ya está en la bóveda: lo del trabajo sobra. Si no se pudo borrar, la
      // pieza común lo barre sola a las dos semanas.
      try {
        await renderer.discard(workKey);
      } on FileSystemException {
        // Ver arriba.
      }
      _remove(id);
      ref.invalidate(documentAudioProvider(id));
      return audio;
    } on ProcessingCancelledException {
      _remove(id);
      return null;
    } on SpeechAudioException catch (e) {
      final job = state[id];
      _set(
        id,
        (job ??
                DocumentAudioJob(
                  document: document,
                  phase: DocumentAudioJobPhase.failed,
                ))
            .copyWith(phase: DocumentAudioJobPhase.failed, failure: e),
      );
      rethrow;
    } finally {
      keeper.idle();
      _signals.remove(id);
      // La descarga ya terminó: quien la esperaba tiene su resultado.
      unawaited(_pending.remove(id));
      ref.invalidate(documentAudioResumableProvider(id));
    }
  }

  void _set(String id, DocumentAudioJob job) => state = {...state, id: job};

  void _remove(String id) {
    if (!state.containsKey(id)) return;
    state = {...state}..remove(id);
  }
}

/// Las descargas de audio en curso, por el id del documento. Una sola para
/// toda la app: sigue aunque se cierre la pantalla que la pidió.
final documentAudioDownloadsProvider =
    NotifierProvider<DocumentAudioDownloads, Map<String, DocumentAudioJob>>(
      DocumentAudioDownloads.new,
    );
