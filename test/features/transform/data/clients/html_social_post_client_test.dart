import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/clients/html_social_post_client.dart';

import '../../../../support/transform_test_doubles.dart';

void main() {
  HtmlSocialPostClient build(String html) =>
      HtmlSocialPostClient(FakeWebPageClient(html: html));

  group('el JSON propio de TikTok', () {
    test('saca el texto, el autor y el video sin marca de agua', () async {
      const html = '''
<html><head></head><body>
<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">
{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"itemInfo":{"itemStruct":{
  "desc":"Un texto con #etiqueta",
  "author":{"uniqueId":"alguien.oficial"},
  "video":{"playAddr":"https://v16.tiktokcdn.com/video/sin-marca.mp4"}
}}}}}
</script>
</body></html>
''';

      final data = await build(
        html,
      ).fetchPost(Uri.parse('https://www.tiktok.com/@alguien/video/123'));

      expect(data.caption, 'Un texto con #etiqueta');
      expect(data.authorName, 'alguien.oficial');
      expect(
        data.videoUrl,
        Uri.parse('https://v16.tiktokcdn.com/video/sin-marca.mp4'),
      );
    });

    test(
      'sin playAddr, saca la carátula del video como foto de respaldo',
      () async {
        const html = '''
<html><head></head><body>
<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">
{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"itemInfo":{"itemStruct":{
  "desc":"Un texto sin video que bajar",
  "author":{"uniqueId":"alguien.oficial"},
  "video":{"originCover":"https://p16.tiktokcdn.com/caratula.jpg"}
}}}}}
</script>
</body></html>
''';

        final data = await build(
          html,
        ).fetchPost(Uri.parse('https://www.tiktok.com/@alguien/video/123'));

        expect(data.videoUrl, isNull);
        expect(
          data.imageUrl,
          Uri.parse('https://p16.tiktokcdn.com/caratula.jpg'),
        );
      },
    );

    test('con playAddr, no se molesta en sacar la carátula', () async {
      const html = '''
<html><head></head><body>
<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">
{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"itemInfo":{"itemStruct":{
  "desc":"Un texto con video",
  "video":{"playAddr":"https://v16.tiktokcdn.com/video.mp4","originCover":"https://p16.tiktokcdn.com/caratula.jpg"}
}}}}}
</script>
</body></html>
''';

      final data = await build(
        html,
      ).fetchPost(Uri.parse('https://www.tiktok.com/@alguien/video/123'));

      expect(data.videoUrl, isNotNull);
      expect(data.imageUrl, isNull);
    });

    test('si el script no está, cae en Open Graph', () async {
      const html = '''
<html><head>
<meta property="og:description" content="Descripción de respaldo">
</head><body></body></html>
''';

      final data = await build(
        html,
      ).fetchPost(Uri.parse('https://www.tiktok.com/@alguien/video/123'));

      expect(data.caption, 'Descripción de respaldo');
    });

    test('si el JSON no tiene la forma esperada, cae en Open Graph en vez '
        'de romperse', () async {
      const html = '''
<html><head>
<meta property="og:description" content="Descripción de respaldo">
</head><body>
<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">
{"algo distinto": "que no tiene el camino esperado"}
</script>
</body></html>
''';

      final data = await build(
        html,
      ).fetchPost(Uri.parse('https://www.tiktok.com/@alguien/video/123'));

      expect(data.caption, 'Descripción de respaldo');
    });
  });

  group('Open Graph, el resguardo universal', () {
    test('saca descripción, título y video de las etiquetas og:', () async {
      const html = '''
<html><head>
<meta property="og:title" content="alguien.oficial">
<meta property="og:description" content="Un reel divertido">
<meta property="og:video" content="https://instagram.com/video.mp4">
</head><body></body></html>
''';

      final data = await build(
        html,
      ).fetchPost(Uri.parse('https://www.instagram.com/reel/abc123/'));

      expect(data.authorName, 'alguien.oficial');
      expect(data.caption, 'Un reel divertido');
      expect(data.videoUrl, Uri.parse('https://instagram.com/video.mp4'));
    });

    test('sin video, saca la foto de og:image', () async {
      const html = '''
<html><head>
<meta property="og:title" content="alguien.oficial">
<meta property="og:description" content="Una foto sola, sin video">
<meta property="og:image" content="https://instagram.com/foto.jpg">
</head><body></body></html>
''';

      final data = await build(
        html,
      ).fetchPost(Uri.parse('https://www.instagram.com/p/abc123/'));

      expect(data.videoUrl, isNull);
      expect(data.imageUrl, Uri.parse('https://instagram.com/foto.jpg'));
    });

    test('con video, no se molesta en sacar og:image', () async {
      const html = '''
<html><head>
<meta property="og:description" content="Un reel con video">
<meta property="og:video" content="https://instagram.com/video.mp4">
<meta property="og:image" content="https://instagram.com/fotograma.jpg">
</head><body></body></html>
''';

      final data = await build(
        html,
      ).fetchPost(Uri.parse('https://www.instagram.com/reel/abc123/'));

      expect(data.videoUrl, isNotNull);
      expect(data.imageUrl, isNull);
    });

    test('funciona sin importar el orden de los atributos del meta', () async {
      const html = '''
<html><head>
<meta content="Un reel divertido" property="og:description">
</head><body></body></html>
''';

      final data = await build(
        html,
      ).fetchPost(Uri.parse('https://www.instagram.com/reel/abc123/'));

      expect(data.caption, 'Un reel divertido');
    });

    test('desescapa las entidades HTML del atributo', () async {
      const html = '''
<html><head>
<meta property="og:description" content="Tacos &amp; burritos &quot;ricos&quot;">
</head><body></body></html>
''';

      final data = await build(
        html,
      ).fetchPost(Uri.parse('https://www.instagram.com/reel/abc123/'));

      expect(data.caption, 'Tacos & burritos "ricos"');
    });

    test('traduce todas las entidades, no solo un puñado (F22)', () async {
      // Antes se desescapaban seis a mano: "&#233;", "&nbsp;" y "&hellip;"
      // quedaban tal cual en el texto guardado.
      const html = '''
<html><head>
<meta property="og:description" content="Caf&#233;&nbsp;y m&aacute;s&hellip;">
</head><body></body></html>
''';

      final data = await build(
        html,
      ).fetchPost(Uri.parse('https://www.instagram.com/reel/abc123/'));

      expect(data.caption, 'Café y más…');
    });

    test(
      'desescapa una sola vez: "&amp;lt;" es el texto "&lt;" (F22)',
      () async {
        // Con "&amp;" primero en la lista, la segunda pasada lo convertía
        // en "<": otro texto.
        const html = '''
<html><head>
<meta property="og:description" content="Escribí &amp;lt;b&amp;gt; para negrita">
<meta property="og:video" content="https://x.example/v.mp4?a=1&amp;b=%26lt">
</head><body></body></html>
''';

        final data = await build(
          html,
        ).fetchPost(Uri.parse('https://www.instagram.com/reel/abc123/'));

        expect(data.caption, 'Escribí &lt;b&gt; para negrita');
        expect(data.videoUrl, Uri.parse('https://x.example/v.mp4?a=1&b=%26lt'));
      },
    );

    test(
      'og:video:secure_url gana sobre og:video cuando están los dos',
      () async {
        const html = '''
<html><head>
<meta property="og:video" content="http://sin-https.example/video.mp4">
<meta property="og:video:secure_url" content="https://con-https.example/video.mp4">
</head><body></body></html>
''';

        final data = await build(
          html,
        ).fetchPost(Uri.parse('https://www.instagram.com/reel/abc123/'));

        expect(data.videoUrl, Uri.parse('https://con-https.example/video.mp4'));
      },
    );

    test(
      'sin ninguna etiqueta, devuelve todo vacío en vez de fallar',
      () async {
        const html = '<html><head></head><body>nada de nada</body></html>';

        final data = await build(
          html,
        ).fetchPost(Uri.parse('https://www.instagram.com/reel/abc123/'));

        expect(data.caption, isNull);
        expect(data.authorName, isNull);
        expect(data.videoUrl, isNull);
      },
    );
  });
}
