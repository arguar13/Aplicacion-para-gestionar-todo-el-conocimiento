import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_http.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_model_backend.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';

RequestOptions get _options => RequestOptions(path: '/x');

DioException _dio(DioExceptionType type, {Object? error}) =>
    DioException(requestOptions: _options, type: type, error: error);

/// Lo que clasifica cada error de la conexión (F39): el «error de conexión»
/// que se veía teniendo buena conexión era todo esto mezclado en uno.
void main() {
  group('cloudFailureOfError', () {
    test('sin conexión: no se pudo ni llegar al proveedor', () {
      expect(
        cloudFailureOfError(
          _dio(
            DioExceptionType.connectionError,
            error: const SocketException('Failed host lookup'),
          ),
        )?.failure,
        CloudModelFailure.network,
      );
      expect(
        cloudFailureOfError(
          _dio(
            DioExceptionType.unknown,
            error: const SocketException('Network is unreachable'),
          ),
        )?.failure,
        CloudModelFailure.network,
      );
    });

    test('la espera vencida, distinguida de la falta de red', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final failure = cloudFailureOfError(_dio(type));
        expect(failure?.failure, CloudModelFailure.timeout, reason: '$type');
        expect(failure?.detail, type.name);
      }
    });

    test('el silencio de la respuesta es una espera vencida', () {
      expect(
        cloudFailureOfError(TimeoutException('callada'))?.failure,
        CloudModelFailure.timeout,
      );
    });

    test('el servidor que cierra antes de las cabeceras es un corte', () {
      expect(
        cloudFailureOfError(
          _dio(
            DioExceptionType.connectionError,
            error: const HttpException(
              'Connection closed before full header was received',
            ),
          ),
        )?.failure,
        CloudModelFailure.cutOff,
      );
    });

    test('un socket que se cae leyendo la respuesta es un corte, no la '
        'falta de internet', () {
      expect(
        cloudFailureOfError(
          const SocketException('Connection reset by peer'),
          inBody: true,
        )?.failure,
        CloudModelFailure.cutOff,
      );
      expect(
        cloudFailureOfError(
          const HttpException('Connection closed while receiving data'),
          inBody: true,
        )?.failure,
        CloudModelFailure.cutOff,
      );
      expect(
        cloudFailureOfError(
          const HandshakeException('se cayó el apretón'),
          inBody: true,
        )?.failure,
        CloudModelFailure.cutOff,
      );
    });

    test('un error que no es de la conexión no se disfraza', () {
      expect(cloudFailureOfError(StateError('un bug')), isNull);
      expect(cloudFailureOfError(ArgumentError('otro')), isNull);
    });

    test('un certificado malo no se cuenta como falta de internet', () {
      expect(
        cloudFailureOfError(_dio(DioExceptionType.badCertificate))?.failure,
        CloudModelFailure.unknown,
      );
    });

    test('un error ya clasificado sale tal cual', () {
      const failure = CloudModelException(CloudModelFailure.blocked);
      expect(identical(cloudFailureOfError(failure), failure), isTrue);
    });
  });

  group('guardedCloudBody', () {
    Stream<Uint8List> body(List<Object> script) async* {
      for (final step in script) {
        if (step is Uint8List) yield step;
        if (step is Error) throw step;
        if (step is Exception) throw step;
      }
    }

    test('deja pasar los bytes', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final out = await guardedCloudBody(
        body([bytes]),
        idle: const Duration(seconds: 1),
      ).toList();
      expect(out.single, bytes);
    });

    test(
      'la conexión que se cae a mitad sale como respuesta cortada',
      () async {
        await expectLater(
          guardedCloudBody(
            body([
              Uint8List.fromList([1]),
              const HttpException('Connection closed while receiving data'),
            ]),
            idle: const Duration(seconds: 1),
          ).toList(),
          throwsA(
            isA<CloudModelException>().having(
              (e) => e.failure,
              'failure',
              CloudModelFailure.cutOff,
            ),
          ),
        );
      },
    );

    test('un socket reseteado a mitad sale como respuesta cortada', () async {
      await expectLater(
        guardedCloudBody(
          body([const SocketException('Connection reset by peer')]),
          idle: const Duration(seconds: 1),
        ).toList(),
        throwsA(
          isA<CloudModelException>().having(
            (e) => e.failure,
            'failure',
            CloudModelFailure.cutOff,
          ),
        ),
      );
    });

    test('un error del programa no se disfraza de la conexión', () async {
      await expectLater(
        guardedCloudBody(
          body([StateError('un bug')]),
          idle: const Duration(seconds: 1),
        ).toList(),
        throwsA(isA<StateError>()),
      );
    });

    test('si se cortó a propósito, termina callado', () async {
      final cancel = CancelToken()..cancel();
      final out = await guardedCloudBody(
        body([const HttpException('Connection closed')]),
        idle: const Duration(seconds: 1),
        cancel: cancel,
      ).toList();
      expect(out, isEmpty);
    });

    test('el silencio vence: espera vencida, no red; y cada pedazo reinicia '
        'la cuenta', () async {
      const idle = Duration(milliseconds: 150);
      final silent = StreamController<Uint8List>();
      final seen = <Uint8List>[];
      final done = Completer<Object?>();
      guardedCloudBody(silent.stream, idle: idle).listen(
        seen.add,
        onError: done.complete,
        onDone: () {
          if (!done.isCompleted) done.complete(null);
        },
      );
      // Llega algo cada 80 ms: más que el silencio permitido en total, pero
      // nunca seguido.
      for (var i = 0; i < 4; i++) {
        silent.add(Uint8List.fromList([i]));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      expect(done.isCompleted, isFalse);
      expect(seen, hasLength(4));

      // Y después se calla.
      expect(
        await done.future,
        isA<CloudModelException>().having(
          (e) => e.failure,
          'failure',
          CloudModelFailure.timeout,
        ),
      );
    });
  });

  group('las esperas', () {
    test('dan margen real a una respuesta larga', () {
      // Más que los 60 s de antes, que vencían en textos largos.
      expect(kCloudFirstByteTimeout, greaterThan(const Duration(minutes: 2)));
      expect(kCloudIdleTimeout, greaterThan(const Duration(minutes: 2)));
    });
  });

  group('retryDelayInMessage', () {
    test('lee lo que dice OpenAI cuando no manda la cabecera', () {
      expect(
        retryDelayInMessage('Rate limit reached. Please try again in 6m0s.'),
        const Duration(minutes: 6),
      );
      expect(
        retryDelayInMessage('Please try again in 1.5s.'),
        const Duration(milliseconds: 1500),
      );
      expect(
        retryDelayInMessage('Please try again in 20ms'),
        const Duration(milliseconds: 20),
      );
      expect(
        retryDelayInMessage('try again in 1h2m3s'),
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
    });

    test('sin tiempo en el mensaje, no inventa uno', () {
      expect(retryDelayInMessage('Rate limit reached.'), isNull);
      expect(retryDelayInMessage(''), isNull);
    });
  });

  group('cloudRetryDelay', () {
    test('se duplica en cada intento', () {
      expect(cloudRetryDelay(1), const Duration(seconds: 3));
      expect(cloudRetryDelay(2), const Duration(seconds: 6));
      expect(cloudRetryDelay(3), const Duration(seconds: 12));
    });

    test('el jitter va de -25 % a +25 %', () {
      expect(cloudRetryDelay(1, jitter: 0), const Duration(milliseconds: 2250));
      expect(cloudRetryDelay(1, jitter: 1), const Duration(milliseconds: 3750));
    });

    test('no pasa del tope', () {
      expect(cloudRetryDelay(10, jitter: 1), kCloudRetryCap);
    });
  });
}
