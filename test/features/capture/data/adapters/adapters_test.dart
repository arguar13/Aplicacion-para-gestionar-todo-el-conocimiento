import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/youtube_url.dart';
import 'package:sinapsis/features/capture/data/adapters/plain_text_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/provisional_titles.dart';
import 'package:sinapsis/features/capture/data/adapters/social_post_link_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/web_link_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/youtube_link_adapter.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter_registry.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';

import '../../../../support/fake_id_generator.dart';

void main() {
  final now = DateTime(2026, 9, 11, 10);
  late FakeIdGenerator ids;

  setUp(() {
    ids = FakeIdGenerator();
  });

  PlainTextAdapter plainText() => PlainTextAdapter(ids: ids, clock: () => now);
  WebLinkAdapter webLink() => WebLinkAdapter(ids: ids, clock: () => now);
  YouTubeLinkAdapter youtube() =>
      YouTubeLinkAdapter(ids: ids, clock: () => now);
  SocialPostLinkAdapter socialPost() =>
      SocialPostLinkAdapter(ids: ids, clock: () => now);

  group('CaptureRequest.asUrl', () {
    test('reconoce una dirección http y https', () {
      expect(
        const CaptureRequest.text(rawInput: 'https://ejemplo.org/a').asUrl,
        isNotNull,
      );
      expect(
        const CaptureRequest.text(rawInput: 'http://ejemplo.org/a').asUrl,
        isNotNull,
      );
    });

    test('ignora los espacios de alrededor: una URL pegada suele traer un '
        'salto de línea detrás', () {
      expect(
        const CaptureRequest.text(rawInput: '  https://ejemplo.org/a\n ').asUrl,
        isNotNull,
      );
    });

    test('un texto cualquiera NO es una dirección', () {
      // `Uri.parse` acepta casi cualquier cosa —"hola" es una URI válida con
      // path "hola"— así que sin exigir esquema web media biblioteca de notas
      // terminaría clasificada como páginas.
      expect(const CaptureRequest.text(rawInput: 'hola').asUrl, isNull);
      expect(
        const CaptureRequest.text(rawInput: 'una nota con dos palabras').asUrl,
        isNull,
      );
      expect(const CaptureRequest.text(rawInput: 'ejemplo.org').asUrl, isNull);
    });

    test('otros esquemas tampoco: no son páginas web', () {
      expect(
        const CaptureRequest.text(rawInput: 'mailto:alguien@ejemplo.org').asUrl,
        isNull,
      );
      expect(
        const CaptureRequest.text(rawInput: 'file:///home/a.txt').asUrl,
        isNull,
      );
    });
  });

  group('PlainTextAdapter', () {
    test('acepta cualquier texto: es la red de contención', () {
      const cualquierCosa = CaptureRequest.text(rawInput: 'lo que sea');

      expect(plainText().canHandle(cualquierCosa), isTrue);
    });

    test('NO acepta un archivo', () {
      // Va último en el registro: sin esto se quedaría con los archivos que
      // el adaptador de archivos no llegara a ver, y los guardaría como una
      // nota de texto vacía — perdiendo el archivo.
      final archivo = CaptureRequest.file(
        file: CapturedFile(
          name: 'apunte.pdf',
          bytes: Uint8List.fromList(utf8.encode('%PDF-1.7')),
        ),
      );

      expect(plainText().canHandle(archivo), isFalse);
    });

    test('guarda el texto como contenido y saca el título de la primera '
        'línea', () async {
      final item = await plainText().adapt(
        const CaptureRequest.text(
          rawInput: 'La idea principal\n\nY después el desarrollo.',
        ),
      );

      expect(item.title, 'La idea principal');
      expect(item.source.kind, SourceKind.manualNote);
      expect(item.renditions, hasLength(1));
      expect(item.renditions.single.searchableText, contains('el desarrollo'));
    });

    test(
      'queda listo de entrada: no hay nada que traer ni convertir',
      () async {
        final item = await plainText().adapt(
          const CaptureRequest.text(rawInput: 'una nota'),
        );

        expect(item.processingState, ProcessingState.ready);
        expect(item.isBeingProcessed, isFalse);
      },
    );

    test('no guarda enlace de origen, y no es un dato faltante: el origen es '
        'quien lo escribió', () async {
      final item = await plainText().adapt(
        const CaptureRequest.text(rawInput: 'una nota'),
      );

      expect(item.source.url, isNull);
    });

    test('la forma de contenido apunta al elemento que la contiene', () async {
      final item = await plainText().adapt(
        const CaptureRequest.text(rawInput: 'una nota'),
      );

      final rendition = item.renditions.single as TextRendition;
      expect(rendition.itemId, item.id);
      expect(rendition.isPrimary, isTrue);
    });

    test('un título puesto a mano gana sobre el deducido', () async {
      final item = await plainText().adapt(
        const CaptureRequest.text(
          rawInput: 'La idea principal',
          title: 'Mi propio título',
        ),
      );

      expect(item.title, 'Mi propio título');
    });

    test('un título en blanco no cuenta como título puesto a mano', () async {
      final item = await plainText().adapt(
        const CaptureRequest.text(rawInput: 'La idea principal', title: '   '),
      );

      expect(item.title, 'La idea principal');
    });
  });

  group('WebLinkAdapter', () {
    test('acepta direcciones y rechaza texto', () {
      expect(
        webLink().canHandle(
          const CaptureRequest.text(rawInput: 'https://ejemplo.org/a'),
        ),
        isTrue,
      );
      expect(
        webLink().canHandle(const CaptureRequest.text(rawInput: 'una nota')),
        isFalse,
      );
    });

    test('guarda el enlace y deduce un título legible de la '
        'dirección', () async {
      final item = await webLink().adapt(
        const CaptureRequest.text(
          rawInput:
              'https://ejemplo.org/blog/2019/la-estructura-de-las-revoluciones',
        ),
      );

      expect(item.title, 'La estructura de las revoluciones');
      expect(item.subtitle, 'ejemplo.org');
      expect(item.source.kind, SourceKind.webPage);
      expect(item.source.url, contains('ejemplo.org'));
    });

    test('queda pendiente y sin contenido: traer el artículo es trabajo '
        'posterior', () async {
      // Es lo que hace que capturar sea instantáneo y funcione sin conexión.
      final item = await webLink().adapt(
        const CaptureRequest.text(rawInput: 'https://ejemplo.org/a'),
      );

      expect(item.processingState, ProcessingState.pending);
      expect(item.isBeingProcessed, isTrue);
      expect(item.renditions, isEmpty);
    });
  });

  group('YouTubeLinkAdapter', () {
    test('reconoce las tres formas en que YouTube reparte enlaces', () {
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
      ]) {
        expect(
          youtube().canHandle(CaptureRequest.text(rawInput: url)),
          isTrue,
          reason: 'debería reconocer $url',
        );
      }
    });

    test('extrae el identificador del video de las tres', () {
      expect(
        YouTubeUrl.videoIdOf(
          Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        ),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeUrl.videoIdOf(Uri.parse('https://youtu.be/dQw4w9WgXcQ')),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeUrl.videoIdOf(
          Uri.parse('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        ),
        'dQw4w9WgXcQ',
      );
    });

    test('un dominio que solo se PARECE a YouTube no cuenta', () {
      // Tratarlo como YouTube haría que la transformación le pidiera
      // subtítulos a un sitio cualquiera.
      expect(
        youtube().canHandle(
          const CaptureRequest.text(
            rawInput: 'https://youtube.ejemplo.com/watch?v=x',
          ),
        ),
        isFalse,
      );
      expect(
        youtube().canHandle(
          const CaptureRequest.text(
            rawInput: 'https://notyoutube.com/watch?v=x',
          ),
        ),
        isFalse,
      );
    });

    test('una página de YouTube sin video tampoco: no hay nada que '
        'capturar', () {
      expect(
        youtube().canHandle(
          const CaptureRequest.text(rawInput: 'https://www.youtube.com/'),
        ),
        isFalse,
      );
      expect(
        youtube().canHandle(
          const CaptureRequest.text(
            rawInput: 'https://www.youtube.com/@uncanal',
          ),
        ),
        isFalse,
      );
    });

    test('lo marca como video y lo deja pendiente de transcripción', () async {
      final item = await youtube().adapt(
        const CaptureRequest.text(
          rawInput: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
      );

      expect(item.source.kind, SourceKind.youtube);
      expect(item.processingState, ProcessingState.pending);
      expect(item.title, contains('dQw4w9WgXcQ'));
    });
  });

  group('SocialPostLinkAdapter', () {
    test('reconoce videos y reels de TikTok', () {
      for (final url in [
        'https://www.tiktok.com/@alguien/video/7123456789012345678',
        'https://vm.tiktok.com/ZMabcdefg/',
      ]) {
        expect(
          socialPost().canHandle(CaptureRequest.text(rawInput: url)),
          isTrue,
          reason: 'debería reconocer $url',
        );
      }
    });

    test('reconoce reels, publicaciones e IGTV de Instagram', () {
      for (final url in [
        'https://www.instagram.com/reel/Cabcdefghij/',
        'https://www.instagram.com/p/Cabcdefghij/',
        'https://www.instagram.com/tv/Cabcdefghij/',
      ]) {
        expect(
          socialPost().canHandle(CaptureRequest.text(rawInput: url)),
          isTrue,
          reason: 'debería reconocer $url',
        );
      }
    });

    test('el perfil de un usuario no cuenta: no hay una sola publicación '
        'que raspar', () {
      expect(
        socialPost().canHandle(
          const CaptureRequest.text(
            rawInput: 'https://www.instagram.com/alguien/',
          ),
        ),
        isFalse,
      );
    });

    test('un dominio ajeno no cuenta', () {
      expect(
        socialPost().canHandle(
          const CaptureRequest.text(rawInput: 'https://ejemplo.org/video/1'),
        ),
        isFalse,
      );
    });

    test('lo marca como publicación social y lo deja pendiente', () async {
      final item = await socialPost().adapt(
        const CaptureRequest.text(
          rawInput: 'https://www.tiktok.com/@alguien/video/123',
        ),
      );

      expect(item.source.kind, SourceKind.socialPost);
      expect(item.processingState, ProcessingState.pending);
    });
  });

  group('SourceAdapterRegistry', () {
    SourceAdapterRegistry buildRegistry() =>
        SourceAdapterRegistry([youtube(), webLink(), plainText()]);

    test('un enlace de YouTube va al adaptador específico, no al genérico', () {
      // Los dos lo aceptarían; el orden de la lista decide, y tiene que
      // ganar el que sabe más.
      final adapter = buildRegistry().resolve(
        const CaptureRequest.text(
          rawInput: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
      );

      expect(adapter, isA<YouTubeLinkAdapter>());
    });

    test('otra dirección va al genérico', () {
      final adapter = buildRegistry().resolve(
        const CaptureRequest.text(rawInput: 'https://ejemplo.org/a'),
      );

      expect(adapter, isA<WebLinkAdapter>());
    });

    test('lo que nadie reconoce termina como nota, no como error', () {
      final adapter = buildRegistry().resolve(
        const CaptureRequest.text(rawInput: 'algo que no es un enlace'),
      );

      expect(adapter, isA<PlainTextAdapter>());
    });
  });

  group('títulos provisionales', () {
    test('de una dirección, el último tramo del camino', () {
      expect(
        titleFromUrl(Uri.parse('https://ejemplo.org/blog/mi-articulo')),
        'Mi articulo',
      );
    });

    test('quitando la extensión', () {
      expect(
        titleFromUrl(Uri.parse('https://ejemplo.org/textos/ensayo.html')),
        'Ensayo',
      );
    });

    test('si el tramo no dice nada, cae al host', () {
      // Un identificador numérico o una ruta vacía no son un título; el host
      // al menos ubica de dónde salió.
      expect(
        titleFromUrl(Uri.parse('https://ejemplo.org/post/12345')),
        'ejemplo.org',
      );
      expect(titleFromUrl(Uri.parse('https://ejemplo.org/')), 'ejemplo.org');
      expect(titleFromUrl(Uri.parse('https://ejemplo.org')), 'ejemplo.org');
    });

    test('de un texto, su primera línea con contenido', () {
      expect(titleFromText('\n\n  La idea  \nel resto'), 'La idea');
    });

    test('un texto largo se corta sin partir una palabra al medio', () {
      final long = 'palabra ' * 30;
      final title = titleFromText(long, maxLength: 20);

      expect(title.length, lessThanOrEqualTo(21));
      expect(title, endsWith('…'));
      // Se cortó en un espacio, no en mitad de "palabra".
      expect(title, isNot(contains('palab…')));
    });

    test('un texto vacío no produce título', () {
      expect(titleFromText('   \n  '), isEmpty);
    });
  });
}
