import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/reference/domain/services/attachment_file_name.dart';

void main() {
  group('extractAttachmentFileName', () {
    test('un nombre de archivo pelado', () {
      expect(extractAttachmentFileName('documento.pdf'), 'documento.pdf');
    });

    test('una ruta relativa', () {
      expect(
        extractAttachmentFileName('archivos/documento.pdf'),
        'documento.pdf',
      );
    });

    test('la forma de JabRef —descripción:ruta:tipo—, con una unidad de '
        'Windows adentro de la ruta', () {
      expect(
        extractAttachmentFileName(r':C:\Users\ana\Documentos\articulo.pdf:PDF'),
        'articulo.pdf',
      );
    });

    test('la forma de JabRef con descripción y ruta relativa Unix', () {
      expect(
        extractAttachmentFileName(':archivos/pdf/articulo.pdf:PDF'),
        'articulo.pdf',
      );
    });

    test('varios adjuntos separados por ; toma el primero', () {
      expect(
        extractAttachmentFileName(':primero.pdf:PDF;:segundo.pdf:PDF'),
        'primero.pdf',
      );
    });

    test('un .docx también se reconoce', () {
      expect(extractAttachmentFileName('tesis.docx'), 'tesis.docx');
    });

    test('no distingue mayúsculas en la extensión', () {
      expect(extractAttachmentFileName('ARTICULO.PDF'), 'ARTICULO.PDF');
    });

    test('sin nada que parezca un archivo: null', () {
      expect(extractAttachmentFileName('no hay ningún archivo acá'), isNull);
    });

    test('un texto vacío: null, sin romper', () {
      expect(extractAttachmentFileName(''), isNull);
    });

    test('una extensión que no es de documento: null', () {
      expect(extractAttachmentFileName('imagen.png'), isNull);
    });
  });

  group('matchAttachmentFile', () {
    final empty = Uint8List(0);
    final pdf = CapturedFile(name: 'Articulo.pdf', bytes: empty);
    final other = CapturedFile(name: 'otro.pdf', bytes: empty);

    test('encuentra el que coincide, sin distinguir mayúsculas', () {
      expect(matchAttachmentFile('articulo.pdf', [other, pdf]), same(pdf));
    });

    test('sin nombre de adjunto: null, sin recorrer nada', () {
      expect(matchAttachmentFile(null, [pdf]), isNull);
    });

    test('ninguno de los elegidos coincide: null', () {
      expect(matchAttachmentFile('no-esta.pdf', [pdf, other]), isNull);
    });

    test('sin ningún archivo elegido: null', () {
      expect(matchAttachmentFile('articulo.pdf', []), isNull);
    });
  });
}
