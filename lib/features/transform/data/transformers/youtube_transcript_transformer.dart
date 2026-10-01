import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/core/util/transcript_timestamps.dart';
import 'package:sinapsis/core/util/youtube_url.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_checkpoints.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// Trae la transcripción de un video de YouTube, junto con su título y su
/// autor reales.
///
/// La transcripción es el reemplazo de DownSub, y sale mejor que integrarlo:
/// los subtítulos se piden sin clave de API y sin cuotas diarias, no hay que
/// abrir una pestaña ni pegar una dirección en otro sitio, y lo que baja
/// queda guardado con el enlace al video en vez de en un archivo suelto en
/// Descargas.
///
/// **Solo la transcripción** (F21, decisión B): unos KB, segundos para un
/// video de cualquier duración. El audio ya no se baja acá —antes el video
/// no quedaba listo hasta terminar de bajar el audio entero, cientos de MB
/// en uno de cuatro horas—: se baja solo si el usuario lo pide, desde el
/// detalle (`DownloadYouTubeAudioUseCase`).
class YouTubeTranscriptTransformer implements Transformer {
  const YouTubeTranscriptTransformer({
    required YouTubeClient client,
    required IdGenerator ids,
    required Clock clock,
    AudioTranscriber? transcriber,
    Future<Directory> Function()? temporaryDirectory,
    ProcessingCheckpoints? checkpoints,
  }) : _client = client,
       _ids = ids,
       _clock = clock,
       _transcriber = transcriber,
       _temporaryDirectory = temporaryDirectory,
       _checkpoints = checkpoints;

  final YouTubeClient _client;
  final IdGenerator _ids;
  final Clock _clock;

  /// Para un video SIN subtítulos: se baja su audio y se transcribe, como
  /// cualquier audio del teléfono (F22). Sin él —en la web, o en una
  /// prueba—, queda la descripción del video.
  final AudioTranscriber? _transcriber;
  final Future<Directory> Function()? _temporaryDirectory;
  final ProcessingCheckpoints? _checkpoints;

  /// Trabajo corto: los datos del video y sus subtítulos.
  @override
  Duration? get timeLimit => kShortTransformTimeLimit;

  @override
  bool canTransform(KnowledgeItem item) {
    if (item.source.kind != SourceKind.youtube) return false;

    final url = item.source.url;
    if (url == null) return false;
    if (YouTubeUrl.videoIdOf(Uri.parse(url)) == null) return false;

    // Ya tiene contenido: no se vuelve a bajar. Sin esta comprobación, cada
    // pasada de la cola pediría de nuevo lo mismo y duplicaría la
    // transcripción.
    return item.renditions.isEmpty;
  }

  @override
  Future<KnowledgeItem> transform(
    KnowledgeItem item, {
    TransformContext context = TransformContext.detached,
  }) async {
    final videoId = YouTubeUrl.videoIdOf(Uri.parse(item.source.url!))!;
    // Si el usuario eligió un idioma para este video, ese manda; si no, el
    // que se habla en él (F22).
    final data = await _client.fetchVideo(
      videoId,
      preferredLanguages: [?item.source.language],
    );
    final now = _clock();

    // Sin subtítulos de ninguna clase: lo dicho se saca del audio (F22).
    var renditions = _renditionsFor(item.id, data, now);
    var language = data.transcriptLanguage ?? item.source.language;
    if (data.transcript.isEmpty) {
      final spoken = await _transcribeAudio(videoId, item, context);
      if (spoken != null && spoken.trim().isNotEmpty) {
        renditions = [
          Rendition.text(
            id: _ids.next(),
            itemId: item.id,
            kind: RenditionKind.plainText,
            content: spoken,
            isPrimary: true,
            createdAt: now,
          ),
        ];
        language = item.source.language ?? defaultTranscriptionLanguage;
      }
    }

    return item.copyWith(
      // El título provisional era el identificador del video; ahora se sabe
      // cómo se llama de verdad.
      title: data.title,
      subtitle: data.authorName ?? item.subtitle,
      source: item.source.copyWith(
        authorName: data.authorName ?? item.source.authorName,
        authorUrl: data.authorChannelUrl ?? item.source.authorUrl,
        publishedAt: data.publishedAt ?? item.source.publishedAt,
        language: language,
      ),
      renditions: renditions,
    );
  }

  /// El audio del video [videoId], transcrito; `null` si no hay con qué
  /// transcribir (F22).
  ///
  /// Es trabajo largo: pasa al carril largo, baja el audio a un archivo
  /// temporal —directo a disco, el de un video de horas pesa cientos de
  /// MB— y lo transcribe por tramos, retomable como cualquier audio. El
  /// archivo bajado queda hasta terminar bien: si la app se cierra, al
  /// retomar no se vuelve a bajar. Después se borra: guardarlo es
  /// "Descargar el audio", que sigue siendo a pedido (F21, decisión B).
  Future<String?> _transcribeAudio(
    String videoId,
    KnowledgeItem item,
    TransformContext context,
  ) async {
    final transcriber = _transcriber;
    final temporaryDirectory = _temporaryDirectory;
    if (kIsWeb || transcriber == null || temporaryDirectory == null) {
      return null;
    }
    await context.enterLongLane();

    final safe = item.id.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
    final folder = await temporaryDirectory();
    // Marca de "audio bajado entero", con la ruta del archivo adentro.
    final marker = File(p.join(folder.path, 'youtube-$safe.bajado'));
    var audioPath = marker.existsSync() ? marker.readAsStringSync() : '';
    try {
      if (audioPath.isEmpty || !File(audioPath).existsSync()) {
        audioPath = await _downloadAudio(videoId, folder, safe, context);
        marker.writeAsStringSync(audioPath);
      }
      final checkpoints = _checkpoints;
      final text = await transcriber.transcribe(
        audioPath,
        language: item.source.language ?? defaultTranscriptionLanguage,
        session: TranscriptionSession(
          context: context,
          workKey: item.id,
          loadSegments: checkpoints == null
              ? null
              : () => checkpoints.load(
                  item.id,
                  ProcessingCheckpointKind.transcriptWindow,
                ),
          saveSegment: checkpoints == null
              ? null
              : (segment, text) => checkpoints.save(
                  item.id,
                  ProcessingCheckpointKind.transcriptWindow,
                  position: segment,
                  content: text,
                ),
        ),
      );
      _discard(marker, audioPath);
      return text;
    } on Object {
      // Interrumpido por algo que un reintento puede salvar: el audio bajado
      // se conserva. Abandonado —se borró el elemento—, no.
      if (context.isCancelled) _discard(marker, audioPath);
      rethrow;
    }
  }

  /// Baja el audio de [videoId] a [folder], directo a disco, avisando el
  /// avance. Devuelve la ruta.
  Future<String> _downloadAudio(
    String videoId,
    Directory folder,
    String safe,
    TransformContext context,
  ) async {
    final audio = await _client.openAudio(videoId);
    final file = File(
      p.join(folder.path, 'youtube-$safe.${audio.fileExtension}'),
    );
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in cancellableStream(
        audio.bytes,
        context.whenCancelled,
      )) {
        sink.add(chunk);
        received += chunk.length;
        final total = audio.totalBytes;
        if (total != null && total > 0) {
          context.reportProgress(received, total);
        }
      }
    } finally {
      await sink.close();
    }
    return file.path;
  }

  void _discard(File marker, String audioPath) {
    if (marker.existsSync()) marker.deleteSync();
    if (audioPath.isNotEmpty && File(audioPath).existsSync()) {
      File(audioPath).deleteSync();
    }
  }

  /// Qué se guarda como contenido.
  ///
  /// La transcripción si la hay. Si el video no tiene subtítulos de ninguna
  /// clase —pasa, y es común en videos caseros— se transcribe su audio (ver
  /// [_transcribeAudio]); esto queda para cuando no hay con qué: la
  /// descripción, que es contenido real, buscable, y mejor que dejar el
  /// elemento vacío.
  List<Rendition> _renditionsFor(
    String itemId,
    YouTubeVideoData data,
    DateTime now,
  ) {
    if (data.transcript.isNotEmpty) {
      return [
        Rendition.text(
          id: _ids.next(),
          itemId: itemId,
          // Lo dicho, tal cual, con su minuto: no es Markdown (F22).
          kind: RenditionKind.plainText,
          content: formatTranscript(data.transcript),
          isPrimary: true,
          createdAt: now,
        ),
      ];
    }

    final description = data.description?.trim() ?? '';
    if (description.isEmpty) return const [];

    return [
      Rendition.text(
        id: _ids.next(),
        itemId: itemId,
        kind: RenditionKind.plainText,
        content: description,
        isPrimary: true,
        createdAt: now,
      ),
    ];
  }
}

/// Arma el texto de la transcripción con sus marcas de tiempo.
///
/// El momento de cada línea es lo que separa una transcripción de un bloque
/// de texto: encontrar una frase en la búsqueda y saber en qué minuto del
/// video estaba es la diferencia entre volver al punto exacto y tener que
/// mirar una hora de video otra vez.
///
/// Se expone para poder probarlo por su cuenta: el formato es lo que el
/// usuario termina leyendo.
String formatTranscript(List<TranscriptLine> lines) {
  return lines
      .map((line) => '[${formatTimestamp(line.offset)}] ${line.text}')
      .join('\n');
}
