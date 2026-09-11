import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/archive/html_page_archiver.dart';
import 'package:sinapsis/features/transform/domain/clients/resource_fetcher.dart';

import '../../../../support/sample_files.dart';
import '../../../../support/transform_test_doubles.dart';

void main() {
  final baseUri = Uri.parse('https://ejemplo.org/articulo');
  final png = withSignature([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  HtmlPageArchiver build(ResourceFetcher fetcher) =>
      HtmlPageArchiver(fetcher: fetcher);

  Future<String> archiveToString(
    HtmlPageArchiver archiver,
    String html, {
    Uri? uri,
  }) async {
    final bytes = await archiver.archive(html, baseUri: uri ?? baseUri);
    return utf8.decode(bytes!);
  }

  group('imágenes', () {
    test('se incrustan como dato cuando el recurso se puede traer', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {'https://ejemplo.org/foto.png': png},
      );
      final archiver = build(fetcher);

      final result = await archiveToString(
        archiver,
        '<html><body><img src="foto.png"></body></html>',
      );

      expect(result, contains('src="data:image/png;base64,'));
      expect(result, isNot(contains('foto.png')));
    });

    test('la URL relativa se resuelve contra la página', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {'https://ejemplo.org/img/foto.png': png},
      );
      final archiver = build(fetcher);

      await archiveToString(
        archiver,
        '<html><body><img src="img/foto.png"></body></html>',
      );

      expect(
        fetcher.requested,
        contains(Uri.parse('https://ejemplo.org/img/foto.png')),
      );
    });

    test('si no se puede traer, la imagen sigue apuntando afuera', () async {
      // Sin esto, cualquier imagen rota tumbaría el archivado entero.
      final archiver = build(FakeResourceFetcher());

      final result = await archiveToString(
        archiver,
        '<html><body><img src="https://ejemplo.org/rota.png"></body></html>',
      );

      expect(result, contains('src="https://ejemplo.org/rota.png"'));
    });

    test('un tipo de recurso que no se reconoce no se incrusta', () async {
      final basura = Uint8List.fromList(utf8.encode('no soy una imagen'));
      final fetcher = FakeResourceFetcher(
        byUrl: {'https://ejemplo.org/rara.xyz': basura},
      );
      final archiver = build(fetcher);

      final result = await archiveToString(
        archiver,
        '<html><body><img src="rara.xyz"></body></html>',
      );

      expect(result, contains('src="rara.xyz"'));
    });

    test('una imagen que ya viene como dato no se vuelve a pedir', () async {
      final fetcher = FakeResourceFetcher();
      final archiver = build(fetcher);

      await archiveToString(
        archiver,
        '<html><body><img src="data:image/png;base64,QUJD"></body></html>',
      );

      expect(fetcher.requested, isEmpty);
    });
  });

  group('tamaño', () {
    test('un recurso más grande que el tope no se incrusta', () async {
      // Un byte de más ya alcanza para superar el tope: no hace falta un
      // archivo pesado de verdad para probar la comparación.
      final fetcher = FakeResourceFetcher(
        byUrl: {'https://ejemplo.org/grande.png': png},
      );
      final archiver = HtmlPageArchiver(
        fetcher: fetcher,
        maxResourceBytes: png.length - 1,
      );

      final result = await archiveToString(
        archiver,
        '<html><body><img src="grande.png"></body></html>',
      );

      expect(result, contains('src="grande.png"'));
    });

    test('agotado el tope total, lo que sigue se deja sin incrustar', () async {
      // El tope solo deja lugar para una de las dos imágenes: la primera se
      // incrusta y agota el presupuesto; a la segunda no le queda nada.
      final fetcher = FakeResourceFetcher(
        byUrl: {
          'https://ejemplo.org/una.png': png,
          'https://ejemplo.org/otra.png': png,
        },
      );
      final archiver = HtmlPageArchiver(
        fetcher: fetcher,
        maxTotalBytes: png.length,
      );

      final result = await archiveToString(
        archiver,
        '<html><body><img src="una.png"><img src="otra.png"></body></html>',
      );

      expect(result, contains('src="data:image/png;base64,'));
      expect(result, contains('src="otra.png"'));
    });
  });

  group('hojas de estilo enlazadas', () {
    test(
      'el <link> se reemplaza por un <style> con el CSS incrustado',
      () async {
        final fetcher = FakeResourceFetcher(
          byUrl: {
            'https://ejemplo.org/tema.css': utf8.encode('body{color:red}'),
          },
        );
        final archiver = build(fetcher);

        final result = await archiveToString(
          archiver,
          '<html><head><link rel="stylesheet" href="tema.css"></head> '
          '<body></body></html>',
        );

        expect(result, isNot(contains('<link')));
        expect(result, contains('<style>body{color:red}</style>'));
      },
    );

    test('las url() de la hoja se resuelven contra la hoja, no contra la '
        'página', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {
          'https://ejemplo.org/css/tema.css': utf8.encode(
            "body{background:url('fondo.png')}",
          ),
          'https://ejemplo.org/css/fondo.png': png,
        },
      );
      final archiver = build(fetcher);

      await archiveToString(
        archiver,
        '<html><head><link rel="stylesheet" href="css/tema.css"></head> '
        '<body></body></html>',
      );

      expect(
        fetcher.requested,
        contains(Uri.parse('https://ejemplo.org/css/fondo.png')),
      );
    });

    test('si la hoja no se puede traer, el <link> queda tal cual', () async {
      final archiver = build(FakeResourceFetcher());

      final result = await archiveToString(
        archiver,
        '<html><head><link rel="stylesheet" href="tema.css"></head> '
        '<body></body></html>',
      );

      expect(result, contains('<link rel="stylesheet" href="tema.css">'));
    });

    test('un <link> que no es de hoja de estilos no se toca', () async {
      final fetcher = FakeResourceFetcher();
      final archiver = build(fetcher);

      final result = await archiveToString(
        archiver,
        '<html><head><link rel="icon" href="favicon.ico"></head> '
        '<body></body></html>',
      );

      expect(result, contains('<link rel="icon" href="favicon.ico">'));
      expect(fetcher.requested, isEmpty);
    });
  });

  group('estilos en línea', () {
    test(
      'las url() de un <style> se incrustan, resueltas contra la página',
      () async {
        final fetcher = FakeResourceFetcher(
          byUrl: {'https://ejemplo.org/fondo.png': png},
        );
        final archiver = build(fetcher);

        final result = await archiveToString(
          archiver,
          "<html><head><style>body{background:url('fondo.png')}</style>"
          '</head><body></body></html>',
        );

        expect(result, contains("url('data:image/png;base64,"));
      },
    );

    test('la misma URL repetida dos veces se pide una sola vez', () async {
      final fetcher = FakeResourceFetcher(
        byUrl: {'https://ejemplo.org/fondo.png': png},
      );
      final archiver = build(fetcher);

      await archiveToString(
        archiver,
        '<html><head><style> '
        "a{background:url('fondo.png')} b{background:url('fondo.png')} "
        '</style></head><body></body></html>',
      );

      expect(
        fetcher.requested.where((u) => u.path == '/fondo.png'),
        hasLength(1),
      );
    });
  });

  group('robustez', () {
    test('un recurso que lanza en vez de fallar en silencio no tumba el '
        'archivado entero', () async {
      // El contrato de ResourceFetcher es no lanzar nunca, pero una
      // implementación con un error propio es exactamente lo que este
      // resguardo existe para cubrir.
      final fetcher = _ThrowingResourceFetcher();
      final archiver = build(fetcher);

      final bytes = await archiver.archive(
        '<html><body><img src="foto.png"></body></html>',
        baseUri: baseUri,
      );

      expect(bytes, isNull);
    });

    test('sin ningún recurso, el HTML se devuelve igual', () async {
      final archiver = build(FakeResourceFetcher());

      final result = await archiveToString(
        archiver,
        '<html><body><p>Solo texto.</p></body></html>',
      );

      expect(result, contains('Solo texto.'));
    });
  });
}

class _ThrowingResourceFetcher implements ResourceFetcher {
  @override
  Future<Uint8List?> fetchBytes(Uri url) => throw StateError('roto');
}
