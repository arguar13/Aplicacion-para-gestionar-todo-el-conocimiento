// Mediciones de F21 en el dispositivo: lo que no se puede probar en el PC
// porque depende de motores nativos de Android —ML Kit para las páginas
// escaneadas, Whisper (sherpa-onnx) para transcribir, el servicio en primer
// plano—.
//
// Uso (emulador o teléfono con depuración USB):
//
//   flutter drive --flavor dev --driver test_driver/integration_test.dart \
//     --target integration_test/processing_benchmark_test.dart \
//     --dart-define=BENCH_DEVICE_INFO="..."
//
// y, cuando la prueba avise que espera el audio (un WAV con voz):
//
//   adb shell mkdir -p /sdcard/Android/data/app.sinapsis.dev/files/bench
//   adb push voz.wav /sdcard/Android/data/app.sinapsis.dev/files/bench/voz.wav
//
// Sin el audio, la parte de la transcripción se salta con motivo.
// La primera vez descarga el modelo de Whisper (unos 375 MB).
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/core/storage/local_file_store.dart';
import 'package:sinapsis/features/transform/data/documents/pdf_parser.dart';
import 'package:sinapsis/features/transform/data/services/http_whisper_model_manager.dart';
import 'package:sinapsis/features/transform/data/services/method_channel_long_work_platform.dart';
import 'package:sinapsis/features/transform/data/services/ml_kit_image_text_extractor.dart';
import 'package:sinapsis/features/transform/data/services/sherpa_onnx_audio_transcriber_io.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/domain/transformers/transform_context.dart';

import '../test/support/sample_files.dart';
import '../test/support/silent_logger.dart';

const _deviceInfo = String.fromEnvironment(
  'BENCH_DEVICE_INFO',
  defaultValue: 'dispositivo sin describir',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final reports = <String, dynamic>{};

  void report(String name, Map<String, Object?> values) {
    final entry = {'dispositivo': _deviceInfo, ...values};
    debugPrint('F21 $name: $entry');
    reports['f21_$name'] = entry;
    binding.reportData = Map<String, dynamic>.of(reports);
  }

  int rssMb() => ProcessInfo.currentRss ~/ (1024 * 1024);

  test('páginas escaneadas: por página, con avance, guardadas y '
      'retomables', () async {
    const pageCount = 20;
    final temp = await getTemporaryDirectory();
    final files = LocalFileStore(rootDirectory: () async => temp);
    final pdf = File('${temp.path}/escaneado.pdf')
      ..writeAsBytesSync(
        buildPdf(
          pageTexts: List.filled(pageCount, ''),
          scannedPages: {for (var i = 0; i < pageCount; i++) i},
        ),
      );
    final source = DocumentSource(
      name: 'escaneado.pdf',
      size: pdf.lengthSync(),
      localPath: pdf.path,
      readAll: pdf.readAsBytes,
      readRange: (start, length) async {
        final handle = await pdf.open();
        try {
          await handle.setPosition(start);
          return await handle.read(length);
        } finally {
          await handle.close();
        }
      },
    );
    final parser = PdfParser(
      ocrExtractor: const MlKitImageTextExtractor(),
      ocrFileStore: files,
    );

    final saved = <int, String>{};
    final context = _RecordingContext();
    final rssBefore = rssMb();
    final all = Stopwatch()..start();
    final result = await parser.parse(
      source,
      session: DocumentParseSession(
        context: context,
        saveRecognizedPage: (page, text) async => saved[page] = text,
      ),
    );
    all.stop();

    expect(result.pageCount, pageCount);
    expect(context.enteredLongLane, isTrue);
    expect(saved.keys, hasLength(pageCount));
    expect(context.progress.last, (pageCount, pageCount));

    // Retomar desde la mitad: solo se reconoce lo que falta.
    final half = {for (var i = 0; i < pageCount ~/ 2; i++) i: 'ya estaba'};
    final resumed = Stopwatch()..start();
    await parser.parse(
      source,
      session: DocumentParseSession(loadRecognizedPages: () async => half),
    );
    resumed.stop();

    report('ocr_paginas', {
      'paginas': pageCount,
      'ms_total': all.elapsedMilliseconds,
      'ms_por_pagina': all.elapsedMilliseconds ~/ pageCount,
      'ms_retomando_desde_la_mitad': resumed.elapsedMilliseconds,
      'rss_mb_antes': rssBefore,
      'rss_mb_despues': rssMb(),
    });
  }, timeout: const Timeout(Duration(minutes: 15)));

  test('transcripción por tramos, con avance, guardada y retomable', () async {
    final external = await getExternalStorageDirectory();
    // `flutter drive` desinstala la app antes de instalarla, y con ella se va
    // lo que se haya empujado antes: el audio se empuja con la prueba ya
    // corriendo, y acá se lo espera un rato.
    final audio = File('${external?.path}/bench/voz.wav');
    print('F21 transcripcion: esperando el audio en ${audio.path}');
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (!audio.existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (!audio.existsSync()) {
      markTestSkipped('Sin audio empujado en ${audio.path}');
      return;
    }
    // Que termine de copiarse.
    await Future<void>.delayed(const Duration(seconds: 3));

    final model = HttpWhisperModelManager(
      dio: Dio(),
      rootDirectory: getApplicationDocumentsDirectory,
    );
    if (!await model.isReady()) {
      final download = Stopwatch()..start();
      await model.download().last;
      report('modelo_whisper', {'ms_descarga': download.elapsedMilliseconds});
    }

    final transcriber = SherpaOnnxAudioTranscriberIo(
      model: model,
      temporaryDirectory: getTemporaryDirectory,
    );
    final audioMinutes = (audio.lengthSync() - 44) / 32000 / 60;

    final saved = <int, String>{};
    final context = _RecordingContext();
    var peakRss = rssMb();
    final sampler = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = rssMb();
      if (now > peakRss) peakRss = now;
    });
    final all = Stopwatch()..start();
    final text = await transcriber.transcribe(
      audio.path,
      session: TranscriptionSession(
        context: context,
        workKey: 'bench',
        saveSegment: (segment, text) async => saved[segment] = text,
      ),
    );
    all.stop();
    sampler.cancel();

    expect(text, isNotEmpty);
    expect(saved, isNotEmpty);
    expect(context.progress.last.$1, context.progress.last.$2);

    // Retomar desde la mitad.
    final segments = saved.length;
    final half = {
      for (final entry in saved.entries)
        if (entry.key < segments ~/ 2) entry.key: entry.value,
    };
    final resumed = Stopwatch()..start();
    await transcriber.transcribe(
      audio.path,
      session: TranscriptionSession(
        workKey: 'bench-2',
        loadSegments: () async => half,
      ),
    );
    resumed.stop();

    final minutesPerMinute = all.elapsedMilliseconds / 60000 / audioMinutes;
    report('transcripcion', {
      'minutos_de_audio': audioMinutes.toStringAsFixed(1),
      'tramos': segments,
      'hilos': Platform.numberOfProcessors,
      'ms_total': all.elapsedMilliseconds,
      'minutos_por_minuto_de_audio': minutesPerMinute.toStringAsFixed(2),
      'extrapolado_4_horas_min': (minutesPerMinute * 240).round(),
      'ms_retomando_desde_la_mitad': resumed.elapsedMilliseconds,
      'rss_mb_pico': peakRss,
      'comienzo_del_texto': text.text.substring(
        0,
        text.text.length.clamp(0, 200),
      ),
    });
  }, timeout: const Timeout(Duration(hours: 2)));

  test('servicio en primer plano: aparece con el trabajo y se va al '
      'terminar', () async {
    // Lo comprueba quien corre la medición, desde afuera, en esta ventana:
    //   adb shell dumpsys activity services app.sinapsis.dev
    // Tiene que listar `LongWorkService` en primer plano mientras dura.
    final keeper = LongWorkCoordinator(
      platform: MethodChannelLongWorkPlatform(logger: const SilentLogger()),
    ).keeperFor(LongWorkOwner.processing)..working(done: 1, total: 4);
    print('F21 servicio: EN CURSO durante 30 s');
    await Future<void>.delayed(const Duration(seconds: 30));
    keeper.idle();
    await Future<void>.delayed(const Duration(seconds: 20));
    print('F21 servicio: SOLTADO');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Un contexto de cola que anota lo que le piden.
class _RecordingContext implements TransformContext {
  bool enteredLongLane = false;
  final progress = <(int, int)>[];

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => Completer<void>().future;

  @override
  void throwIfCancelled() {}

  @override
  Future<void> enterLongLane() async => enteredLongLane = true;

  @override
  void reportProgress(int done, int total) => progress.add((done, total));
}
