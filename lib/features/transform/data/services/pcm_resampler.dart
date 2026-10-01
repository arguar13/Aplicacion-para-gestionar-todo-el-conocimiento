import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// De PCM crudo —como lo entrega el decodificador del sistema— al WAV de
/// Whisper: 16 kHz, mono, 16 bits (F22).
///
/// Corre en Dart, compilado a código nativo, y no en Kotlin: en una app
/// recién instalada Android ejecuta el código Kotlin interpretado, y hacer
/// cuentas muestra por muestra ahí tardaba 113 s por cada 5 minutos de AAC
/// (medido en el teléfono del usuario). El lado de Android solo decodifica
/// y vuelca los bytes (`AudioToWav.kt`).

/// Cómo vienen las muestras de un tramo del PCM crudo.
enum PcmEncoding {
  /// 16 bits con signo.
  int16,

  /// 32 bits de punto flotante.
  float32,

  /// 8 bits sin signo.
  uint8,

  /// 32 bits con signo.
  int32;

  int get bytesPerSample => switch (this) {
    int16 => 2,
    float32 => 4,
    uint8 => 1,
    int32 => 4,
  };
}

/// Un tramo del PCM crudo con un mismo formato: el decodificador puede
/// cambiarlo a mitad de camino (lo anuncia), y cada tramo se lee con el
/// suyo.
class PcmSegment {
  const PcmSegment({
    required this.offset,
    required this.length,
    required this.sampleRate,
    required this.channels,
    required this.encoding,
  });

  /// Desde qué byte del archivo crudo, y cuántos.
  final int offset;
  final int length;
  final int sampleRate;
  final int channels;
  final PcmEncoding encoding;
}

/// La frecuencia de Whisper.
const whisperSampleRate = 16000;

/// Escribe en [wavPath] el WAV de 16 kHz, mono, 16 bits con el audio de
/// [segments] de [rawPath], leyéndolo por partes: un audio de horas nunca
/// está entero en memoria. Devuelve cuántas muestras escribió.
int writeWhisperWav(String rawPath, List<PcmSegment> segments, String wavPath) {
  final raw = File(rawPath).openSync();
  final out = File(wavPath).openSync(mode: FileMode.write);
  final sink = _WavWriter(out);
  try {
    sink.begin();
    for (final segment in segments) {
      final resampler = PolyphaseResampler(
        segment.sampleRate,
        whisperSampleRate,
      );
      final frameBytes = segment.channels * segment.encoding.bytesPerSample;
      // De a ~1 MB, en cuadros enteros.
      final chunk = math.max(frameBytes, (1 << 20) ~/ frameBytes * frameBytes);
      raw.setPositionSync(segment.offset);
      var left = segment.length - segment.length % frameBytes;
      while (left > 0) {
        final bytes = raw.readSync(math.min(chunk, left));
        if (bytes.isEmpty) break;
        left -= bytes.length;
        resampler.push(
          toMonoSamples(bytes, segment.channels, segment.encoding),
          sink.write,
        );
      }
      resampler.flush(sink.write);
    }
    sink.end();
    return sink.samples;
  } finally {
    out.closeSync();
    raw.closeSync();
  }
}

/// [bytes] —cuadros enteros de [channels] canales, en little-endian— a
/// muestras mono entre -1 y 1, promediando los canales.
Float32List toMonoSamples(Uint8List bytes, int channels, PcmEncoding encoding) {
  final data = ByteData.sublistView(bytes);
  final size = encoding.bytesPerSample;
  final frames = bytes.length ~/ (size * channels);
  final mono = Float32List(frames);
  var at = 0;
  for (var frame = 0; frame < frames; frame++) {
    var sum = 0.0;
    for (var channel = 0; channel < channels; channel++) {
      sum += switch (encoding) {
        PcmEncoding.int16 => data.getInt16(at, Endian.little) / 32768,
        PcmEncoding.float32 => data.getFloat32(at, Endian.little),
        PcmEncoding.uint8 => (data.getUint8(at) - 128) / 128,
        PcmEncoding.int32 => data.getInt32(at, Endian.little) / 2147483648,
      };
      at += size;
    }
    mono[frame] = sum / channels;
  }
  return mono;
}

/// Remuestreo por filtro sinc con ventana de Blackman, por partes (F22).
///
/// Bajando de frecuencia, el corte va al 95 % del nuevo Nyquist: lo que
/// estaba por encima no se pliega como ruido —un tono de 10 kHz llevado a
/// 16 kHz desaparece, en vez de volver en 6 kHz como hacía la interpolación
/// lineal de `audio_decoder`—. Polifásico: la relación entre frecuencias es
/// una fracción exacta —44.100 a 16.000 es 441/160—, así que cada muestra de
/// salida cae en una de [_phases] posiciones entre dos de entrada, y sus
/// coeficientes se calculan una sola vez. Con una relación rara —más de
/// 4096 fases— se usa la fase más cercana: un error de 1/8192 de muestra.
class PolyphaseResampler {
  PolyphaseResampler(int from, int to)
    : _passthrough = from == to,
      _up = to ~/ _gcd(from, to),
      _down = from ~/ _gcd(from, to) {
    _phases = math.min(_up, _maxPhases);
    final cutoff = 0.5 * math.min(1, to / from) * 0.95;
    _halfWidth = (_zeroCrossings / (2 * cutoff)).ceil();
    _taps = 2 * _halfWidth;
    _coefficients = Float32List(_phases * _taps);
    for (var phase = 0; phase < _phases; phase++) {
      final frac = phase / _phases;
      for (var t = 0; t < _taps; t++) {
        final x = (t - _halfWidth + 1) - frac;
        final sinc = x == 0
            ? 1.0
            : math.sin(2 * math.pi * cutoff * x) / (2 * math.pi * cutoff * x);
        final w = x.abs() / _halfWidth;
        final blackman = w >= 1
            ? 0.0
            : 0.42 +
                  0.5 * math.cos(math.pi * w) +
                  0.08 * math.cos(2 * math.pi * w);
        _coefficients[phase * _taps + t] = 2 * cutoff * sinc * blackman;
      }
    }
  }

  static const _zeroCrossings = 16;
  static const _maxPhases = 4096;

  final bool _passthrough;
  final int _up;
  final int _down;
  late final int _phases;
  late final int _halfWidth;
  late final int _taps;
  late final Float32List _coefficients;

  Float32List _history = Float32List(0);
  var _filled = 0;
  var _started = false;

  /// La muestra de entrada en la que cae la próxima de salida, y cuánto
  /// pasa de ella en fracciones de 1/[_up].
  var _center = 0;
  var _offset = 0;

  void push(Float32List samples, void Function(double sample) emit) {
    if (_passthrough) {
      for (final s in samples) {
        emit(s);
      }
      return;
    }
    if (!_started) {
      // Ceros antes del principio, para que la primera muestra tenga a
      // quién mirar hacia atrás.
      _started = true;
      _history = Float32List(math.max(4 * _taps, samples.length + _taps));
      _filled = _halfWidth;
      _center = _halfWidth;
    }
    _append(samples);
    _produce(emit, _filled - _halfWidth);
    _compact();
  }

  void flush(void Function(double sample) emit) {
    if (_passthrough || !_started) return;
    final end = _filled;
    _append(Float32List(_halfWidth + 1));
    _produce(emit, end);
    _started = false;
    _history = Float32List(0);
    _filled = 0;
  }

  void _append(Float32List samples) {
    if (_filled + samples.length > _history.length) {
      final grown = Float32List(
        math.max(_history.length * 2, _filled + samples.length),
      )..setRange(0, _filled, _history);
      _history = grown;
    }
    _history.setRange(_filled, _filled + samples.length, samples);
    _filled += samples.length;
  }

  void _compact() {
    final drop = _center - _halfWidth;
    if (drop <= 0) return;
    _history.setRange(0, _filled - drop, _history, drop);
    _filled -= drop;
    _center -= drop;
  }

  void _produce(void Function(double sample) emit, int limit) {
    final h = _history;
    final c = _coefficients;
    final taps = _taps;
    while (_center < limit) {
      final phase = _phases == _up ? _offset : _offset * _phases ~/ _up;
      final base = phase * taps;
      final start = _center - _halfWidth + 1;
      var acc = 0.0;
      for (var t = 0; t < taps; t++) {
        acc += h[start + t] * c[base + t];
      }
      emit(acc);
      _offset += _down;
      _center += _offset ~/ _up;
      _offset %= _up;
    }
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);
}

/// El WAV de salida, con la cabecera de 44 bytes que se completa al final.
class _WavWriter {
  _WavWriter(this._file);

  final RandomAccessFile _file;
  final _buffer = ByteData(1 << 16);
  var _used = 0;
  int samples = 0;

  void begin() => _file.writeFromSync(Uint8List(44));

  void write(double sample) {
    if (_used == _buffer.lengthInBytes) _drain();
    final value = (sample * 32767).round().clamp(-32768, 32767);
    _buffer.setInt16(_used, value, Endian.little);
    _used += 2;
    samples++;
  }

  void end() {
    _drain();
    final data = samples * 2;
    final header = ByteData(44)
      ..setUint32(0, 0x52494646) // RIFF
      ..setUint32(4, 36 + data, Endian.little)
      ..setUint32(8, 0x57415645) // WAVE
      ..setUint32(12, 0x666d7420) // fmt
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, whisperSampleRate, Endian.little)
      ..setUint32(28, whisperSampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(36, 0x64617461) // data
      ..setUint32(40, data, Endian.little);
    _file
      ..setPositionSync(0)
      ..writeFromSync(header.buffer.asUint8List());
  }

  void _drain() {
    _file.writeFromSync(_buffer.buffer.asUint8List(0, _used));
    _used = 0;
  }
}
