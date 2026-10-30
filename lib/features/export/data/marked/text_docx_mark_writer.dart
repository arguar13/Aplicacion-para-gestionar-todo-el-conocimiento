import 'dart:isolate';
import 'dart:typed_data';

import 'package:sinapsis/features/export/data/exporters/docx_package.dart';
import 'package:sinapsis/features/export/data/marked/docx_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/document_note.dart';
import 'package:xml/xml.dart';

/// Un texto suelto (`.txt`) marcado, como Word (F38, decisión C).
///
/// Un archivo de texto no tiene dónde guardar un color, así que el texto se
/// descarga como un `.docx` con **el mismo texto, un párrafo por renglón**, y
/// los tramos marcados como los marca [DocxMarkWriter]: fondo o subrayado de
/// su color exacto, las notas de un resaltado como comentarios y las notas en
/// el texto (F45, mejora 19) como notas al pie. La otra salida que el plan
/// consideró, un `.txt` con marcas como «⟦así⟧», cambia el texto; esta lo
/// deja como estaba.
///
/// El documento que se arma es mínimo pero de verdad —el mismo paquete que
/// el exportador de Word: tipo de contenido, relaciones y propiedades—, con
/// Calibri a 11 puntos para que se lea como un documento y no como el
/// Times 10 que Word usa cuando no hay estilos.
class TextDocxMarkWriter {
  const TextDocxMarkWriter({DocxMarkWriter docx = const DocxMarkWriter()})
    : _docx = docx;

  final DocxMarkWriter _docx;

  /// El texto [text] como Word, con [marks] marcados y [notes] como notas al
  /// pie. [title] va a las propiedades del documento. Las posiciones de los
  /// dos son de [text].
  Future<Uint8List> write({
    required String text,
    List<DocumentMark> marks = const [],
    List<DocumentNote> notes = const [],
    String title = '',
  }) => Isolate.run(
    () => writeSync(text: text, marks: marks, notes: notes, title: title),
  );

  /// Lo mismo que [write], en este hilo.
  Uint8List writeSync({
    required String text,
    List<DocumentMark> marks = const [],
    List<DocumentNote> notes = const [],
    String title = '',
  }) {
    final plain = buildDocxPackage(
      documentXml: _documentXml(text),
      title: title,
      creator: 'Sinapsis',
    );
    return _docx.writeSync(docx: plain, text: text, marks: marks, notes: notes);
  }
}

const _tab = '\u0009';

/// Lo que XML 1.0 no admite en ningún lugar: los controles menos tabulación
/// y salto de línea.
final _invalidXmlChars = RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F]');

String _documentXml(String text) {
  final body = StringBuffer();
  for (final line
      in text.replaceAll(_invalidXmlChars, '').split(RegExp(r'\r\n|\r|\n'))) {
    if (line.isEmpty) {
      body.write('<w:p/>');
      continue;
    }
    body.write('<w:p>');
    // Una tabulación es un elemento propio en Word, no un carácter en el
    // texto.
    final tabs = line.split(_tab);
    for (var i = 0; i < tabs.length; i++) {
      if (i > 0) body.write('<w:r>$_runProperties<w:tab/></w:r>');
      if (tabs[i].isEmpty) continue;
      final escaped = XmlText(tabs[i]).toXmlString();
      body.write(
        '<w:r>$_runProperties<w:t xml:space="preserve">$escaped</w:t></w:r>',
      );
    }
    body.write('</w:p>');
  }
  return [
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
    '<w:document xmlns:w="$kWordNamespace"><w:body>$body</w:body></w:document>',
  ].join();
}

final _runProperties = [
  '<w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>',
  '<w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr>',
].join();
