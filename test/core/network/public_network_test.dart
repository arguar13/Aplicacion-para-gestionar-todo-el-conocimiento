import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/network/public_network.dart';

void main() {
  group('isPublicAddress', () {
    bool public(String ip) => isPublicAddress(InternetAddress(ip));

    test('internet', () {
      expect(public('8.8.8.8'), isTrue);
      expect(public('208.80.154.224'), isTrue); // Wikimedia
      expect(public('2620:0:861:ed1a::1'), isTrue);
    });

    test('el propio equipo y las redes privadas, no', () {
      for (final ip in [
        '127.0.0.1',
        '127.8.9.1',
        '0.0.0.0',
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.255',
        '192.168.1.1',
        '169.254.169.254', // metadatos de la nube
        '100.64.0.1',
        '224.0.0.1',
        '255.255.255.255',
        '::1',
        '::',
        'fe80::1',
        'fd00::1',
        'fc12::1',
        '::ffff:192.168.0.1',
        '::ffff:127.0.0.1',
        '64:ff9b::a00:1', // 10.0.0.1 traducida
      ]) {
        expect(public(ip), isFalse, reason: ip);
      }
    });

    test('los bordes de los rangos', () {
      expect(public('172.15.255.255'), isTrue);
      expect(public('172.32.0.0'), isTrue);
      expect(public('100.63.255.255'), isTrue);
      expect(public('100.128.0.0'), isTrue);
      expect(public('::ffff:8.8.8.8'), isTrue);
    });
  });

  group('resolvePublic', () {
    test('un nombre que resuelve a algo privado no pasa', () async {
      await expectLater(
        resolvePublic(
          'trampa.ejemplo.org',
          lookup: (_) async => [InternetAddress('192.168.0.10')],
        ),
        throwsA(isA<PrivateNetworkException>()),
      );
    });

    test('ni uno que resuelve a una pública Y a una privada', () async {
      await expectLater(
        resolvePublic(
          'mixto.ejemplo.org',
          lookup: (_) async => [
            InternetAddress('8.8.8.8'),
            InternetAddress('127.0.0.1'),
          ],
        ),
        throwsA(isA<PrivateNetworkException>()),
      );
    });

    test('una IP escrita como dirección se comprueba sin resolver', () async {
      await expectLater(
        resolvePublic('127.0.0.1', lookup: (_) => fail('no resuelve')),
        throwsA(isA<PrivateNetworkException>()),
      );
      await expectLater(
        resolvePublic('[::1]', lookup: (_) => fail('no resuelve')),
        throwsA(isA<PrivateNetworkException>()),
      );
    });

    test('lo público pasa', () async {
      final addresses = await resolvePublic(
        'ejemplo.org',
        lookup: (_) async => [InternetAddress('93.184.215.14')],
      );
      expect(addresses.single.address, '93.184.215.14');
    });
  });

  group('createPublicOnlyHttpClient', () {
    late HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        ..listen((request) async {
          request.response.write('secreto de la red local');
          await request.response.close();
        });
    });

    tearDown(() => server.close(force: true));

    test('no llega a conectarse a un servidor del propio equipo', () async {
      final dio = Dio()
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: createPublicOnlyHttpClient,
        );
      final url = 'http://127.0.0.1:${server.port}/';

      // Sin la guarda, el mismo pedido sí llega: la prueba prueba algo.
      final open = await Dio().get<String>(url);
      expect(open.data, 'secreto de la red local');

      await expectLater(
        dio.get<String>(url),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<PrivateNetworkException>(),
          ),
        ),
      );
      await expectLater(
        dio.get<String>('http://localhost:${server.port}/'),
        throwsA(isA<DioException>()),
      );
    });

    test('ni siguiendo una redirección desde afuera', () async {
      // Un servidor "público" de mentira que redirige a la red local: la
      // conexión a la redirección pasa por la misma guarda.
      final redirector = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => redirector.close(force: true));
      redirector.listen((request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set('location', 'http://10.0.0.1:${server.port}/');
        await request.response.close();
      });
      // El primer salto se permite a propósito —para la prueba, el propio
      // equipo cuenta como "internet"—; el segundo va a 10.0.0.1, y no se
      // abre.
      final dio = Dio()
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () => createPublicOnlyHttpClient(
            lookup: (host) async => [InternetAddress('127.0.0.1')],
            isAllowed: (a) => a.isLoopback || isPublicAddress(a),
          ),
        );

      await expectLater(
        dio.get<String>('http://publico.ejemplo.org:${redirector.port}/'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<PrivateNetworkException>().having(
              (e) => e.host,
              'host',
              '10.0.0.1',
            ),
          ),
        ),
      );
    });
  });
}
