// Medición de F22 en el dispositivo: qué tan fiel y qué tan rápida es la
// transcripción de verdad —Whisper (sherpa-onnx) con los tramos cortados en
// pausas y la protección contra bucles— sobre audios reales.
//
// Uso (teléfono con depuración USB):
//
//   flutter drive --flavor dev --driver test_driver/integration_test.dart \
//     --target integration_test/transcription_fidelity_test.dart \
//     --dart-define=BENCH_DEVICE_INFO="..." --dart-define=BENCH_THREADS=2,4,6
//
// y, cuando la prueba avise que espera los audios (WAV de 16 kHz mono):
//
//   adb shell mkdir -p /sdcard/Android/data/app.sinapsis.dev/files/fidelidad
//   adb push charla.wav alabanza.wav /sdcard/.../files/fidelidad/
//   adb shell touch /sdcard/.../files/fidelidad/listo
//
// Cada audio se transcribe con cada cantidad de hilos de BENCH_THREADS, y el
// texto queda al lado, `<audio>.<hilos>h.txt`, para bajarlo con `adb pull` y
// compararlo en la PC contra una transcripción hecha por personas: la
// diferencia palabra por palabra se cuenta afuera, con las mismas
// herramientas que midieron el plan (docs/planes/F22-fidelidad-del-texto.md).
// La primera vez descarga el modelo de Whisper (unos 375 MB).
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/features/transform/data/services/http_whisper_model_manager.dart';
import 'package:sinapsis/features/transform/data/services/sherpa_onnx_audio_transcriber_io.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';

const _deviceInfo = String.fromEnvironment(
  'BENCH_DEVICE_INFO',
  defaultValue: 'dispositivo sin describir',
);

/// Con cuántos hilos transcribir cada audio, separados por coma.
const _threads = String.fromEnvironment('BENCH_THREADS', defaultValue: '4');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final reports = <String, dynamic>{};

  void report(String name, Map<String, Object?> values) {
    final entry = {'dispositivo': _deviceInfo, ...values};
    debugPrint('F22 $name: $entry');
    reports['f22_$name'] = entry;
    binding.reportData = Map<String, dynamic>.of(reports);
  }

  test('cada audio, con cada cantidad de hilos: tiempo, tramos y huecos, y '
      'el texto al lado para compararlo', () async {
    final external = await getExternalStorageDirectory();
    final folder = Directory('${external?.path}/fidelidad');
    final ready = File('${folder.path}/listo');
    // `flutter drive` desinstala la app antes de instalarla, y con ella se va
    // lo que se haya empujado antes: los audios se empujan con la prueba ya
    // corriendo, y la marca `listo` dice que terminaron de copiarse.
    print('F22 fidelidad: esperando los audios y la marca en ${ready.path}');
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (!ready.existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (!ready.existsSync()) {
      markTestSkipped('Sin la marca ${ready.path}');
      return;
    }
    final audios =
        folder
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.wav'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(audios, isNotEmpty);

    final model = HttpWhisperModelManager(
      dio: Dio(),
      rootDirectory: getApplicationDocumentsDirectory,
    );
    if (!await model.isReady()) {
      final download = Stopwatch()..start();
      await model.download().last;
      report('modelo_whisper', {'ms_descarga': download.elapsedMilliseconds});
    }

    for (final threads in _threads.split(',').map(int.parse)) {
      final transcriber = SherpaOnnxAudioTranscriberIo(
        model: model,
        temporaryDirectory: getTemporaryDirectory,
        threads: threads,
      );
      for (final audio in audios) {
        final name = p.basenameWithoutExtension(audio.path);
        final seconds = (audio.lengthSync() - 44) / 32000;
        final segments = <int>[];

        final clock = Stopwatch()..start();
        final text = await transcriber.transcribe(
          audio.path,
          session: TranscriptionSession(
            saveSegment: (segment, _) async => segments.add(segment),
          ),
        );
        clock.stop();

        File('${folder.path}/$name.${threads}h.txt').writeAsStringSync(text);
        report('${name}_${threads}h', {
          'segundos_de_audio': seconds.round(),
          'hilos': threads,
          'ms_total': clock.elapsedMilliseconds,
          'veces_la_duracion': (clock.elapsedMilliseconds / 1000 / seconds)
              .toStringAsFixed(3),
          'extrapolado_1_hora_min':
              (clock.elapsedMilliseconds / 1000 / seconds * 60).round(),
          'tramos': segments.length,
          'huecos_marcados': RegExp(
            'fragmento no reconocido',
          ).allMatches(text).length,
          'palabras': text.split(RegExp(r'\s+')).length,
        });
      }
    }
  }, timeout: const Timeout(Duration(hours: 3)));
}
