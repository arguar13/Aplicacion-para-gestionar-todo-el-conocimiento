import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/services/processed_image_title.dart';

/// El título de cada imagen al triarla (F46, decisión E): el que traía la
/// fuente —el pie de foto, el texto alternativo, el título bajo el que
/// está— y, si no traía ninguno, el nombre de su archivo, limpio.
void main() {
  group('processedImageTitle: de lo más propio a lo menos', () {
    test('el pie de foto, antes que el texto alternativo y el título '
        'cercano', () {
      expect(
        processedImageTitle(
          const ImageTitleClues(
            caption: 'El foro en el siglo II',
            alt: 'Foro',
            nearbyHeading: 'La ciudad',
            fileName: 'foro.jpg',
          ),
        ),
        'El foro en el siglo II',
      );
    });

    test('sin pie, el texto alternativo; sin él, el título cercano', () {
      expect(
        processedImageTitle(
          const ImageTitleClues(
            alt: 'Mapa del Imperio romano',
            nearbyHeading: 'La expansión',
            fileName: 'IMG_2034.jpg',
          ),
        ),
        'Mapa del Imperio romano',
      );
      expect(
        processedImageTitle(
          const ImageTitleClues(
            nearbyHeading: 'La expansión',
            fileName: 'IMG_2034.jpg',
          ),
        ),
        'La expansión',
      );
    });

    test('lo que no dice nada no cuenta: vacío, relleno, una dirección, '
        'solo signos', () {
      expect(
        processedImageTitle(
          const ImageTitleClues(
            caption: '   ',
            alt: 'Imagen',
            nearbyHeading: 'https://ejemplo.org/foto.jpg',
            fileName: 'mapa_imperio-romano_02.jpg',
          ),
        ),
        'Mapa imperio romano',
      );
      expect(
        processedImageTitle(
          const ImageTitleClues(
            caption: '— 3 —',
            alt: 'photo',
            fileName: 'roma.png',
          ),
        ),
        'Roma',
      );
    });

    test('un texto alternativo que es un nombre de archivo se limpia como '
        'tal', () {
      expect(
        processedImageTitle(
          const ImageTitleClues(alt: 'coliseo_noche-01.JPG', fileName: 'x.jpg'),
        ),
        'Coliseo noche',
      );
    });

    test('los espacios de más se van, y uno larguísimo se corta', () {
      expect(
        processedImageTitle(
          const ImageTitleClues(alt: '  El  foro \n romano ', fileName: ''),
        ),
        'El foro romano',
      );
      final long = processedImageTitle(
        ImageTitleClues(alt: 'Palabra ' * 40, fileName: ''),
      )!;
      expect(long.length, kImageTitleMaxChars);
      expect(long, endsWith('…'));
    });

    test('si nada dice nada, ninguno: la pantalla la nombra por su lugar', () {
      expect(
        processedImageTitle(
          const ImageTitleClues(
            alt: 'foto',
            fileName: 'IMG_20231014_101530.jpg',
          ),
        ),
        isNull,
      );
    });
  });

  group('imageTitleFromFileName: el nombre del archivo, limpio', () {
    test('sin carpeta, extensión, guiones ni número de serie', () {
      expect(
        imageTitleFromFileName(
          'originales/x/contenido/mapa_imperio-romano_02.jpg',
        ),
        'Mapa imperio romano',
      );
      expect(
        imageTitleFromFileName(r'C:\fotos\el.foro+romano~3.png'),
        'El foro romano',
      );
      expect(imageTitleFromFileName('foro.jpg.webp'), 'Foro');
    });

    test('lo que agregan la cámara y el teléfono, fuera', () {
      for (final name in [
        'IMG_20231014_101530.jpg',
        'IMG-20231014-WA0001.jpeg',
        'DSC01234.JPG',
        'PXL_20230101_123456789.jpg',
        'P1010123.JPG',
        'Captura de pantalla 2023-10-14 a las 10.15.30.png',
        'Screen Shot 2023-10-14 at 10.15.30 AM.png',
        'WhatsApp Image 2023-10-14 at 10.15.30.jpeg',
        'Photo_2023-10-01.heic',
        'a3f9c2e1b7d04e55.jpg',
        'foto.jpg',
      ]) {
        expect(imageTitleFromFileName(name), isNull, reason: name);
      }
      expect(imageTitleFromFileName('IMG_2034_coliseo.jpg'), 'Coliseo');
      expect(
        imageTitleFromFileName('Captura de pantalla 2023-10-14 Roma.png'),
        'Roma',
      );
    });

    test('lo que agrega la página o la copia, atrás, fuera', () {
      expect(imageTitleFromFileName('foro-romano-1024x768.jpg'), 'Foro romano');
      expect(imageTitleFromFileName('foro-romano@2x.png'), 'Foro romano');
      expect(imageTitleFromFileName('foro-romano-scaled.jpg'), 'Foro romano');
      expect(imageTitleFromFileName('foro-romano (1).jpg'), 'Foro romano');
      expect(
        imageTitleFromFileName('foro_romano_copia_final.jpg'),
        'Foro romano',
      );
      expect(
        imageTitleFromFileName('foro-romano-e1612345678.jpg'),
        'Foro romano',
      );
    });

    test('una palabra común que dice algo se queda', () {
      expect(
        imageTitleFromFileName('foto_de_mi_abuela.jpg'),
        'Foto de mi abuela',
      );
      expect(imageTitleFromFileName('foto_a_la_playa.jpg'), 'Foto a la playa');
      expect(imageTitleFromFileName('mapa_3d.png'), 'Mapa 3d');
    });

    test('un año se queda', () {
      expect(imageTitleFromFileName('colon_1492.png'), 'Colon 1492');
    });

    test('las mayúsculas que traía se respetan', () {
      expect(imageTitleFromFileName('Mapa_SPQR.png'), 'Mapa SPQR');
      expect(imageTitleFromFileName('ROMA.png'), 'ROMA');
    });

    test('de una dirección: sin la consulta ni el ancla, y con lo escrito '
        'con %', () {
      expect(
        imageTitleFromFileName(
          'https://upload.org/a/b/Mapa%20del%20Imperio%20romano.png?w=300#x',
        ),
        'Mapa del Imperio romano',
      );
      expect(imageTitleFromFileName('caf%C3%A9_paris.jpg'), 'Café paris');
      expect(imageTitleFromFileName('cien%_roma.jpg'), 'Cien% roma');
      expect(imageTitleFromFileName('mal%FF_roma.jpg'), 'Mal\uFFFD roma');
    });

    test('vacío o sin letras, ninguno', () {
      expect(imageTitleFromFileName(''), isNull);
      expect(imageTitleFromFileName('2023-10-14.jpg'), isNull);
      expect(imageTitleFromFileName('---.png'), isNull);
    });
  });

  group('headingsAboveImages: bajo qué título de la página está cada una', () {
    const page =
        '# Roma\n\n'
        'Texto.\n\n'
        '![](https://ejemplo.org/img/foro.jpg)\n\n'
        '## La expansión\n\n'
        '![Mapa](<https://ejemplo.org/img/mapa.jpg> "título")\n\n'
        '<img src="https://ejemplo.org/img/arco.jpg?a=1&amp;b=2" alt="">\n\n'
        '![](https://cdn.org/chico/columna-300x200.jpg)';

    test('el último título antes de donde aparece', () {
      expect(
        headingsAboveImages(page, [
          'https://ejemplo.org/img/foro.jpg',
          'http://ejemplo.org/img/mapa.jpg#zoom',
          'https://ejemplo.org/img/arco.jpg?a=1&b=2',
        ]),
        {
          'https://ejemplo.org/img/foro.jpg': 'Roma',
          'http://ejemplo.org/img/mapa.jpg#zoom': 'La expansión',
          'https://ejemplo.org/img/arco.jpg?a=1&b=2': 'La expansión',
        },
      );
    });

    test('por el nombre del archivo, si en la página hay uno solo con ese '
        'nombre', () {
      expect(
        headingsAboveImages(page, ['https://otro.org/x/columna-300x200.jpg']),
        {'https://otro.org/x/columna-300x200.jpg': 'La expansión'},
      );
      const twice =
          '# A\n\n![](https://a.org/f.jpg)\n\n# B\n\n![](https://b.org/f.jpg)';
      expect(headingsAboveImages(twice, ['https://c.org/f.jpg']), isEmpty);
    });

    test('las que no aparecen, o no tienen un título arriba, no están', () {
      expect(
        headingsAboveImages('![](https://a.org/arriba.jpg)\n\n# Después', [
          'https://a.org/arriba.jpg',
          'https://a.org/otra.jpg',
        ]),
        isEmpty,
      );
      expect(
        headingsAboveImages('Sin títulos', ['https://a.org/f.jpg']),
        isEmpty,
      );
      expect(headingsAboveImages(page, const []), isEmpty);
    });
  });

  group('sourceImageTitles: lo que se engancha al triar', () {
    test('cada imagen de la fuente, por su archivo, con lo que dice la '
        'fuente de ella', () {
      const markdown = '# Roma\n\n![](https://ejemplo.org/foro.jpg)';
      final titles = sourceImageTitles(
        const [
          SourceImage(
            path: 'originales/f/guardada.jpg',
            origin: SourceImageOrigin.original,
            sizeBytes: 1,
          ),
          SourceImage(
            path: 'originales/f/contenido/1.jpg',
            origin: SourceImageOrigin.content,
            sizeBytes: 1,
            title: 'El arco de Tito',
            originUrl: 'https://ejemplo.org/arco.jpg',
          ),
          SourceImage(
            path: 'originales/f/contenido/2.jpg',
            origin: SourceImageOrigin.content,
            sizeBytes: 1,
            originUrl: 'https://ejemplo.org/foro.jpg',
          ),
          SourceImage(
            path: 'originales/f/contenido/3.jpg',
            origin: SourceImageOrigin.content,
            sizeBytes: 1,
            originUrl: 'https://ejemplo.org/columna_trajana.jpg',
          ),
          SourceImage(
            path: 'originales/f/contenido/IMG_0001.jpg',
            origin: SourceImageOrigin.content,
            sizeBytes: 1,
          ),
        ],
        sourceTitle: 'Mi foto del Panteón',
        sourceMarkdown: markdown,
      );
      expect(titles, {
        'originales/f/guardada.jpg': 'Mi foto del Panteón',
        'originales/f/contenido/1.jpg': 'El arco de Tito',
        'originales/f/contenido/2.jpg': 'Roma',
        'originales/f/contenido/3.jpg': 'Columna trajana',
        'originales/f/contenido/IMG_0001.jpg': null,
      });
    });

    test('sin el texto de la fuente, sin título cercano', () {
      expect(
        sourceImageTitles(const [
          SourceImage(
            path: 'c/foro.jpg',
            origin: SourceImageOrigin.content,
            sizeBytes: 1,
            originUrl: 'https://ejemplo.org/foro_romano.jpg',
          ),
        ]),
        {'c/foro.jpg': 'Foro romano'},
      );
    });
  });
}
