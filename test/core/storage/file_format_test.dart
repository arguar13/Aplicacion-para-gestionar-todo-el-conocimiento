import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_format.dart';

import '../../support/sample_files.dart';

void main() {
  Uint8List raw(String text) => Uint8List.fromList(utf8.encode(text));

  group('documentos', () {
    test('un PDF se reconoce por su firma', () {
      expect(detectFileFormat(raw('%PDF-1.7 binario')), FileFormat.pdf);
    });

    test('un EPUB se reconoce sin descomprimirlo', () {
      // La especificacion obliga a que la primera entrada del ZIP se llame
      // `mimetype` y contenga `application/epub+zip`, sin comprimir. Eso es
      // exactamente para poder reconocerlo leyendo el principio del archivo.
      expect(detectFileFormat(buildEpub()), FileFormat.epub);
    });

    test('un DOCX se reconoce por lo que trae adentro', () {
      expect(detectFileFormat(buildDocx()), FileFormat.docx);
    });

    test('un ZIP que no es ninguno de los dos no se confunde', () {
      // Sin esta distincion, cualquier .zip entraria como documento y el
      // lector de DOCX reventaria con un error incomprensible.
      expect(detectFileFormat(buildPlainZip()), FileFormat.unknown);
    });
  });

  group('la extension no manda', () {
    test('un PDF llamado .txt sigue siendo un PDF', () {
      // Pasa al descargar de sitios que sirven el archivo con otro nombre, y
      // pasa cuando alguien renombra para "ordenar".
      expect(
        detectFileFormat(raw('%PDF-1.4 ...'), name: 'apunte.txt'),
        FileFormat.pdf,
      );
    });

    test('un .docx que en realidad es un EPUB se lee como EPUB', () {
      expect(
        detectFileFormat(buildEpub(), name: 'libro.docx'),
        FileFormat.epub,
      );
    });

    test('un archivo sin nombre se reconoce igual', () {
      // Lo que llega por el boton de compartir a veces no trae nombre.
      expect(detectFileFormat(buildDocx()), FileFormat.docx);
    });
  });

  group('la extension decide solo cuando no hay firma', () {
    test('el texto suelto se reconoce por el nombre', () {
      // Un .txt no empieza con nada en particular: no hay otra forma.
      expect(
        detectFileFormat(raw('unas notas sueltas'), name: 'notas.txt'),
        FileFormat.plainText,
      );
    });

    test('el Markdown se distingue del texto suelto', () {
      expect(
        detectFileFormat(raw('# Un titulo'), name: 'apunte.md'),
        FileFormat.markdown,
      );
    });

    test('sin firma ni extension conocida, queda sin reconocer', () {
      expect(
        detectFileFormat(raw('vaya a saber que'), name: 'cosa.xyz'),
        FileFormat.unknown,
      );
    });

    test('la extension no distingue mayusculas', () {
      expect(
        detectFileFormat(raw('notas'), name: 'NOTAS.TXT'),
        FileFormat.plainText,
      );
    });
  });

  group('imagenes', () {
    test('PNG', () {
      expect(
        detectFileFormat(
          withSignature([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        FileFormat.png,
      );
    });

    test('JPEG', () {
      expect(
        detectFileFormat(withSignature([0xFF, 0xD8, 0xFF, 0xE0])),
        FileFormat.jpeg,
      );
    });

    test('GIF, en sus dos versiones', () {
      expect(detectFileFormat(raw('GIF87a...')), FileFormat.gif);
      expect(detectFileFormat(raw('GIF89a...')), FileFormat.gif);
    });

    test('WEBP, que comparte cabecera con WAV', () {
      // Los dos son contenedores RIFF: se distinguen recien en el byte 8.
      expect(detectFileFormat(raw('RIFF????WEBPVP8 ')), FileFormat.webp);
    });

    test('HEIC, que es el formato de las fotos del iPhone', () {
      expect(detectFileFormat(raw('    ftypheic')), FileFormat.heic);
    });
  });

  group('audio y video', () {
    test('MP3 con etiqueta ID3', () {
      expect(detectFileFormat(raw('ID3 ')), FileFormat.mp3);
    });

    test('MP3 sin etiqueta, que empieza directo con la trama', () {
      expect(detectFileFormat(withSignature([0xFF, 0xFB])), FileFormat.mp3);
    });

    test('WAV', () {
      expect(detectFileFormat(raw('RIFF????WAVEfmt ')), FileFormat.wav);
    });

    test('OGG', () {
      expect(detectFileFormat(raw('OggS...')), FileFormat.ogg);
    });

    test('FLAC', () {
      expect(detectFileFormat(raw('fLaC...')), FileFormat.flac);
    });

    test('MP4, cuya firma no esta al principio', () {
      // Los primeros cuatro bytes son el tamano de la caja; la firma viene
      // despues. Buscarla en el byte cero no encontraria nada.
      expect(detectFileFormat(raw('    ftypisom')), FileFormat.mpeg4);
    });
  });

  group('archivos rotos o vacios', () {
    test('un archivo vacio no revienta', () {
      expect(detectFileFormat(Uint8List(0)), FileFormat.unknown);
    });

    test('dos bytes sueltos tampoco', () {
      // Cada comprobacion mira una cantidad distinta de bytes; ninguna puede
      // salirse del arreglo.
      expect(
        detectFileFormat(Uint8List.fromList([0x50, 0x4B])),
        FileFormat.unknown,
      );
    });

    test(
      'un ZIP cortado a la mitad devuelve desconocido, no una excepcion',
      () {
        final truncated = Uint8List.fromList(buildEpub().take(20).toList());
        expect(detectFileFormat(truncated), FileFormat.unknown);
      },
    );
  });

  group('de que clase de fuente se trata', () {
    test('los documentos', () {
      expect(FileFormat.pdf.sourceKind, SourceKind.document);
      expect(FileFormat.epub.sourceKind, SourceKind.document);
      expect(FileFormat.docx.sourceKind, SourceKind.document);
      expect(FileFormat.markdown.sourceKind, SourceKind.document);
    });

    test('las imagenes', () {
      expect(FileFormat.png.sourceKind, SourceKind.image);
      expect(FileFormat.heic.sourceKind, SourceKind.image);
    });

    test('el audio', () {
      expect(FileFormat.mp3.sourceKind, SourceKind.audio);
      expect(FileFormat.flac.sourceKind, SourceKind.audio);
    });

    test('lo que no se reconocio se guarda igual, como documento', () {
      // El archivo ES la fuente: perderlo seria lo peor que podria pasar.
      // Que no se le pueda sacar texto es otro problema, y menor.
      expect(FileFormat.unknown.sourceKind, SourceKind.document);
    });
  });
}
