import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sinapsis/features/transform/data/services/pcm_resampler.dart';

/// El armado de un audio de tramos (F47, pasos 5 y 6): de los WAV de cada
/// tramo —con la frecuencia y el formato que dejó cada motor— a uno solo,
/// mono, de 16 bits y a [kSpeechAudioSampleRate], con el silencio pedido
/// entre uno y otro.
///
/// Es código síncrono y sin estado, para correr en un isolate aparte
/// (`SpeechAudioRenderer`): un podcast largo son decenas de megas de
/// muestras, y la pantalla no tiene que trabarse mientras se arman.

/// La frecuencia del audio armado: la de Kokoro y la de la voz del teléfono
/// en casi todos; Piper (22.050) se lleva a esta.
const kSpeechAudioSampleRate = 24000;

/// Lo que se deja de margen al recortar el silencio de los bordes de un
/// tramo: lo que tarda en apagarse una consonante final.
const kSpeechEdgeMargin = Duration(milliseconds: 40);

/// Debajo de esto, una muestra es silencio (un -50 dB): el soplido de fondo
/// de una voz sintetizada, no un sonido.
const kSpeechSilenceLevel = 0.003;

/// El formato de un WAV, leído de su cabecera.
class WavInfo {
  const WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.encoding,
    required this.dataOffset,
    required this.dataLength,
  });

  final int sampleRate;
  final int channels;
  final PcmEncoding encoding;

  /// Dónde empiezan las muestras y cuántos bytes son.
  final int dataOffset;
  final int dataLength;
}

/// Lee la cabecera del WAV [file]: recorre sus partes (`fmt `, `data` y las
/// que sobren, como `LIST`) sin suponer que mide 44 bytes. Lanza
/// [FormatException] si no es un WAV que se sepa leer: PCM de 8, 16 o 32
/// bits, o de punto flotante de 32.
WavInfo readWavInfo(RandomAccessFile file) {
  final length = file.lengthSync();
  file.setPositionSync(0);
  final head = file.readSync(12);
  if (head.length < 12 ||
      String.fromCharCodes(head.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(head.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('no es un WAV');
  }
  int? rate;
  int? channels;
  PcmEncoding? encoding;
  var position = 12;
  while (position + 8 <= length) {
    file.setPositionSync(position);
    final chunk = file.readSync(8);
    final id = String.fromCharCodes(chunk.sublist(0, 4));
    final size = ByteData.sublistView(chunk).getUint32(4, Endian.little);
    final body = position + 8;
    if (id == 'fmt ') {
      final fmt = ByteData.sublistView(file.readSync(math.min(size, 16)));
      if (fmt.lengthInBytes < 16) throw const FormatException('fmt corto');
      final format = fmt.getUint16(0, Endian.little);
      channels = fmt.getUint16(2, Endian.little);
      rate = fmt.getUint32(4, Endian.little);
      final bits = fmt.getUint16(14, Endian.little);
      // 0xFFFE es «extensible»: el formato de verdad va más adelante, pero
      // con 16 o 32 bits enteros es PCM en la práctica.
      encoding = switch ((format, bits)) {
        (1 || 0xFFFE, 16) => PcmEncoding.int16,
        (1 || 0xFFFE, 8) => PcmEncoding.uint8,
        (1 || 0xFFFE, 32) => PcmEncoding.int32,
        (3, 32) => PcmEncoding.float32,
        _ => throw FormatException('formato $format de $bits bits'),
      };
    } else if (id == 'data') {
      if (rate == null || channels == null || encoding == null) {
        throw const FormatException('data antes que fmt');
      }
      if (channels < 1 || rate < 1) {
        throw const FormatException('sin canales ni frecuencia');
      }
      // Un motor que se cortó a mitad deja un tamaño de más: vale lo que hay.
      final available = math.min(size, length - body);
      final frame = channels * encoding.bytesPerSample;
      return WavInfo(
        sampleRate: rate,
        channels: channels,
        encoding: encoding,
        dataOffset: body,
        dataLength: available - available % frame,
      );
    }
    // Las partes van alineadas a dos bytes.
    position = body + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('sin muestras');
}

/// Un tramo que se arma: su WAV y el silencio que va después.
typedef SpeechClipPart = ({String path, int pauseMs});

/// Lo que se le pide al armado.
class AssembleSpeechJob {
  const AssembleSpeechJob({required this.parts, required this.outputPath});

  final List<SpeechClipPart> parts;
  final String outputPath;
}

/// Lo que quedó armado: dónde empieza cada tramo y cuánto dura todo, en
/// muestras a [kSpeechAudioSampleRate].
class AssembledSpeech {
  const AssembledSpeech({required this.starts, required this.samples});

  final List<int> starts;
  final int samples;
}

/// Arma [job]: cada tramo, sin el silencio que el motor dejó en sus bordes
/// —salvo [kSpeechEdgeMargin]—, llevado a [kSpeechAudioSampleRate] y mono;
/// después, exactamente su pausa. Así, entre dos tramos suena el silencio que
/// se pidió (300, 550 o 1.200 ms en un podcast), y no ese más el que cada
/// motor pone por su cuenta.
///
/// Lee cada tramo entero —uno es una oración o un párrafo, unos cientos de
/// kilobytes— y escribe por partes. Lanza [FormatException] si un tramo no
/// es un WAV que se sepa leer.
AssembledSpeech assembleSpeechWav(AssembleSpeechJob job) {
  final output = File(job.outputPath).openSync(mode: FileMode.write);
  final writer = _Pcm16Writer(output);
  final starts = <int>[];
  try {
    writer.begin();
    for (final part in job.parts) {
      starts.add(writer.samples);
      final (:rate, :samples) = _readClip(part.path);
      PolyphaseResampler(rate, kSpeechAudioSampleRate)
        ..push(samples, writer.write)
        ..flush(writer.write);
      writer.silence((part.pauseMs * kSpeechAudioSampleRate / 1000).round());
    }
    writer.end(kSpeechAudioSampleRate);
  } finally {
    output.closeSync();
  }
  return AssembledSpeech(starts: starts, samples: writer.samples);
}

/// La frecuencia de [path] y sus muestras, mono, entre -1 y 1 y sin el
/// silencio de los bordes ([trimSpeechSilence]).
({int rate, Float32List samples}) _readClip(String path) {
  final file = File(path).openSync();
  try {
    final info = readWavInfo(file);
    file.setPositionSync(info.dataOffset);
    final bytes = file.readSync(info.dataLength);
    final samples = toMonoSamples(bytes, info.channels, info.encoding);
    return (
      rate: info.sampleRate,
      samples: trimSpeechSilence(samples, info.sampleRate),
    );
  } finally {
    file.closeSync();
  }
}

/// [samples] —a [sampleRate]— sin el silencio de sus bordes, con
/// [kSpeechEdgeMargin] a cada lado (lo que haya, si el tramo empieza o
/// termina sonando). Un tramo todo silencio queda vacío.
Float32List trimSpeechSilence(Float32List samples, int sampleRate) {
  final margin =
      kSpeechEdgeMargin.inMicroseconds *
      sampleRate ~/
      Duration.microsecondsPerSecond;
  var first = 0;
  while (first < samples.length && samples[first].abs() < kSpeechSilenceLevel) {
    first++;
  }
  if (first == samples.length) return Float32List(0);
  var last = samples.length - 1;
  while (samples[last].abs() < kSpeechSilenceLevel) {
    last--;
  }
  final from = math.max(0, first - margin);
  final to = math.min(samples.length, last + 1 + margin);
  return Float32List.sublistView(samples, from, to);
}

/// El WAV armado: mono, 16 bits, con la cabecera de 44 bytes que se completa
/// al final.
class _Pcm16Writer {
  _Pcm16Writer(this._file);

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

  void silence(int count) {
    for (var i = 0; i < count; i++) {
      write(0);
    }
  }

  void end(int sampleRate) {
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
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
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

/// Un WAV mono de 16 bits con [samples] (entre -1 y 1) a [sampleRate]: lo
/// que escriben los motores de mentira de las pruebas, y nada más.
Uint8List encodeMonoWav(List<double> samples, int sampleRate) {
  final data = samples.length * 2;
  final bytes = ByteData(44 + data)
    ..setUint32(0, 0x52494646)
    ..setUint32(4, 36 + data, Endian.little)
    ..setUint32(8, 0x57415645)
    ..setUint32(12, 0x666d7420)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461)
    ..setUint32(40, data, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(
      44 + i * 2,
      (samples[i] * 32767).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

/// Un tramo que un motor dejó en otro formato —el MP3 de una voz de la nube
/// (F47, paso 4)—, ya decodificado por el sistema a PCM crudo en [rawPath]
/// con sus [segments] (`AudioToPcm.kt`): lo escribe en [wavPath] como los
/// demás, mono, de 16 bits y a [kSpeechAudioSampleRate]. Lee de a pedazos.
void writeSpeechWavFromRaw(
  String rawPath,
  List<PcmSegment> segments,
  String wavPath,
) {
  final raw = File(rawPath).openSync();
  final out = File(wavPath).openSync(mode: FileMode.write);
  final writer = _Pcm16Writer(out);
  try {
    writer.begin();
    for (final segment in segments) {
      final frame = segment.channels * segment.encoding.bytesPerSample;
      final resampler = PolyphaseResampler(
        segment.sampleRate,
        kSpeechAudioSampleRate,
      );
      var done = 0;
      raw.setPositionSync(segment.offset);
      while (done < segment.length) {
        final take = math.min(frame * 8192, segment.length - done);
        final bytes = raw.readSync(take - take % frame);
        if (bytes.isEmpty) break;
        done += bytes.length;
        resampler.push(
          toMonoSamples(bytes, segment.channels, segment.encoding),
          writer.write,
        );
      }
      resampler.flush(writer.write);
    }
    writer.end(kSpeechAudioSampleRate);
  } finally {
    out.closeSync();
    raw.closeSync();
  }
}

/// Si [path] empieza como un WAV (`RIFF…WAVE`).
bool isWavFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return false;
  final raf = file.openSync();
  try {
    final head = raf.readSync(12);
    return head.length == 12 &&
        String.fromCharCodes(head.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(head.sublist(8, 12)) == 'WAVE';
  } finally {
    raf.closeSync();
  }
}
