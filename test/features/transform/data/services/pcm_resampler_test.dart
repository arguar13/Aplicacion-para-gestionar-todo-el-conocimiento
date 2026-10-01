import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/services/pcm_resampler.dart';

/// El paso de PCM crudo al WAV de Whisper (F22): la duración exacta, sin
/// ruido plegado, con cualquier formato que entregue el decodificador.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pcm'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// [seconds] de un tono de [hz] a [rate], en 16 bits, con [channels]
  /// canales iguales.
  Uint8List tone(double hz, int rate, double seconds, {int channels = 1}) {
    final frames = (rate * seconds).round();
    final data = ByteData(frames * channels * 2);
    for (var i = 0; i < frames; i++) {
      final v = (0.5 * math.sin(2 * math.pi * hz * i / rate) * 32767).round();
      for (var c = 0; c < channels; c++) {
        data.setInt16((i * channels + c) * 2, v, Endian.little);
      }
    }
    return data.buffer.asUint8List();
  }

  /// Escribe [raw] y lo convierte; devuelve las muestras del WAV.
  Float32List convert(Uint8List raw, List<PcmSegment> segments) {
    final rawFile = File('${temp.path}/crudo.pcm')..writeAsBytesSync(raw);
    final wav = '${temp.path}/salida.wav';
    writeWhisperWav(rawFile.path, segments, wav);
    final bytes = File(wav).readAsBytesSync();
    final data = ByteData.sublistView(bytes, 44);
    return Float32List.fromList([
      for (var i = 0; i + 1 < data.lengthInBytes; i += 2)
        data.getInt16(i, Endian.little) / 32768,
    ]);
  }

  /// La amplitud de [hz] en [samples] (a 16 kHz), por correlación.
  double amplitudeAt(Float32List samples, double hz) {
    var re = 0.0;
    var im = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final a = 2 * math.pi * hz * i / 16000;
      re += samples[i] * math.cos(a);
      im += samples[i] * math.sin(a);
    }
    return 2 * math.sqrt(re * re + im * im) / samples.length;
  }

  PcmSegment segment(
    int length,
    int rate, {
    int channels = 1,
    int offset = 0,
    PcmEncoding encoding = PcmEncoding.int16,
  }) => PcmSegment(
    offset: offset,
    length: length,
    sampleRate: rate,
    channels: channels,
    encoding: encoding,
  );

  test('de 44,1 kHz estéreo: la duración exacta, y un tono que se oye pasa '
      'entero', () {
    final raw = tone(1000, 44100, 2, channels: 2);
    final out = convert(raw, [segment(raw.length, 44100, channels: 2)]);

    expect(out.length, 32000);
    expect(amplitudeAt(out.sublist(2000, 30000), 1000), closeTo(0.5, 0.01));
  });

  test('lo que no entra en 16 kHz desaparece: no vuelve como ruido', () {
    // 10 kHz está por encima de los 8 kHz que caben en 16 kHz; una
    // interpolación lineal lo devolvía plegado en 6 kHz.
    final raw = tone(10000, 44100, 2);
    final out = convert(raw, [segment(raw.length, 44100)]);

    expect(amplitudeAt(out.sublist(2000, 30000), 6000), lessThan(0.001));
  });

  test('el HE-AAC que medía el doble: lo que importa es la frecuencia que '
      'entrega el decodificador, y con ella la duración es la real', () {
    // 44,1 kHz de verdad, aunque el archivo dijera 22,05: el segmento lleva
    // la del decodificador.
    final raw = tone(440, 44100, 3);
    final out = convert(raw, [segment(raw.length, 44100)]);

    expect(out.length / 16000, closeTo(3, 0.001));
  });

  test('ya a 16 kHz mono, pasa tal cual', () {
    final raw = tone(300, 16000, 1);
    final out = convert(raw, [segment(raw.length, 16000)]);

    expect(out.length, 16000);
    expect(
      out[100],
      closeTo(
        ByteData.sublistView(raw).getInt16(200, Endian.little) / 32768,
        1e-4,
      ),
    );
  });

  test('48 kHz en punto flotante, y 8 bits sin signo', () {
    const frames = 48000;
    final floats = ByteData(frames * 4);
    for (var i = 0; i < frames; i++) {
      floats.setFloat32(
        i * 4,
        0.5 * math.sin(2 * math.pi * 1000 * i / 48000),
        Endian.little,
      );
    }
    final f = convert(floats.buffer.asUint8List(), [
      segment(frames * 4, 48000, encoding: PcmEncoding.float32),
    ]);
    expect(f.length, 16000);
    expect(amplitudeAt(f.sublist(1000, 15000), 1000), closeTo(0.5, 0.01));

    final bytes = Uint8List.fromList([
      for (var i = 0; i < 8000; i++)
        (128 + 64 * math.sin(2 * math.pi * 500 * i / 8000)).round(),
    ]);
    final u = convert(bytes, [
      segment(8000, 8000, encoding: PcmEncoding.uint8),
    ]);
    expect(u.length, 16000);
    expect(amplitudeAt(u.sublist(1000, 15000), 500), closeTo(0.5, 0.02));
  });

  test('si el decodificador cambia de formato a mitad de camino, cada tramo '
      'se lee con el suyo', () {
    final first = tone(1000, 22050, 1);
    final second = tone(1000, 44100, 1, channels: 2);
    final out = convert(Uint8List.fromList([...first, ...second]), [
      segment(first.length, 22050),
      segment(second.length, 44100, channels: 2, offset: first.length),
    ]);

    expect(out.length / 16000, closeTo(2, 0.001));
  });

  test('cinco minutos de 44,1 kHz estéreo, en segundos y no en minutos', () {
    final raw = tone(1000, 44100, 300, channels: 2);
    final clock = Stopwatch()..start();
    final out = convert(raw, [segment(raw.length, 44100, channels: 2)]);
    clock.stop();

    expect(out.length, 300 * 16000);
    // Para leer la cifra en la salida de la prueba, no para verificarla.
    // ignore: avoid_print
    print('5 min de 44,1 kHz estéreo: ${clock.elapsedMilliseconds} ms');
    expect(clock.elapsed, lessThan(const Duration(seconds: 30)));
  });
}
