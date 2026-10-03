import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/features/dev_seed/presentation/widgets/sample_library_confirmation.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

const _mb = 1024 * 1024;

SampleLink _web(String id) => SampleLink(
  id: id,
  title: 'Página $id',
  why: 'Una página.',
  kind: SampleLinkKind.webArticle,
  url: 'https://ejemplo.org/$id',
  approxBytes: 2 * _mb,
);

const _video = SampleLink(
  id: 'yt-corto',
  title: 'Un video corto',
  why: 'Un video.',
  kind: SampleLinkKind.youtubeVideo,
  url: 'https://www.youtube.com/watch?v=abc',
  approxBytes: 4 * _mb,
);

const _pdf = SampleFile(
  id: 'pdf-laudato',
  title: "Laudato si'",
  why: 'Un PDF.',
  kind: SampleFileKind.pdf,
  url: 'https://ejemplo.org/laudato.pdf',
  fileName: 'laudato_si.pdf',
  approxBytes: 3 * _mb,
);

const _audio = SampleFile(
  id: 'audio-apologia',
  title: 'Apología de Sócrates',
  why: 'Un audio.',
  kind: SampleFileKind.audio,
  url: 'https://archivo.org/apologia.mp3',
  fileName: 'apologia.mp3',
  approxBytes: 5 * _mb,
);

SampleNote _note(String id) =>
    SampleNote(id: id, title: 'Nota $id', why: 'Una nota.', blocks: const []);

/// Lo que dice la confirmación antes de cargar la biblioteca de ejemplo:
/// solo lo que de verdad falta, con el singular y el plural en su lugar.
void main() {
  final es = AppLocalizationsEs();
  final en = AppLocalizationsEn();

  group('qué se guarda', () {
    test('nombra solo los tipos que faltan, con cuántos de cada uno', () {
      final sentences = sampleLibraryConfirmSentences(es, [_pdf, _note('a')]);

      expect(
        sentences.first,
        'Se van a guardar 1 PDF y 1 nota de la biblioteca de ejemplo.',
      );
      expect(sentences.join(' '), isNot(contains('artículo')));
      expect(sentences.join(' '), isNot(contains('video')));
    });

    test('un solo recurso va en singular', () {
      final sentences = sampleLibraryConfirmSentences(es, [_web('a')]);

      expect(
        sentences.first,
        'Se va a guardar 1 artículo de la biblioteca de ejemplo.',
      );
      expect(
        sentences.last,
        'Se carga en segundo plano: podés seguir usando la app y cancelar '
        'cuando quieras.',
      );
    });

    test('varios de un tipo van en plural, y en el orden de la lista', () {
      final sentences = sampleLibraryConfirmSentences(es, [
        _note('a'),
        _audio,
        _web('a'),
        _note('b'),
        _web('b'),
        _video,
      ]);

      expect(
        sentences.first,
        'Se van a guardar 2 artículos, 1 video, 1 audio y 2 notas de la '
        'biblioteca de ejemplo.',
      );
      expect(
        sentences.last,
        'Se cargan por tandas, en segundo plano: podés seguir usando la app '
        'y cancelar cuando quieras.',
      );
    });
  });

  group('cuánto se baja', () {
    test('archivos ahora y páginas y videos al procesarse', () {
      final sentences = sampleLibraryConfirmSentences(es, [
        _web('a'),
        _video,
        _pdf,
        _audio,
      ]);

      expect(
        sentences[1],
        'Se bajan de internet unos 8,0 MB ahora y, al procesarse, unos '
        '6,0 MB más: la página y el audio del video.',
      );
    });

    test('sin enlaces no habla de lo que se baja al procesarse', () {
      final sentences = sampleLibraryConfirmSentences(es, [_pdf, _note('a')]);

      expect(sentences[1], 'Se bajan de internet unos 3,0 MB ahora.');
      expect(sentences.join(' '), isNot(contains('0 B')));
    });

    test('sin archivos no habla de lo que se baja ahora', () {
      final sentences = sampleLibraryConfirmSentences(es, [
        _web('a'),
        _web('b'),
      ]);

      expect(
        sentences[1],
        'Al procesarse, se bajan de internet unos 4,0 MB: las páginas.',
      );
      expect(sentences.join(' '), isNot(contains('ahora')));
    });

    test('solo notas: no hay nada que bajar, y no se menciona', () {
      final sentences = sampleLibraryConfirmSentences(es, [
        _note('a'),
        _note('b'),
      ]);

      expect(sentences, hasLength(2));
      expect(
        sentences.first,
        'Se van a guardar 2 notas de la biblioteca de ejemplo.',
      );
      expect(sentences.last, startsWith('Se cargan por tandas'));
    });
  });

  test('en inglés, con su conjunción y su punto decimal', () {
    final sentences = sampleLibraryConfirmSentences(en, [
      _web('a'),
      _web('b'),
      _video,
      _pdf,
    ]);

    expect(
      sentences[0],
      'This saves 2 articles, 1 video and 1 PDF from the sample library.',
    );
    expect(
      sentences[1],
      'It downloads about 3.0 MB now and, while processing, about 8.0 MB '
      "more: the pages and the video's audio.",
    );
    expect(
      sentences[2],
      'They load in batches, in the background: you can keep using the app '
      'and cancel at any time.',
    );
  });

  test('lo que se baja es la suma de lo que pesa cada uno', () {
    expect(sampleLibraryBytes([_pdf, _audio, _note('a')]), 8 * _mb);
    expect(sampleLibraryBytes(const []), 0);
  });
}
