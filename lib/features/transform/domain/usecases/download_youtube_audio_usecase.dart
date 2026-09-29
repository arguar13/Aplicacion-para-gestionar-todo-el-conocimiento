import 'dart:async';

import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/youtube_url.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Baja el audio de un video de YouTube a pedido del usuario, para
/// escucharlo sin conexión (F21, decisión B).
///
/// Antes se bajaba solo, al procesar el video, y el video no quedaba listo
/// hasta terminar: cientos de MB en uno de cuatro horas. Ahora el video
/// queda listo con su transcripción en segundos, y el audio es un pedido
/// aparte: por partes, directo a disco —nunca entero en memoria—, con
/// avance y cancelable.
///
/// Lanza si no puede: el motivo lo traduce quien lo llama, con el mismo
/// criterio que un procesamiento fallido (`processingFailureReasonFor`).
class DownloadYouTubeAudioUseCase {
  const DownloadYouTubeAudioUseCase({
    required YouTubeClient client,
    required FileStore files,
    required LibraryRepository repository,
    required Clock clock,
  }) : _client = client,
       _files = files,
       _repository = repository,
       _clock = clock;

  final YouTubeClient _client;
  final FileStore _files;
  final LibraryRepository _repository;
  final Clock _clock;

  /// Baja el audio de [itemId] y lo deja como su archivo original.
  ///
  /// [onProgress] recibe cuánto se bajó y cuánto pesa en total, si YouTube
  /// lo informa. Si [cancellation] pide abandonar, la descarga se corta en el
  /// acto, no queda ningún archivo a medias y se lanza
  /// [ProcessingCancelledException].
  Future<KnowledgeItem> call(
    String itemId, {
    void Function(int received, int? total)? onProgress,
    CancellationSignal? cancellation,
  }) async {
    final item = (await _repository.findById(itemId)).getRight().toNullable();
    if (item == null) throw const ProcessingCancelledException();

    final url = item.source.url;
    final videoId = url == null ? null : YouTubeUrl.videoIdOf(Uri.parse(url));
    if (item.source.kind != SourceKind.youtube || videoId == null) {
      throw ArgumentError.value(itemId, 'itemId', 'no es un video de YouTube');
    }

    cancellation?.throwIfCancelled();
    final audio = await _client.openAudio(videoId);

    var received = 0;
    final counted = audio.bytes.map((chunk) {
      received += chunk.length;
      onProgress?.call(received, audio.totalBytes);
      return chunk;
    });

    final path = await _files.saveStream(
      bytes: _cancellable(counted, cancellation),
      suggestedName: '${item.title}.${audio.fileExtension}',
      id: item.source.id,
    );

    // Sobre la versión actual, no la que se leyó al empezar: la descarga
    // pudo tardar minutos, y mientras tanto el usuario pudo cambiarle el
    // título, las etiquetas... o borrarlo.
    final saved = await _repository.runInTransaction(() async {
      final current = (await _repository.findById(
        itemId,
      )).getRight().toNullable();
      if (current == null) return null;
      return (await _repository.save(
        current.copyWith(
          source: current.source.copyWith(originalFilePath: path),
          updatedAt: _clock(),
        ),
      )).getRight().toNullable();
    });

    if (saved == null) {
      // Se borró mientras se bajaba, o no se pudo guardar: el archivo no
      // tiene de quién ser.
      await _files.delete(path);
      throw const ProcessingCancelledException();
    }
    return saved;
  }

  /// [source], salvo que [cancellation] pida abandonar: ver
  /// [cancellableStream].
  Stream<List<int>> _cancellable(
    Stream<List<int>> source,
    CancellationSignal? cancellation,
  ) => cancellation == null
      ? source
      : cancellableStream(source, cancellation.whenCancelled);
}
