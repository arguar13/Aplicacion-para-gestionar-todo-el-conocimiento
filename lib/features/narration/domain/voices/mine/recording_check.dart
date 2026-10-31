import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Cómo salió una muestra para clonar una voz (F47, paso 4): cuánto dura,
/// cuánta voz tiene, cuánto ruido de fondo y si satura. Es lo que la app mide
/// antes de usarla, para avisar si conviene repetirla.
///
/// **Cómo se mide** (una heurística documentada, no un modelo):
///
/// - El audio se corta en cuadros de [frameMillis] ms y de cada uno se saca
///   su nivel —la raíz del promedio de los cuadrados— en dBFS (0 es lo más
///   fuerte que entra en 16 bits).
/// - **El ruido de fondo** es el percentil 10 de esos niveles: en una lectura
///   en voz alta, al menos uno de cada diez cuadros es pausa entre palabras,
///   y lo que suena ahí es el cuarto. **La voz** es el percentil 90.
/// - **Cuánta voz hay** son los cuadros que pasan el ruido por
///   [voiceOverNoiseDb] y además [minimumVoiceDb]: se cuentan los segundos en
///   que alguien habla,
///   no los de silencio.
/// - **Satura** si más de [maxClippedRatio] de las muestras tocan el tope.
///
/// Los umbrales salen de lo que se pide para clonar —1 o 2 minutos de voz
/// clara, sin ruido ni música— y de lo que se oye en una grabación casera: con
/// menos de 25 dB entre la voz y el ruido, el ruido se oye en la voz clonada.
@immutable
class RecordingReport {
  const RecordingReport({
    required this.total,
    required this.voiced,
    required this.noiseDb,
    required this.voiceDb,
    required this.clippedRatio,
  });

  final Duration total;

  /// Los segundos en que hay voz.
  final Duration voiced;

  /// El nivel del ruido de fondo, en dBFS.
  final double noiseDb;

  /// El nivel de la voz, en dBFS.
  final double voiceDb;

  /// La parte de las muestras que toca el tope de 16 bits.
  final double clippedRatio;

  static const frameMillis = 30;

  /// Lo mínimo que tiene que superar un cuadro al ruido para contar como voz.
  static const voiceOverNoiseDb = 10.0;

  /// Lo mínimo que tiene que sonar un cuadro para contar como voz: debajo de
  /// esto es silencio aunque no haya ruido.
  static const minimumVoiceDb = -50.0;

  /// Debajo de esto, la voz está demasiado baja: hay que acercarse.
  static const quietVoiceDb = -35.0;

  /// Lo mínimo entre la voz y el ruido para que el ruido no se oiga.
  static const minimumSignalToNoiseDb = 25.0;

  /// El ruido de fondo, por sí solo, que ya se oye.
  static const loudNoiseDb = -45.0;

  static const maxClippedRatio = 0.001;

  /// Lo que se pide: entre 1 y 2 minutos de voz. Menos de [shortVoice] se
  /// avisa; menos de [tooLittleVoice] no alcanza para clonar.
  static const shortVoice = Duration(seconds: 45);
  static const tooLittleVoice = Duration(seconds: 20);

  /// Más de esto no es «1 o 2 minutos»: se pide uno más corto.
  static const longest = Duration(minutes: 5);

  /// Lo que la app propone grabar como mucho: la grabación se corta sola.
  static const recordingLimit = Duration(minutes: 3);

  double get signalToNoiseDb => voiceDb - noiseDb;

  /// Qué conviene arreglar, en el orden en que se dice.
  List<RecordingIssue> get issues => [
    if (voiced < minimumUsableVoice || voiceDb < minimumVoiceDb)
      RecordingIssue.tooLittleVoice
    else if (voiced < shortVoice)
      RecordingIssue.short,
    if (total > longest) RecordingIssue.tooLong,
    if (voiceDb >= minimumVoiceDb && voiceDb < quietVoiceDb)
      RecordingIssue.quiet,
    if (voiceDb >= minimumVoiceDb &&
        (signalToNoiseDb < minimumSignalToNoiseDb || noiseDb > loudNoiseDb))
      RecordingIssue.noisy,
    if (clippedRatio > maxClippedRatio) RecordingIssue.clipping,
  ];

  /// La voz mínima para clonar: [tooLittleVoice].
  static const minimumUsableVoice = tooLittleVoice;

  /// Si se puede usar: con avisos, sí —la persona decide—; sin voz suficiente
  /// o demasiado larga, no.
  bool get usable =>
      !issues.contains(RecordingIssue.tooLittleVoice) &&
      !issues.contains(RecordingIssue.tooLong);

  /// Si conviene repetirla.
  bool get worthRepeating => issues.isNotEmpty;

  Map<String, Object?> toJson() => {
    'totalMs': total.inMilliseconds,
    'voicedMs': voiced.inMilliseconds,
    'noiseDb': noiseDb,
    'voiceDb': voiceDb,
    'clippedRatio': clippedRatio,
  };

  static RecordingReport? fromJson(Object? json) {
    if (json is! Map) return null;
    final total = json['totalMs'];
    final voiced = json['voicedMs'];
    final noise = json['noiseDb'];
    final voice = json['voiceDb'];
    final clipped = json['clippedRatio'];
    if (total is! num ||
        voiced is! num ||
        noise is! num ||
        voice is! num ||
        clipped is! num) {
      return null;
    }
    return RecordingReport(
      total: Duration(milliseconds: total.toInt()),
      voiced: Duration(milliseconds: voiced.toInt()),
      noiseDb: noise.toDouble(),
      voiceDb: voice.toDouble(),
      clippedRatio: clipped.toDouble(),
    );
  }
}

/// Lo que puede tener una muestra para clonar.
enum RecordingIssue {
  /// Menos de 20 s de voz: no alcanza.
  tooLittleVoice,

  /// Menos de 45 s de voz: alcanza, pero conviene más.
  short,

  /// Más de 5 minutos.
  tooLong,

  /// La voz se oye baja.
  quiet,

  /// Hay ruido de fondo.
  noisy,

  /// Satura: está demasiado cerca o demasiado fuerte.
  clipping,
}

/// El nivel más bajo que se informa: el silencio digital no tiene dBFS.
const _floorDb = -96.0;

/// Mide [samples] —PCM de 16 bits, mono— a [sampleRate] (ver
/// [RecordingReport]).
RecordingReport analyzeRecording(Int16List samples, int sampleRate) {
  if (sampleRate <= 0) {
    throw ArgumentError.value(sampleRate, 'sampleRate', 'tiene que ser > 0');
  }
  final total = Duration(
    microseconds: samples.length * Duration.microsecondsPerSecond ~/ sampleRate,
  );
  final frameLength = math.max(
    1,
    sampleRate * RecordingReport.frameMillis ~/ 1000,
  );
  final levels = <double>[];
  var clipped = 0;
  for (
    var start = 0;
    start + frameLength <= samples.length;
    start += frameLength
  ) {
    var sum = 0.0;
    for (var i = start; i < start + frameLength; i++) {
      final sample = samples[i];
      if (sample >= 32767 || sample <= -32767) clipped++;
      final value = sample / 32768;
      sum += value * value;
    }
    final rms = math.sqrt(sum / frameLength);
    levels.add(rms <= 0 ? _floorDb : math.max(_floorDb, 20 * _log10(rms)));
  }
  // Lo que quedó al final, más corto que un cuadro, solo cuenta si satura.
  for (var i = levels.length * frameLength; i < samples.length; i++) {
    if (samples[i] >= 32767 || samples[i] <= -32767) clipped++;
  }
  if (levels.isEmpty) {
    return RecordingReport(
      total: total,
      voiced: Duration.zero,
      noiseDb: _floorDb,
      voiceDb: _floorDb,
      clippedRatio: samples.isEmpty ? 0 : clipped / samples.length,
    );
  }
  final sorted = [...levels]..sort();
  final noise = _percentile(sorted, 0.1);
  final voice = _percentile(sorted, 0.9);
  final threshold = math.max(
    noise + RecordingReport.voiceOverNoiseDb,
    RecordingReport.minimumVoiceDb,
  );
  final voicedFrames = levels.where((level) => level >= threshold).length;
  return RecordingReport(
    total: total,
    voiced: Duration(milliseconds: voicedFrames * RecordingReport.frameMillis),
    noiseDb: noise,
    voiceDb: voice,
    clippedRatio: clipped / samples.length,
  );
}

double _percentile(List<double> sorted, double fraction) =>
    sorted[((sorted.length - 1) * fraction).round()];

double _log10(double value) => math.log(value) / math.ln10;

/// Un WAV leído: sus muestras de 16 bits, ya en mono, y a qué frecuencia.
@immutable
class PcmWav {
  const PcmWav({required this.samples, required this.sampleRate});

  /// Lee un WAV PCM de 16 bits —el que graba la app y el que deja el
  /// conversor de audio—: busca los bloques `fmt ` y `data` sin suponer que
  /// la cabecera mide 44 bytes, y junta los canales en uno promediándolos.
  /// Falla con [FormatException] si no es un WAV así.
  factory PcmWav.parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
    if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const FormatException('no es un WAV');
    }
    int? channels;
    int? sampleRate;
    int? bits;
    int? format;
    var at = 12;
    while (at + 8 <= bytes.length) {
      final id = tag(at);
      final size = data.getUint32(at + 4, Endian.little);
      final body = at + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        if (format != 1 || bits != 16 || channels == null || channels < 1) {
          throw const FormatException('el WAV no es PCM de 16 bits');
        }
        final end = math.min(bytes.length, body + size);
        final frames = (end - body) ~/ (2 * channels);
        final samples = Int16List(frames);
        for (var frame = 0; frame < frames; frame++) {
          var sum = 0;
          for (var channel = 0; channel < channels; channel++) {
            sum += data.getInt16(
              body + (frame * channels + channel) * 2,
              Endian.little,
            );
          }
          samples[frame] = sum ~/ channels;
        }
        return PcmWav(samples: samples, sampleRate: sampleRate!);
      }
      // Los bloques van alineados a dos bytes.
      at = body + size + (size.isOdd ? 1 : 0);
    }
    throw const FormatException('el WAV no trae audio');
  }

  final Int16List samples;
  final int sampleRate;
}
