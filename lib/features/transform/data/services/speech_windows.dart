import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/transform/data/services/pcm16_samples.dart';

/// Cómo se parte un audio en los tramos que Whisper transcribe de a uno, y
/// cómo se defiende la transcripción de cada tramo de los errores groseros
/// del motor (F22).
///
/// Cada decisión, medida antes de escribirla —una alabanza cantada con
/// música y 10 minutos de una charla con subtítulos hechos por personas, con
/// el mismo motor y la misma versión que la app; ver
/// `docs/planes/F22-fidelidad-del-texto.md`—:
///
/// - **Tramos de hasta 14,5 s, cortados en la pausa más cercana**, no cada
///   29 s en un punto fijo del reloj: el corte fijo cae a mitad de palabra
///   (15 % más palabras perdidas) y los tramos largos hacen que Whisper
///   entre en bucle con la música ("oh, oh, oh…" 90 veces en un tramo).
///   La pausa se busca por energía, sin un detector de voz: el que se probó
///   (Silero) no considera voz al canto con música, y descartaba 186 de 299
///   segundos de una canción.
/// - **Un tramo en bucle se vuelve a transcribir en mitades**, cortadas
///   también en una pausa: en la prueba, las dos mitades salieron limpias.
/// - **El silencio puro no llega al motor**: es donde Whisper inventa frases
///   enteras que nadie dijo.
///
/// Sin nada de sherpa-onnx: el motor entra como una función, así que es la
/// misma lógica en el dispositivo y en la web, y se prueba con uno falso.

/// La frecuencia con la que está entrenado Whisper.
const speechSampleRate = 16000;

/// El largo máximo de un tramo. Whisper admite hasta 29,5 s —ver
/// `whisperChunkSamples`—, pero con la mitad pierde menos palabras y no
/// entra en bucles con la música, al mismo costo (medido, F22).
const maxWindowSamples = whisperChunkSamples ~/ 2;

/// Cuánto antes del largo máximo se busca la pausa donde cortar.
const pauseSearchSamples = speechSampleRate * 3;

/// Un bloque de energía: 10 ms.
const energyBlockSamples = speechSampleRate ~/ 100;

/// Por debajo de esta energía —-50 dBFS de media cuadrática, en cada bloque
/// de 10 ms del tramo— un tramo es silencio puro: ni la voz más baja de una
/// grabación con el teléfono queda tan abajo en todo un tramo.
const silenceMeanSquare = 1e-5;

/// Un tramo del audio: de la muestra [start] a [end] (sin incluirla).
@immutable
class AudioWindow {
  const AudioWindow(this.start, this.end, {this.silent = false});

  final int start;
  final int end;

  /// Silencio puro: no se transcribe.
  final bool silent;

  int get length => end - start;

  Duration get startTime =>
      Duration(microseconds: start * 1000000 ~/ speechSampleRate);

  @override
  bool operator ==(Object other) =>
      other is AudioWindow &&
      other.start == start &&
      other.end == end &&
      other.silent == silent;

  @override
  int get hashCode => Object.hash(start, end, silent);

  @override
  String toString() => 'AudioWindow($start, $end${silent ? ', silent' : ''})';
}

/// La energía de un audio, bloque a bloque de [energyBlockSamples], armada
/// por partes: un audio de horas se recorre leyéndolo del disco de a
/// pedazos, sin tenerlo entero en memoria (una hora son 360.000 bloques,
/// 1,4 MB).
class EnergyProfileBuilder {
  final _blocks = <double>[];
  double _sum = 0;
  int _count = 0;
  int _samples = 0;

  /// Suma [samples], que siguen a los anteriores.
  void add(Float32List samples) {
    for (final sample in samples) {
      _sum += sample * sample;
      _count++;
      if (_count == energyBlockSamples) {
        _blocks.add(_sum / _count);
        _sum = 0;
        _count = 0;
      }
    }
    _samples += samples.length;
  }

  /// La energía de cada bloque —el último, incompleto, con lo que tenga— y
  /// cuántas muestras hay en total.
  EnergyProfile build() => EnergyProfile(
    Float32List.fromList([..._blocks, if (_count > 0) _sum / _count]),
    _samples,
  );
}

/// Media cuadrática por bloque de [energyBlockSamples], y el total de
/// muestras del audio.
class EnergyProfile {
  const EnergyProfile(this.blocks, this.totalSamples);

  factory EnergyProfile.of(Float32List samples) =>
      (EnergyProfileBuilder()..add(samples)).build();

  final Float32List blocks;
  final int totalSamples;
}

/// Parte el audio en tramos de hasta [maxWindowSamples], cortando cada uno
/// en el punto más silencioso de sus últimos [pauseSearchSamples]: la
/// ventana de 30 ms —tres bloques— de menor energía, por su centro.
///
/// Determinista: el mismo audio da siempre los mismos tramos, así que al
/// retomar una transcripción el tramo 12 es el mismo tramo 12.
List<AudioWindow> planWindows(EnergyProfile profile) {
  final total = profile.totalSamples;
  final windows = <AudioWindow>[];
  var start = 0;
  while (start < total) {
    final limit = start + maxWindowSamples;
    final end = limit >= total
        ? total
        : _quietestPoint(profile, limit - pauseSearchSamples, limit);
    windows.add(
      AudioWindow(start, end, silent: _isSilent(profile, start, end)),
    );
    start = end;
  }
  return windows;
}

/// El centro de los 30 ms más silenciosos entre [from] y [to] (muestras):
/// dónde cortar sin partir una palabra.
int _quietestPoint(EnergyProfile profile, int from, int to) {
  final blocks = profile.blocks;
  final first = (from / energyBlockSamples).ceil();
  final last = to ~/ energyBlockSamples - 3;
  if (last < first) return to;

  var best = first;
  var bestEnergy = double.infinity;
  for (var b = first; b <= last; b++) {
    final energy = blocks[b] + blocks[b + 1] + blocks[b + 2];
    // Ante un empate —silencio digital parejo— gana el más tardío: tramos
    // lo más largos posible, menos cortes.
    if (energy <= bestEnergy) {
      bestEnergy = energy;
      best = b;
    }
  }
  return (best + 1) * energyBlockSamples + energyBlockSamples ~/ 2;
}

bool _isSilent(EnergyProfile profile, int start, int end) {
  final blocks = profile.blocks;
  final first = start ~/ energyBlockSamples;
  final last = math.min((end - 1) ~/ energyBlockSamples, blocks.length - 1);
  for (var b = first; b <= last; b++) {
    if (blocks[b] >= silenceMeanSquare) return false;
  }
  return true;
}

/// Si [text] es un bucle de repetición del motor: el mismo criterio que usa
/// Whisper original para descartar una decodificación —el texto se
/// comprime más de 2,4 veces—. Un texto normal da entre 1 y 2, incluso una
/// letra de canción con estribillos (1,9 lo más alto medido); el bucle de
/// la alabanza de prueba, 9,4.
///
/// Un texto corto no se juzga: no tiene cómo repetirse tanto, y comprimido
/// casi no cambia de tamaño.
bool looksLikeRepetitionLoop(String text) {
  final bytes = utf8.encode(text);
  if (bytes.length < 40) return false;
  final compressed = const ZLibEncoder().encode(bytes);
  return bytes.length / compressed.length > 2.4;
}

/// Cuántas veces se puede partir en mitades un tramo en bucle: hasta en
/// cuartos, de unos 3,6 s.
const maxLoopSplits = 2;

/// Transcribe un tramo con [decode] —el motor— defendiéndose de los bucles:
/// un tramo cuyo texto es un bucle se vuelve a transcribir en dos mitades,
/// cortadas en su pausa más cercana al medio, y así hasta
/// [maxLoopSplits] veces. Si un pedazo sigue en bucle, no se guarda lo que
/// inventó: queda una marca visible con su lugar en el audio —un hueco
/// honesto, no texto que nadie dijo—.
///
/// [offset] es dónde empieza [samples] dentro del audio entero, en
/// muestras: para que la marca diga en qué minuto está el hueco.
String transcribeGuarded(
  Float32List samples,
  String Function(Float32List samples) decode, {
  int offset = 0,
}) {
  final pieces = <Object>[];
  _transcribeGuarded(samples, decode, offset, 0, pieces);

  // Dos huecos seguidos —las dos mitades de un pedazo, las dos en bucle—
  // son un solo hueco.
  final merged = <Object>[];
  for (final piece in pieces) {
    final last = merged.isEmpty ? null : merged.last;
    if (piece is (int, int) && last is (int, int) && last.$2 == piece.$1) {
      merged.last = (last.$1, piece.$2);
    } else {
      merged.add(piece);
    }
  }
  return merged
      .map(
        (piece) => switch (piece) {
          (final int start, final int end) => unrecognizedMarker(start, end),
          _ => piece as String,
        },
      )
      .where((text) => text.isNotEmpty)
      .join(' ');
}

/// Agrega a [pieces] el texto de cada pedazo, o su hueco —`(inicio, fin)`
/// en muestras— si no hubo forma de transcribirlo sin bucle.
void _transcribeGuarded(
  Float32List samples,
  String Function(Float32List samples) decode,
  int offset,
  int depth,
  List<Object> pieces,
) {
  final text = decode(samples).trim();
  if (!looksLikeRepetitionLoop(text)) {
    pieces.add(text);
    return;
  }
  if (depth >= maxLoopSplits) {
    pieces.add((offset, offset + samples.length));
    return;
  }

  final middle = _quietestPoint(
    EnergyProfile.of(samples),
    samples.length ~/ 3,
    samples.length * 2 ~/ 3,
  );
  _transcribeGuarded(
    Float32List.sublistView(samples, 0, middle),
    decode,
    offset,
    depth + 1,
    pieces,
  );
  _transcribeGuarded(
    Float32List.sublistView(samples, middle),
    decode,
    offset + middle,
    depth + 1,
    pieces,
  );
}

/// La marca que queda en lugar de un pedazo que el motor no pudo
/// transcribir sin inventar: "[fragmento no reconocido 3:15–3:19]".
String unrecognizedMarker(int start, int end) =>
    '[fragmento no reconocido '
    '${_clock(start)}–${_clock(end)}]';

String _clock(int sample) {
  final seconds = sample ~/ speechSampleRate;
  final h = seconds ~/ 3600;
  final m = seconds % 3600 ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
