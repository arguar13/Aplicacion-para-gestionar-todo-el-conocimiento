import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/transform/data/clients/reader_mode_article_extractor.dart';
import 'package:sinapsis/features/transform/data/transformers/web_article_transformer.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/silent_logger.dart';
import '../../../../support/transform_test_doubles.dart';

void main() {
  final now = DateTime(2026, 9, 11, 10);
  late FakeIdGenerator ids;
  late InMemoryFileStore files;

  setUp(() {
    ids = FakeIdGenerator();
    files = InMemoryFileStore();
  });

  KnowledgeItem webItem({
    List<Rendition> renditions = const [],
    SourceKind kind = SourceKind.webPage,
  }) => KnowledgeItem(
    id: 'item-1',
    // El título provisional que dedujo la captura de la propia dirección.
    title: 'Un articulo interesante',
    subtitle: 'ejemplo.org',
    source: Source(
      id: 'src-1',
      kind: kind,
      capturedAt: now,
      url: 'https://ejemplo.org/blog/un-articulo-interesante',
    ),
    processingState: ProcessingState.pending,
    createdAt: now,
    updatedAt: now,
    renditions: renditions,
  );

  WebArticleTransformer build({
    FakeWebPageClient? client,
    FakeArticleExtractor? extractor,
    FakePageArchiver? archiver,
  }) => WebArticleTransformer(
    client: client ?? FakeWebPageClient(html: '<html></html>'),
    extractor:
        extractor ??
        FakeArticleExtractor(
          article: const ExtractedArticle(
            contentHtml: '<p>El cuerpo del artículo.</p>',
            textContent: 'El cuerpo del artículo.',
          ),
        ),
    // `null` por defecto: la mayoría de las pruebas de acá no le interesa el
    // archivado, y así se comprueba de paso que no archivar nada no le
    // cuesta nada al resto del resultado.
    archiver: archiver ?? FakePageArchiver(),
    files: files,
    ids: ids,
    clock: () => now,
    logger: const SilentLogger(),
  );

  group('a qué se aplica', () {
    test('a una página sin contenido todavía', () {
      expect(build().canTransform(webItem()), isTrue);
    });

    test('NO a algo que no es una página web', () {
      expect(build().canTransform(webItem(kind: SourceKind.youtube)), isFalse);
    });

    test('NO a una página que ya se extrajo', () {
      final withContent = webItem(
        renditions: [
          Rendition.text(
            id: 'r1',
            itemId: 'item-1',
            kind: RenditionKind.markdown,
            content: 'ya estaba',
            isPrimary: true,
            createdAt: now,
          ),
        ],
      );

      expect(build().canTransform(withContent), isFalse);
    });
  });

  group('lo que guarda', () {
    test('convierte el artículo a Markdown', () async {
      // Markdown y no HTML: es lo que leen Obsidian, Logseq y cualquier
      // editor, y evita que el índice de búsqueda se llene de nombres de
      // etiquetas.
      final transformer = build(
        extractor: FakeArticleExtractor(
          article: const ExtractedArticle(
            contentHtml:
                '<h2>Un subtítulo</h2><p>Con <strong>énfasis</strong>.</p>',
            textContent: 'Un subtítulo Con énfasis.',
          ),
        ),
      );

      final result = await transformer.transform(webItem());
      final content = result.renditions.single.searchableText!;

      // Carácter por carácter (F22). Con html2md, además, sin configurar el
      // estilo los encabezados de nivel 1 y 2 salían subrayados con === y
      // ---: el mismo documento con dos convenciones.
      expect(content, '## Un subtítulo\n\nCon **énfasis**.');
      expect(result.renditions.single.renditionKind, RenditionKind.markdown);
    });

    test('no agrega barras invertidas al texto del artículo (F22)', () async {
      // html2md guardaba "\[1\]", "1\. Intro" y "a\_b": barras que el
      // artículo no tiene.
      final transformer = build(
        extractor: FakeArticleExtractor(
          article: const ExtractedArticle(
            contentHtml:
                '<p>Ver [1].</p><p>1. Intro</p><p>a_b y 10<sup>6</sup></p>',
            textContent: 'Ver [1]. 1. Intro a_b y 106',
          ),
        ),
      );

      final result = await transformer.transform(webItem());

      expect(
        result.renditions.single.searchableText,
        'Ver [1].\n\n1. Intro\n\na_b y 10<sup>6</sup>',
      );
    });

    test(
      'un artículo corto se guarda, con la página archivada (F22)',
      () async {
        // Con el extractor de verdad: antes, por debajo de 250 caracteres se
        // decía que no había artículo y no se guardaba ni el texto ni la
        // página.
        final transformer = WebArticleTransformer(
          client: FakeWebPageClient(
            html: '<html><body><p>Cerrado por feriado.</p></body></html>',
          ),
          extractor: const ReaderModeArticleExtractor(),
          archiver: FakePageArchiver(
            result: Uint8List.fromList(utf8.encode('<html></html>')),
          ),
          files: files,
          ids: ids,
          clock: () => now,
          logger: const SilentLogger(),
        );

        final result = await transformer.transform(webItem());

        expect(result.renditions.single.searchableText, 'Cerrado por feriado.');
        expect(result.source.originalFilePath, isNotNull);
      },
    );

    test(
      'reemplaza el título deducido de la URL por el del artículo',
      () async {
        final transformer = build(
          extractor: FakeArticleExtractor(
            article: const ExtractedArticle(
              contentHtml: '<p>cuerpo</p>',
              textContent: 'cuerpo',
              title: 'La estructura de las revoluciones científicas',
              byline: 'Ana Ejemplo',
              siteName: 'Revista Ejemplo',
            ),
          ),
        );

        final result = await transformer.transform(webItem());

        expect(result.title, 'La estructura de las revoluciones científicas');
        expect(result.subtitle, 'Revista Ejemplo');
        expect(result.source.authorName, 'Ana Ejemplo');
      },
    );

    test('si el artículo no trae título, conserva el provisional en vez de '
        'dejarlo en blanco', () async {
      final transformer = build(
        extractor: FakeArticleExtractor(
          article: const ExtractedArticle(
            contentHtml: '<p>cuerpo</p>',
            textContent: 'cuerpo',
          ),
        ),
      );

      final result = await transformer.transform(webItem());

      expect(result.title, 'Un articulo interesante');
    });

    test('descarga la dirección guardada, no otra', () async {
      final client = FakeWebPageClient(html: '<html></html>');

      await build(client: client).transform(webItem());

      expect(
        client.requested.single.toString(),
        'https://ejemplo.org/blog/un-articulo-interesante',
      );
    });
  });

  group('páginas sin nada que leer', () {
    test('lanza en vez de guardar un elemento vacío', () async {
      // El extractor solo responde que no hay artículo cuando la página no
      // tiene ni una letra (F22): vacía, o armada entera con JavaScript.
      // El elemento queda como fallido y conserva su enlace.
      final transformer = build(extractor: FakeArticleExtractor());

      expect(
        () => transformer.transform(webItem()),
        throwsA(isA<NoArticleFoundException>()),
      );
    });
  });

  group('archivado de la página', () {
    Uint8List archivedBytes(String contents) =>
        Uint8List.fromList(utf8.encode(contents));

    test('si se pudo archivar, la ruta queda en la fuente', () async {
      final transformer = build(
        archiver: FakePageArchiver(result: archivedBytes('<html></html>')),
      );

      final result = await transformer.transform(webItem());

      expect(result.source.originalFilePath, isNotNull);
      expect(await files.read(result.source.originalFilePath!), isNotNull);
    });

    test('el archivo queda bajo el identificador de la fuente', () async {
      final transformer = build(
        archiver: FakePageArchiver(result: archivedBytes('<html></html>')),
      );

      final result = await transformer.transform(webItem());

      expect(
        result.source.originalFilePath,
        startsWith('originales/${result.source.id}/'),
      );
    });

    test('se le pasa a la página tal cual la trajo el cliente', () async {
      final archiver = FakePageArchiver(result: archivedBytes('<html></html>'));
      final client = FakeWebPageClient(html: '<html>contenido real</html>');

      await build(client: client, archiver: archiver).transform(webItem());

      expect(archiver.requested.single, '<html>contenido real</html>');
    });

    test(
      'si el archivador no produjo nada, la fuente no gana un archivo',
      () async {
        final transformer = build(archiver: FakePageArchiver());

        final result = await transformer.transform(webItem());

        expect(result.source.originalFilePath, isNull);
        expect(files.paths, isEmpty);
      },
    );

    test(
      'si el archivador revienta, el artículo se guarda igual, sin archivo',
      () async {
        // El archivado es un extra. Que falle de la forma que sea no puede
        // costarle al usuario el artículo que sí se extrajo.
        final transformer = build(
          archiver: FakePageArchiver(error: StateError('roto')),
        );

        final result = await transformer.transform(webItem());

        expect(result.source.originalFilePath, isNull);
        expect(result.renditions, isNotEmpty);
      },
    );
  });
}
