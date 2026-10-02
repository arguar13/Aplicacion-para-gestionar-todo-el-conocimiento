import 'dart:async';

import 'package:sinapsis/core/util/transcript_timestamps.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/entities/timed_text.dart';
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
  ///
  /// [language] es el idioma en que se habla, como código de dos letras:
  /// se transcribe en ese idioma, sin detectarlo ni traducir (F22).
  ///
  /// Devuelve el texto y, si el motor los mide, el momento en que se dice
  /// cada palabra (F23).
  Future<Transcript> transcribe(
    String path, {
    TranscriptionSession session = TranscriptionSession.detached,
    String language = defaultTranscriptionLanguage,
  });
}

/// El idioma de un audio del que no se sabe el idioma: el de quien usa esta
/// app. Detectarlo solo no es opción: Whisper confunde el español con el
/// gallego y le quita las tildes (medido, F22).
const defaultTranscriptionLanguage = 'es';

/// Los idiomas que se ofrecen para transcribir, como código de dos letras.
/// Whisper admite muchos más; estos son los que tiene sentido ofrecer en una
/// lista corta, y cualquier otro código que llegue igual se respeta.
const transcriptionLanguages = ['es', 'en', 'pt', 'fr', 'it', 'de'];

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
///
/// Con [segmentStart] —dónde empieza cada tramo en el audio—, el texto sale
/// con una línea por tramo y su marca de tiempo, "[3:15] …", igual que una
/// transcripción de YouTube (F22): se puede ubicar cada frase en el audio,
/// y la búsqueda y las citas ya entienden ese formato. Sin él, texto corrido.
/// Un tramo sin texto —silencio, música— no deja línea.
///
/// Con [stitch], los textos de todos los tramos pasan por ahí antes de
/// armar el texto: el motor transcribe tramos que se solapan, y [stitch]
/// los une sin repetir lo que dicen los dos (F22, ver
/// `stitchOverlapping`). Se guarda lo que dijo el motor y se une al
/// final: un tramo retomado se une igual que uno recién hecho.
///
/// Cada tramo llega palabra por palabra con su momento, si el motor lo mide
/// (F23); se guarda con él —`TimedText.encode`—, así un tramo retomado no
/// pierde sus tiempos, y uno guardado por una versión anterior se retoma
/// sin tiempos. Las palabras del resultado son las del texto, en orden y
/// sin las marcas de tiempo de cada renglón.
Future<Transcript> runSegmentedTranscription({
  required int segmentCount,
  required TranscriptionSession session,
  required Stream<(int, TimedText)> Function(List<int> pending) transcribe,
  Duration Function(int segment)? segmentStart,
  List<TimedText> Function(List<TimedText> segments)? stitch,
}) async {
  final context = session.context..throwIfCancelled();

  final texts = List<TimedText?>.filled(segmentCount, null);
  for (final MapEntry(:key, :value)
      in (await session.transcribedSegments()).entries) {
    if (key >= 0 && key < segmentCount) texts[key] = TimedText.decode(value);
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
      await session.saveSegment(segment, text.encode());
      done++;
      context.reportProgress(done, segmentCount);
    }
  }

  String line(int segment, String text) => segmentStart == null
      ? text
      : '[${formatTimestamp(segmentStart(segment))}] $text';

  final raw = [for (final text in texts) text ?? TimedText.empty];
  final joined = stitch?.call(raw) ?? raw;
  final kept = [
    for (var i = 0; i < segmentCount; i++)
      if (!joined[i].isEmpty) (i, joined[i]),
  ];
  return Transcript(
    [
      for (final (i, segment) in kept) line(i, segment.text),
    ].join(segmentStart == null ? ' ' : '\n'),
    [for (final (_, segment) in kept) ...segment.words],
  );
}
