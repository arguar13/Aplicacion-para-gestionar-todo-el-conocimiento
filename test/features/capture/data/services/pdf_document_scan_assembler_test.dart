import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/features/capture/data/services/pdf_document_scan_assembler.dart';

void main() {
  const assembler = PdfDocumentScanAssembler();

  /// Una imagen chica de verdad, no bytes cualquiera: `pw.MemoryImage`
  /// necesita poder decodificarla para ponerla en la página.
  Uint8List fakePagePhoto({int width = 40, int height = 60}) {
    final image = img.Image(width: width, height: height);
    return Uint8List.fromList(img.encodePng(image));
  }

  setUpAll(() async {
    await pdfrxInitialize();
  });

  test('una sola foto arma un PDF de una sola página', () async {
    final bytes = await assembler.assemble([fakePagePhoto()]);

    expect(bytes.take(5), '%PDF-'.codeUnits);

    final document = await PdfDocument.openData(bytes);
    try {
      expect(document.pages, hasLength(1));
    } finally {
      await document.dispose();
    }
  });

  test(
    'varias fotos arman un PDF con una página por cada una, en orden',
    () async {
      final pages = [
        fakePagePhoto(),
        fakePagePhoto(width: 60, height: 40),
        fakePagePhoto(),
      ];

      final bytes = await assembler.assemble(pages);

      final document = await PdfDocument.openData(bytes);
      try {
        expect(document.pages, hasLength(3));
      } finally {
        await document.dispose();
      }
    },
  );
}
