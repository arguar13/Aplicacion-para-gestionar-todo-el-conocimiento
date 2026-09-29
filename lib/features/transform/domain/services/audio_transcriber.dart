import 'dart:async';

import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/transformers/transform_context.dart';

/// Convierte el audio de un archivo en el texto que se dice en él.
///
/// Mismo criterio que `ImageTextExtractor`: una sola operación, y quien la
/// implementa decide con qué motor y en qué hilo. Sirve tanto para un
/// archivo de audio como para uno de video —la pista de audio es lo único
/// que importa en los dos casos—.
// ignore: one_member_abstracts
abstract interface class AudioTranscriber {
  /// [path] es la ruta absoluta fuera de la web; en la web, donde no existe
  /// tal cosa, es la ruta relativa que guarda la base —mismo criterio que
  /// `ImageTextExtractor.extractText`—.
  ///
  /// [session] es el trabajo en curso: un audio de horas se transcribe por
  /// tramos, avisando el avance y guardando cada tramo, para retomarlo si
  /// se interrumpe (F21).
  Future<String> transcribe(
    String path, {
    TranscriptionSession session = TranscriptionSession.detached,
  });
}

/// El trabajo en curso de transcribir un audio (F21): con qué avisar el
/// avance y saber si abandonar, y dónde guardar los tramos ya hechos.
class TranscriptionSession {
  const TranscriptionSession({
    this.context = TransformContext.detached,
    this.workKey,
    Future<Map<int, String>> Function()? loadSegments,
    Future<void> Function(int segment, String text)? saveSegment,
  }) : _load = loadSegments,
       _save = saveSegment;

  /// Sin cola ni avance guardado.
  static const detached = TranscriptionSession();

  /// La cola: avisar el avance, saber si abandonar.
  final TransformContext context;

  /// Qué se transcribe —el elemento—, para que un paso intermedio caro
  /// —convertir cuatro horas de audio al formato del modelo— se reaproveche
  /// al retomar en vez de rehacerse. `null`: nada se reaprovecha.
  final String? workKey;

  final Future<Map<int, String>> Function()? _load;
  final Future<void> Function(int segment, String text)? _save;

  /// Los tramos ya transcritos en un intento anterior: número de tramo
  /// (desde 0) → texto.
  Future<Map<int, String>> transcribedSegments() async =>
      await _load?.call() ?? const {};

  /// Guarda que [segment] ya se transcribió, con su [text].
  Future<void> saveSegment(int segment, String text) async =>
      _save?.call(segment, text);
}

/// Transcribe un audio de [segmentCount] tramos, por partes y retomable
/// (F21): lo que ya se hizo en un intento anterior no se repite, cada tramo
/// nuevo se guarda apenas llega, el avance se avisa tramo a tramo, y si hay
/// que abandonar se corta en el acto —sin esperar a que termine el tramo en
/// curso—.
///
/// [transcribe] recibe los tramos que faltan, en orden, y entrega cada uno
/// con su texto a medida que los termina. Es todo lo que cambia entre un
/// motor y otro; el resto —qué falta, qué se guarda, cómo se arma el texto—
/// es esto, y por eso se prueba acá, sin motor.
Future<String> runSegmentedTranscription({
  required int segmentCount,
  required TranscriptionSession session,
  required Stream<(int, String)> Function(List<int> pending) transcribe,
}) async {
  final context = session.context..throwIfCancelled();

  final texts = List<String?>.filled(segmentCount, null);
  for (final MapEntry(:key, :value)
      in (await session.transcribedSegments()).entries) {
    if (key >= 0 && key < segmentCount) texts[key] = value;
  }

  final pending = [
    for (var i = 0; i < segmentCount; i++)
      if (texts[i] == null) i,
  ];
  var done = segmentCount - pending.length;
  context.reportProgress(done, segmentCount);

  if (pending.isNotEmpty) {
    final results = cancellableStream(
      transcribe(pending),
      context.whenCancelled,
    );
    await for (final (segment, text) in results) {
      texts[segment] = text;
      await session.saveSegment(segment, text);
      done++;
      context.reportProgress(done, segmentCount);
    }
  }

  return texts
      .map((text) => text?.trim() ?? '')
      .where((text) => text.isNotEmpty)
      .join(' ');
}
