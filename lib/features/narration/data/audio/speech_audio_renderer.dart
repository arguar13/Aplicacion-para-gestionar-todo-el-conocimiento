import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/audio/speech_audio_encoder.dart';
import 'package:sinapsis/features/narration/data/audio/speech_wav.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Arma un audio en un isolate aparte: lo de fábrica es `Isolate.run`.
typedef SpeechAssembler =
    Future<AssembledSpeech> Function(AssembleSpeechJob job);

/// **La pieza común para generar audio en el teléfono** (F47, pasos 5 y 6):
/// de una lista de tramos `{texto, voz, pausa}` a un solo archivo.
///
/// - **Tramo por tramo**, cada uno con quien sabe hacer su voz
///   ([SpeechVoiceRenderer]: las sin conexión, las del teléfono y, en el
///   paso 4, las de la nube). Cada tramo queda en su WAV en la carpeta del
///   trabajo ([SpeechAudioRequest.workKey]).
/// - **Retomable**: el WAV de un tramo se nombra por su texto, su voz y la
///   versión de la voz, y se escribe aparte y se renombra al terminar. Si la
///   app se cierra a mitad —o se cancela—, el próximo intento con la misma
///   clave encuentra lo hecho y no lo rehace; un tramo que cambió de texto o
///   de voz se vuelve a generar y los demás no.
/// - **Antes de generar nada**, se fija que estén todas las voces que faltan
///   usar: no se generan cien tramos para fallar en el ciento uno.
/// - **Cualquier formato de tramo**: un motor puede dejar WAV (las sin
///   conexión, las del teléfono) u otra cosa —el MP3 de una voz de la nube,
///   paso 4—; lo que no es WAV pasa por [SpeechClipDecoder] antes de armar.
/// - **El armado** ([assembleSpeechWav]) corre en otro isolate: recorta el
///   silencio de los bordes de cada tramo, lo lleva a 24 kHz mono y pone
///   exactamente la pausa pedida. Después se comprime a M4A
///   ([SpeechAudioEncoder]); donde no hay con qué, queda el WAV.
/// - **Sin bloquear la interfaz**: los motores trabajan en su isolate o en
///   el sistema, y acá solo se espera.
/// - **El avance**: `onProgress(hechos, total)`, con un paso más al final
///   para el armado.
///
/// Quien pide copia el archivo a donde va (la bóveda) y llama a [discard]:
/// la carpeta del trabajo no es la bóveda, no viaja en la copia y se borra.
/// Las carpetas de trabajos abandonados —una creación que se borró a mitad—
/// se barren solas pasado [staleAfter].
class SpeechAudioRenderer {
  SpeechAudioRenderer({
    required List<SpeechVoiceRenderer> Function() voices,
    required Future<Directory> Function() workRoot,
    required SpeechAudioEncoder encoder,
    SpeechClipDecoder? decoder,
    SpeechAssembler? assemble,
    DateTime Function()? clock,
  }) : _voices = voices,
       _workRoot = workRoot,
       _encoder = encoder,
       _decoder = decoder,
       _assemble = assemble ?? _assembleOffThread,
       _clock = clock ?? DateTime.now;

  /// Desde cuándo una carpeta de trabajo sin tocar se da por abandonada.
  static const staleAfter = Duration(days: 14);

  final List<SpeechVoiceRenderer> Function() _voices;
  final Future<Directory> Function() _workRoot;
  final SpeechAudioEncoder _encoder;
  final SpeechClipDecoder? _decoder;
  final SpeechAssembler _assemble;
  final DateTime Function() _clock;

  static final _validKey = RegExp(r'^[A-Za-z0-9_-]+$');

  static Future<AssembledSpeech> _assembleOffThread(AssembleSpeechJob job) =>
      Isolate.run(() => assembleSpeechWav(job));

  /// Quien hace [voiceId], o `null` si nadie en este dispositivo.
  SpeechVoiceRenderer? rendererOf(String voiceId) {
    for (final renderer in _voices()) {
      if (renderer.owns(voiceId)) return renderer;
    }
    return null;
  }

  /// Si [voiceId] puede generar ya, sin bajar nada.
  Future<bool> isReady(String voiceId) async =>
      await rendererOf(voiceId)?.isReady(voiceId) ?? false;

  /// Lo que costaría generar [pieces] con voces de la nube, o `null` si son
  /// todas gratis (decisión F): lo que se dice antes de pedir confirmación.
  SpeechAudioCost? costOf(Iterable<SpeechAudioPiece> pieces) =>
      speechAudioCostOf(pieces, (id) => rendererOf(id)?.priceOf(id));

  /// Genera [request]. Lanza [SpeechAudioException] si falta una voz o un
  /// motor falla, y [ProcessingCancelledException] si se cancela con
  /// [cancellation]; en los dos casos, lo hecho queda para el próximo
  /// intento.
  Future<SpeechAudioResult> render(
    SpeechAudioRequest request, {
    CancellationSignal? cancellation,
    void Function(int done, int total)? onProgress,
  }) async {
    final key = request.workKey;
    if (!_validKey.hasMatch(key)) {
      throw ArgumentError.value(key, 'workKey', 'un solo tramo de carpeta');
    }
    if (request.pieces.isEmpty) {
      throw ArgumentError.value(request.pieces, 'pieces', 'sin tramos');
    }
    final root = await _workRoot();
    await _sweepStale(root, keep: key);
    final folder = Directory(p.join(root.path, key));
    await folder.create(recursive: true);
    final total = request.pieces.length + 1;

    // Qué tramo va en qué archivo, y quién lo hace.
    final plan =
        <({SpeechAudioPiece piece, File clip, SpeechVoiceRenderer by})>[];
    for (final piece in request.pieces) {
      final by = rendererOf(piece.voiceId);
      if (by == null) {
        throw SpeechAudioException(
          SpeechAudioFailure.voiceMissing,
          voiceId: piece.voiceId,
          detail: 'nadie hace esta voz en este dispositivo',
        );
      }
      plan.add((
        piece: piece,
        clip: File(p.join(folder.path, _clipName(piece, by))),
        by: by,
      ));
    }
    // Las voces que todavía tienen algo que decir, todas listas antes de
    // empezar.
    final checked = <String>{};
    for (final step in plan) {
      if (_isDone(step.clip) || !checked.add(step.piece.voiceId)) continue;
      if (!await step.by.isReady(step.piece.voiceId)) {
        throw SpeechAudioException(
          SpeechAudioFailure.voiceMissing,
          voiceId: step.piece.voiceId,
          detail: 'la voz no está en el teléfono',
        );
      }
    }

    for (final (index, step) in plan.indexed) {
      cancellation?.throwIfCancelled();
      onProgress?.call(index, total);
      if (_isDone(step.clip)) continue;
      final part = File('${step.clip.path}.part');
      try {
        await step.by.render(
          voiceId: step.piece.voiceId,
          text: step.piece.text,
          outputPath: part.path,
        );
      } on SpeechAudioException {
        _deleteQuietly(part);
        rethrow;
        // Cualquier otra cosa de un motor también es una falla del motor, con
        // su voz, y no un error suelto.
        // ignore: avoid_catches_without_on_clauses
      } catch (error) {
        _deleteQuietly(part);
        throw SpeechAudioException(
          SpeechAudioFailure.engine,
          voiceId: step.piece.voiceId,
          detail: '$error',
        );
      }
      final wrote = part.existsSync() && part.lengthSync() > 0;
      if (wrote && !isWavFile(part.path)) {
        await _decode(part, step.piece.voiceId);
      }
      if (!_isDone(part)) {
        _deleteQuietly(part);
        throw SpeechAudioException(
          SpeechAudioFailure.engine,
          voiceId: step.piece.voiceId,
          detail: 'el motor no dejó audio',
        );
      }
      await part.rename(step.clip.path);
    }
    cancellation?.throwIfCancelled();
    onProgress?.call(plan.length, total);

    final wav = p.join(folder.path, 'armado.wav');
    final AssembledSpeech assembled;
    try {
      assembled = await _assemble(
        AssembleSpeechJob(
          parts: [
            for (final step in plan)
              (
                path: step.clip.path,
                pauseMs: step.piece.pauseAfter.inMilliseconds,
              ),
          ],
          outputPath: wav,
        ),
      );
    } on FormatException catch (e) {
      throw SpeechAudioException(SpeechAudioFailure.file, detail: '$e');
    } on FileSystemException catch (e) {
      throw SpeechAudioException(SpeechAudioFailure.file, detail: '$e');
    }
    cancellation?.throwIfCancelled();

    final m4a = p.join(folder.path, 'audio.m4a');
    bool compressed;
    try {
      compressed = await _encoder.toM4a(wav, m4a);
    } on Exception catch (e) {
      throw SpeechAudioException(SpeechAudioFailure.file, detail: '$e');
    }
    if (compressed) _deleteQuietly(File(wav));
    onProgress?.call(total, total);
    Duration at(int samples) => Duration(
      microseconds:
          samples * Duration.microsecondsPerSecond ~/ kSpeechAudioSampleRate,
    );
    return SpeechAudioResult(
      path: compressed ? m4a : wav,
      mimeType: compressed ? 'audio/mp4' : 'audio/wav',
      duration: at(assembled.samples),
      starts: [for (final start in assembled.starts) at(start)],
    );
  }

  /// Lleva a WAV, en su lugar, el tramo [part] que un motor dejó en otro
  /// formato —el MP3 de una voz de la nube—. Sin decodificador, o si el
  /// sistema no pudo, es una falla del archivo, y no queda nada a medias.
  Future<void> _decode(File part, String voiceId) async {
    final decoder = _decoder;
    final wav = File('${part.path}.wav');
    try {
      if (decoder == null || !await decoder.toWav(part.path, wav.path)) {
        throw SpeechAudioException(
          SpeechAudioFailure.file,
          voiceId: voiceId,
          detail: 'un tramo que no es WAV, sin con qué decodificarlo',
        );
      }
    } on SpeechAudioException {
      _deleteQuietly(part);
      _deleteQuietly(wav);
      rethrow;
    } on Exception catch (e) {
      _deleteQuietly(part);
      _deleteQuietly(wav);
      throw SpeechAudioException(
        SpeechAudioFailure.file,
        voiceId: voiceId,
        detail: '$e',
      );
    }
    _deleteQuietly(part);
    await wav.rename(part.path);
  }

  /// Borra la carpeta del trabajo [workKey]: lo que quien pidió ya guardó, o
  /// un trabajo que no se va a retomar. No falla si no estaba.
  Future<void> discard(String workKey) async {
    if (!_validKey.hasMatch(workKey)) return;
    final folder = Directory(p.join((await _workRoot()).path, workKey));
    if (folder.existsSync()) await folder.delete(recursive: true);
  }

  /// El nombre del WAV de [piece]: su texto, su voz y la versión de la voz.
  static String _clipName(SpeechAudioPiece piece, SpeechVoiceRenderer by) {
    final digest = sha256.convert(
      utf8.encode(
        '${by.versionOf(piece.voiceId)}\n${piece.voiceId}\n'
        '${piece.text}',
      ),
    );
    return 't-${digest.toString().substring(0, 24)}.wav';
  }

  /// Si [clip] quedó entero: está, y tiene más que la cabecera.
  static bool _isDone(File clip) => clip.existsSync() && clip.lengthSync() > 44;

  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Lo que no se pudo borrar se barre con la carpeta.
    }
  }

  /// Borra las carpetas de [root] que nadie tocó en [staleAfter], salvo la
  /// de [keep].
  Future<void> _sweepStale(Directory root, {required String keep}) async {
    if (!root.existsSync()) return;
    final limit = _clock().subtract(staleAfter);
    for (final entry in root.listSync()) {
      if (entry is! Directory || p.basename(entry.path) == keep) continue;
      try {
        if (entry.statSync().modified.isBefore(limit)) {
          await entry.delete(recursive: true);
        }
      } on FileSystemException {
        // Otro intento la barre.
      }
    }
  }
}
