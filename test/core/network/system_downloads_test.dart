import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/network/system_downloads.dart';

/// El gestor de descargas del sistema por su canal (F29), contra un Android
/// simulado: qué se le pide y cómo se entiende lo que contesta.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.sinapsis/system_downloads');
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) answer;

  setUp(() {
    calls = [];
    answer = (call) => switch (call.method) {
      'directory' => '/storage/emulated/0/Android/data/app.sinapsis/files',
      _ => null,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return answer(call);
        });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('en Android, con el gestor disponible, baja a la carpeta que dice el '
      'sistema', () async {
    final downloads = await MethodChannelSystemDownloads.resolve();

    expect(
      downloads?.directory.path,
      '/storage/emulated/0/Android/data/app.sinapsis/files',
    );
  });

  test(
    'sin el gestor —deshabilitado, sin almacenamiento— baja la app',
    () async {
      answer = (_) => null;

      expect(await MethodChannelSystemDownloads.resolve(), isNull);
    },
  );

  test('fuera de Android ni pregunta', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    expect(await MethodChannelSystemDownloads.resolve(), isNull);
    expect(calls, isEmpty);
  });

  test('pide la descarga con su destino, sus cabeceras y qué es', () async {
    answer = (call) => switch (call.method) {
      'directory' => '/datos',
      'enqueue' => 42,
      _ => null,
    };
    final downloads = (await MethodChannelSystemDownloads.resolve())!;

    final id = await downloads.enqueue(
      url: 'https://huggingface.co/a/b',
      destination: File('/datos/modelos/x.descargando'),
      headers: {'authorization': 'Bearer hf_x'},
      label: 'relations_model',
    );

    expect(id, 42);
    expect(calls.last.arguments, {
      'url': 'https://huggingface.co/a/b',
      'path': File('/datos/modelos/x.descargando').path,
      'headers': {'authorization': 'Bearer hf_x'},
      'label': 'relations_model',
    });
  });

  group('lo que dice el sistema de una descarga', () {
    late SystemDownloads downloads;

    setUp(() async {
      downloads = (await MethodChannelSystemDownloads.resolve())!;
    });

    Future<SystemDownloadState> stateFor(Map<String, Object?> reply) {
      answer = (call) => call.method == 'query' ? reply : null;
      return downloads.query(7);
    }

    test('bajando, con lo que lleva y el total', () async {
      final state = await stateFor({
        'status': 'running',
        'downloaded': 1024,
        'total': 4096,
      });

      expect(state.status, SystemDownloadStatus.running);
      expect(state.downloadedBytes, 1024);
      expect(state.totalBytes, 4096);
    });

    test('un total que el servidor todavía no dijo es nulo', () async {
      final state = await stateFor({
        'status': 'pending',
        'downloaded': 0,
        'total': -1,
      });

      expect(state.totalBytes, isNull);
    });

    test('fallida por el servidor: lo que contestó', () async {
      final state = await stateFor({'status': 'failed', 'httpStatus': 403});

      expect(state.status, SystemDownloadStatus.failed);
      expect(state.httpStatus, 403);
    });

    test('fallida sin lugar', () async {
      final state = await stateFor({
        'status': 'failed',
        'error': 'insufficient_space',
      });

      expect(state.error, SystemDownloadError.insufficientSpace);
    });

    test('fallida por otra cosa', () async {
      final state = await stateFor({'status': 'failed', 'error': 'other_1001'});

      expect(state.error, SystemDownloadError.other);
    });

    test('una que el sistema no conoce', () async {
      final state = await stateFor({'status': 'unknown'});

      expect(state.status, SystemDownloadStatus.unknown);
    });
  });
}
