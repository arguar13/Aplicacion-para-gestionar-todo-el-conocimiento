// Medición de F22 en el dispositivo: qué tan fiel y qué tan rápida es la
// transcripción de verdad —Whisper (sherpa-onnx) con los tramos cortados en
// pausas y la protección contra bucles— sobre audios reales.
//
// Uso (teléfono con depuración USB). Con el sabor `staging`, NUNCA con el
// que se usa a diario: `flutter drive` desinstala la app antes de
// instalarse, y con ella se iría la bóveda del usuario. `staging` es otra
// app (`app.sinapsis.staging`), con sus propios datos.
//
//   flutter drive --flavor staging --driver test_driver/integration_test.dart \
//     --target integration_test/transcription_fidelity_test.dart \
//     --dart-define=BENCH_DEVICE_INFO="..." --dart-define=BENCH_THREADS=2,4,6
//
// y, cuando la prueba avise que espera los audios (WAV de 16 kHz mono):
//
//   adb shell mkdir -p /sdcard/Android/data/app.sinapsis.staging/files/fidelidad
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

import 'package:audio_decoder/audio_decoder.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/features/transform/data/services/audio_wav_converter.dart';
import 'package:sinapsis/features/transform/data/services/http_whisper_model_manager.dart';
import 'package:sinapsis/features/transform/data/services/sherpa_onnx_audio_transcriber_io.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';

const _deviceInfo = String.fromEnvironment(
  'BENCH_DEVICE_INFO',
  defaultValue: 'dispositivo sin describir',
);

/// Con cuántos hilos transcribir cada audio, separados por coma; `0`, solo
/// medir la conversión.
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
    // A la carpeta privada de la app, como los archivos de la bóveda: la
    // externa (`/sdcard`) pasa por una capa de permisos que hace lenta cada
    // lectura chica, y el decodificador lee de a un cuadro de audio.
    final private = Directory(
      p.join((await getTemporaryDirectory()).path, 'fidelidad'),
    )..createSync(recursive: true);
    final pushedAudios =
        folder
            .listSync()
            .whereType<File>()
            .where(
              (file) => const {
                '.wav',
                '.m4a',
                '.mp3',
                '.aac',
                '.ogg',
                '.opus',
                '.mp4',
              }.contains(p.extension(file.path).toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(pushedAudios, isNotEmpty);
    final audios = [
      for (final audio in pushedAudios)
        audio.copySync(p.join(private.path, p.basename(audio.path))),
    ];

    final model = HttpWhisperModelManager(
      dio: Dio(),
      rootDirectory: getApplicationDocumentsDirectory,
    );
    // El modelo, si se empujó con los audios (`fidelidad/modelo/`): así la
    // prueba corre sin internet y en modo profile, donde no se puede copiar
    // nada adentro de la app.
    final pushed = Directory('${folder.path}/modelo');
    if (!await model.isReady() && pushed.existsSync()) {
      final target = Directory(
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          'modelos',
          'whisper-small',
        ),
      )..createSync(recursive: true);
      for (final file in pushed.listSync().whereType<File>()) {
        file.copySync(p.join(target.path, p.basename(file.path)));
      }
    }
    if (!await model.isReady()) {
      final download = Stopwatch()..start();
      await model.download().last;
      report('modelo_whisper', {'ms_descarga': download.elapsedMilliseconds});
    }

    // Lo primero que se mira de cada audio: si convertirlo al formato de
    // Whisper (WAV de 16 kHz, mono) conserva su duración. Si el WAV dura
    // otra cosa que el original, a Whisper le llega el audio estirado o
    // comprimido, y transcribe disparates (F22).
    final seconds = <String, double>{};
    for (final audio in audios) {
      final name = p.basename(audio.path);
      final info = await AudioDecoder.getAudioInfo(audio.path);
      final temp = await getTemporaryDirectory();
      final wav = File('${temp.path}/conversion-$name.wav');
      // El mismo conversor que usa la app al transcribir.
      final conversion = Stopwatch()..start();
      await const PlatformAudioWavConverter().convert(audio.path, wav.path);
      conversion.stop();
      final wavSeconds = (wav.lengthSync() - 44) / 32000;
      wav.deleteSync();
      seconds[audio.path] = info.duration.inMilliseconds / 1000;
      report('conversion_$name', {
        'formato': info.format,
        'hz_declarados': info.sampleRate,
        'canales_declarados': info.channels,
        'segundos_del_original': info.duration.inMilliseconds / 1000,
        'segundos_del_wav': wavSeconds.toStringAsFixed(1),
        'ms_conversion': conversion.elapsedMilliseconds,
      });
    }

    // `BENCH_THREADS=0`: solo la conversión, sin transcribir.
    for (final threads
        in _threads.split(',').map(int.parse).where((threads) => threads > 0)) {
      final transcriber = SherpaOnnxAudioTranscriberIo(
        model: model,
        temporaryDirectory: getTemporaryDirectory,
        threads: threads,
      );
      for (final audio in audios) {
        final name = p.basename(audio.path).replaceAll('.', '_');
        final duration = seconds[audio.path]!;
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
          'segundos_de_audio': duration.round(),
          'hilos': threads,
          'ms_total': clock.elapsedMilliseconds,
          'veces_la_duracion': (clock.elapsedMilliseconds / 1000 / duration)
              .toStringAsFixed(3),
          'extrapolado_1_hora_min':
              (clock.elapsedMilliseconds / 1000 / duration * 60).round(),
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
