import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/recording_check.dart';

const _rate = 8000;

/// Una grabación de mentira: [voiced] segundos de «voz» —un tono a
/// [voiceAmplitude], de a 0,7 s con 0,3 s de pausa— sobre un ruido parejo de
/// [noiseAmplitude], hasta [total] segundos.
Int16List _recording({
  required double total,
  required double voiced,
  double voiceAmplitude = 0.3,
  double noiseAmplitude = 0.001,
  bool clip = false,
}) {
  final random = math.Random(7);
  final samples = Int16List((total * _rate).round());
  var spoken = 0;
  final voicedSamples = (voiced * _rate).round();
  for (var i = 0; i < samples.length; i++) {
    final inWord = (i % _rate) < _rate * 0.7;
    var value = (random.nextDouble() * 2 - 1) * noiseAmplitude;
    if (inWord && spoken < voicedSamples) {
      value += math.sin(2 * math.pi * 220 * i / _rate) * voiceAmplitude;
      spoken++;
    }
    if (clip && inWord && i % 50 == 0) value = 1;
    samples[i] = (value.clamp(-1.0, 1.0) * 32767).round();
  }
  return samples;
}

Uint8List _wav(
  Int16List samples, {
  int channels = 1,
  int sampleRate = _rate,
  bool extraChunk = false,
}) {
  final data = ByteData(samples.length * 2 * channels);
  for (var i = 0; i < samples.length; i++) {
    for (var c = 0; c < channels; c++) {
      data.setInt16((i * channels + c) * 2, samples[i], Endian.little);
    }
  }
  final list = BytesBuilder();
  void tag(String text) => list.add(text.codeUnits);
  void u32(int value) => list.add(
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
  );
  void u16(int value) => list.add(
    (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List(),
  );
  tag('RIFF');
  u32(0);
  tag('WAVE');
  if (extraChunk) {
    tag('LIST');
    u32(3);
    list.add([1, 2, 3, 0]);
  }
  tag('fmt ');
  u32(16);
  u16(1);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * 2 * channels);
  u16(2 * channels);
  u16(16);
  tag('data');
  u32(data.lengthInBytes);
  list.add(data.buffer.asUint8List());
  return list.toBytes();
}

void main() {
  group('analyzeRecording', () {
    test('un minuto y medio de voz clara sobre silencio: salió bien', () {
      final report = analyzeRecording(
        _recording(total: 100, voiced: 90),
        _rate,
      );
      expect(report.total, const Duration(seconds: 100));
      expect(report.voiced.inSeconds, inInclusiveRange(65, 75));
      expect(report.issues, isEmpty);
      expect(report.usable, isTrue);
      expect(report.worthRepeating, isFalse);
    });

    test('mide la voz por encima del ruido, no el silencio', () {
      final report = analyzeRecording(_recording(total: 90, voiced: 25), _rate);
      // 25 s de voz en 90: la voz son los segundos con tono.
      expect(report.voiced.inSeconds, inInclusiveRange(23, 27));
      expect(report.issues, contains(RecordingIssue.short));
      expect(report.usable, isTrue);
    });

    test('menos de 20 segundos de voz no alcanza', () {
      final report = analyzeRecording(_recording(total: 30, voiced: 10), _rate);
      expect(report.issues, contains(RecordingIssue.tooLittleVoice));
      expect(report.usable, isFalse);
    });

    test('el silencio no es voz', () {
      final report = analyzeRecording(Int16List(_rate * 60), _rate);
      expect(report.voiced, Duration.zero);
      expect(report.issues, [RecordingIssue.tooLittleVoice]);
    });

    test('con ruido de fondo, avisa', () {
      final report = analyzeRecording(
        _recording(total: 90, voiced: 80, noiseAmplitude: 0.05),
        _rate,
      );
      expect(
        report.signalToNoiseDb,
        lessThan(RecordingReport.minimumSignalToNoiseDb),
      );
      expect(report.issues, contains(RecordingIssue.noisy));
      expect(report.usable, isTrue);
    });

    test('la voz baja, avisa', () {
      final report = analyzeRecording(
        _recording(
          total: 90,
          voiced: 80,
          voiceAmplitude: 0.01,
          noiseAmplitude: 0.0001,
        ),
        _rate,
      );
      expect(report.issues, contains(RecordingIssue.quiet));
    });

    test('si satura, avisa', () {
      final report = analyzeRecording(
        _recording(total: 90, voiced: 80, clip: true),
        _rate,
      );
      expect(report.clippedRatio, greaterThan(RecordingReport.maxClippedRatio));
      expect(report.issues, contains(RecordingIssue.clipping));
    });

    test('más de 5 minutos no se usa', () {
      final report = analyzeRecording(
        _recording(total: 310, voiced: 120),
        _rate,
      );
      expect(report.issues, contains(RecordingIssue.tooLong));
      expect(report.usable, isFalse);
    });

    test('vuelve igual de su JSON', () {
      final report = analyzeRecording(_recording(total: 70, voiced: 60), _rate);
      final back = RecordingReport.fromJson(report.toJson())!;
      expect(back.total, report.total);
      expect(back.voiced, report.voiced);
      expect(back.noiseDb, report.noiseDb);
      expect(back.voiceDb, report.voiceDb);
      expect(back.clippedRatio, report.clippedRatio);
      expect(RecordingReport.fromJson({'totalMs': 1}), isNull);
    });
  });

  group('PcmWav', () {
    test('lee un WAV con un bloque de más antes de `fmt `', () {
      final samples = Int16List.fromList([0, 1000, -1000, 32767]);
      final wav = PcmWav.parse(_wav(samples, extraChunk: true));
      expect(wav.sampleRate, _rate);
      expect(wav.samples, samples);
    });

    test('junta dos canales en uno', () {
      final samples = Int16List.fromList([100, 200]);
      final wav = PcmWav.parse(_wav(samples, channels: 2));
      expect(wav.samples, samples);
    });

    test('lo que no es un WAV PCM de 16 bits no se lee', () {
      expect(
        () => PcmWav.parse(Uint8List.fromList('no es audio'.codeUnits)),
        throwsFormatException,
      );
      final float = _wav(Int16List(4));
      // El formato 3 es coma flotante.
      ByteData.sublistView(float).setUint16(20, 3, Endian.little);
      expect(() => PcmWav.parse(float), throwsFormatException);
    });
  });
}
