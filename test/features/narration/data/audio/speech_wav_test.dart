import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/audio/speech_wav.dart';
import 'package:sinapsis/features/transform/data/services/pcm_resampler.dart';

/// F47, pasos 5 y 6: el armado del audio de tramos —leer el WAV de cada
/// motor, recortar sus silencios, llevarlo a 24 kHz y poner exactamente la
/// pausa pedida—.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('wav'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, Uint8List bytes) {
    final path = p.join(dir.path, name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// [ms] de un tono a [rate], con [silenceMs] de silencio antes y después.
  List<double> tone(int rate, int ms, {int silenceMs = 0}) => [
    for (var i = 0; i < rate * silenceMs ~/ 1000; i++) 0,
    for (var i = 0; i < rate * ms ~/ 1000; i++) 0.5,
    for (var i = 0; i < rate * silenceMs ~/ 1000; i++) 0,
  ];

  /// Las muestras de un WAV armado, como enteros.
  Int16List samplesOf(String path) {
    final bytes = File(path).readAsBytesSync();
    return Int16List.sublistView(Uint8List.fromList(bytes.sublist(44)));
  }

  group('readWavInfo', () {
    test('recorre las partes sin suponer 44 bytes: salta LIST y lee fmt y '
        'data', () {
      final plain = encodeMonoWav(tone(22050, 10), 22050);
      // Un LIST de 6 bytes metido entre fmt y data.
      final list = Uint8List.fromList([
        ...'LIST'.codeUnits,
        6,
        0,
        0,
        0,
        ...List.filled(6, 7),
      ]);
      final bytes = Uint8List.fromList([
        ...plain.sublist(0, 36),
        ...list,
        ...plain.sublist(36),
      ]);
      // El tamaño del RIFF no se mira; el de data, sí.
      final file = File(write('list.wav', bytes)).openSync();
      addTearDown(file.closeSync);
      final info = readWavInfo(file);
      expect(info.sampleRate, 22050);
      expect(info.channels, 1);
      expect(info.encoding, PcmEncoding.int16);
      expect(info.dataOffset, 44 + list.length);
      expect(info.dataLength, 220 * 2);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('un data que dice más de lo que hay vale lo que hay, en cuadros '
        'enteros', () {
      final bytes = encodeMonoWav(tone(16000, 10), 16000);
      final cut = Uint8List.fromList(bytes.sublist(0, bytes.length - 3));
      final file = File(write('cortado.wav', cut)).openSync();
      addTearDown(file.closeSync);
      expect(readWavInfo(file).dataLength, 160 * 2 - 4);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('lo que no es un WAV que se sepa leer, con FormatException', () {
      final notWav = File(
        write('x.wav', Uint8List.fromList([1, 2, 3])),
      ).openSync();
      addTearDown(notWav.closeSync);
      expect(() => readWavInfo(notWav), throwsFormatException);

      final bytes = encodeMonoWav(tone(16000, 5), 16000);
      // 24 bits.
      ByteData.sublistView(bytes).setUint16(34, 24, Endian.little);
      final deep = File(write('24.wav', bytes)).openSync();
      addTearDown(deep.closeSync);
      expect(() => readWavInfo(deep), throwsFormatException);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('trimSpeechSilence', () {
    test('saca el silencio de los bordes y deja 40 ms de margen', () {
      final samples = Float32List.fromList(tone(1000, 500, silenceMs: 300));
      final trimmed = trimSpeechSilence(samples, 1000);
      // 500 de tono + 40 de margen a cada lado.
      expect(trimmed.length, 580);
      expect(trimmed.first, 0);
      expect(trimmed[40], 0.5);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('un soplido debajo de -50 dB es silencio; un tramo todo silencio '
        'queda vacío', () {
      expect(
        trimSpeechSilence(Float32List.fromList([0.002, -0.002, 0]), 1000),
        isEmpty,
      );
      // Sin silencio en los bordes, queda entero.
      final loud = Float32List.fromList([0.4, 0.4, 0.4]);
      expect(trimSpeechSilence(loud, 1000), hasLength(3));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  test('arma los tramos a 24 kHz, sin los silencios de cada motor y con '
      'exactamente la pausa pedida; dice dónde empieza cada uno', () {
    // Uno de Kokoro (24 kHz) con 300 ms de silencio de cada lado, y uno de
    // Piper (22.050 Hz) sin silencio.
    final a = write(
      'a.wav',
      encodeMonoWav(tone(24000, 500, silenceMs: 300), 24000),
    );
    final b = write('b.wav', encodeMonoWav(tone(22050, 1000), 22050));
    final out = p.join(dir.path, 'armado.wav');

    final done = assembleSpeechWav(
      AssembleSpeechJob(
        parts: [(path: a, pauseMs: 550), (path: b, pauseMs: 0)],
        outputPath: out,
      ),
    );

    // a: 500 ms + 2 × 40 de margen = 580 ms; después, 550 de pausa.
    const first = 24000 * 580 ~/ 1000;
    const pause = 24000 * 550 ~/ 1000;
    expect(done.starts, [0, first + pause]);
    // b, de 22.050 a 24.000 Hz: un segundo sigue siendo un segundo.
    expect(done.samples - done.starts[1], closeTo(24000, 24));

    final raf = File(out).openSync();
    final info = readWavInfo(raf);
    raf.closeSync();
    expect(info.sampleRate, 24000);
    final samples = samplesOf(out);
    expect(samples.length, done.samples);
    // La pausa es silencio de verdad, y el tramo de antes suena.
    expect(
      samples.sublist(first + 10, first + pause - 10).every((s) => s == 0),
      isTrue,
    );
    expect(samples[first ~/ 2], greaterThan(10000));
    final header = ByteData.sublistView(File(out).readAsBytesSync());
    expect(header.getUint32(40, Endian.little), done.samples * 2);
    expect(header.getUint32(4, Endian.little), 36 + done.samples * 2);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('lo que el sistema decodificó a PCM crudo —el MP3 de una voz de la '
      'nube— queda en un WAV mono de 24 kHz, de cada tramo con su formato', () {
    // 100 ms estéreo de 16 bits a 48 kHz, y 50 ms mono de punto flotante a
    // 24 kHz.
    final stereo = ByteData(4800 * 4);
    for (var i = 0; i < 4800 * 2; i++) {
      stereo.setInt16(i * 2, 16000, Endian.little);
    }
    final float = ByteData(1200 * 4);
    for (var i = 0; i < 1200; i++) {
      float.setFloat32(i * 4, 0.5, Endian.little);
    }
    final raw = write(
      'crudo.pcm',
      Uint8List.fromList([
        ...stereo.buffer.asUint8List(),
        ...float.buffer.asUint8List(),
      ]),
    );
    final out = p.join(dir.path, 'nube.wav');
    writeSpeechWavFromRaw(raw, const [
      PcmSegment(
        offset: 0,
        length: 4800 * 4,
        sampleRate: 48000,
        channels: 2,
        encoding: PcmEncoding.int16,
      ),
      PcmSegment(
        offset: 4800 * 4,
        length: 1200 * 4,
        sampleRate: 24000,
        channels: 1,
        encoding: PcmEncoding.float32,
      ),
    ], out);
    expect(isWavFile(out), isTrue);
    final raf = File(out).openSync();
    final info = readWavInfo(raf);
    raf.closeSync();
    expect(info.sampleRate, 24000);
    expect(info.channels, 1);
    // 100 ms a 24 kHz son 2.400 muestras, y 50 ms, 1.200.
    expect(info.dataLength ~/ 2, closeTo(3600, 4));
    final samples = samplesOf(out);
    expect(samples[1200], closeTo(16000, 200));
    expect(samples[3000], closeTo(16383, 200));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('isWavFile reconoce un WAV por su cabecera, no por su nombre', () {
    expect(isWavFile(write('a.wav', encodeMonoWav([0.1], 8000))), isTrue);
    expect(
      isWavFile(write('b.wav', Uint8List.fromList('ID3abcdefghij'.codeUnits))),
      isFalse,
    );
    expect(isWavFile(p.join(dir.path, 'no-esta.wav')), isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('un tramo que no es un WAV corta el armado con FormatException', () {
    final bad = write('mal.wav', Uint8List.fromList(List.filled(60, 1)));
    expect(
      () => assembleSpeechWav(
        AssembleSpeechJob(
          parts: [(path: bad, pauseMs: 0)],
          outputPath: p.join(dir.path, 'o.wav'),
        ),
      ),
      throwsFormatException,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
