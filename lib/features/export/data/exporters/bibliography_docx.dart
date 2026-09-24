import 'dart:typed_data';

import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/export/data/exporters/docx_package.dart';
import 'package:xml/xml.dart';

/// La bibliografía de un conjunto como un `.docx` de verdad (F15): el título de
/// la lista y una entrada por párrafo, con las cursivas del estilo y la
/// sangría francesa —la primera línea al margen y las siguientes metidas— que
/// APA, MLA y Chicago piden.
///
/// Los huecos van como texto, tal cual —«[falta: año]»—: es lo que quien abre
/// el documento tiene que ver para completarlo. El portapapeles de Flutter
/// solo lleva texto plano, así que para pegar una bibliografía con sus
/// cursivas en un trabajo esto y el Markdown son el camino.
///
/// Es solo la lista, sin el texto de una nota ni nada más: la bibliografía al
/// pie de una nota exportada es otro camino, que la agrega al documento de la
/// nota.
Uint8List buildBibliographyDocx(Bibliography bibliography) => buildDocxPackage(
  documentXml: bibliographyDocumentXml(bibliography),
  title: bibliography.title,
  creator: 'Sinapsis',
);

/// El cuerpo del documento —`word/document.xml`— de [bibliography]: lo que
/// también se agrega al pie de una nota exportada.
String bibliographyDocumentXml(Bibliography bibliography) {
  final builder = XmlBuilder();
  builder
    ..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"')
    ..element(
      'document',
      namespace: _w,
      namespaces: {_w: 'w'},
      nest: () {
        builder.element(
          'body',
          namespace: _w,
          nest: () {
            writeBibliographyBody(builder, bibliography);
            builder.element('sectPr', namespace: _w);
          },
        );
      },
    );
  return builder.buildDocument().toXmlString();
}

/// El título de la lista y una entrada por párrafo de [bibliography], dentro
/// del `<w:body>` que [builder] ya tiene abierto —sin abrirlo ni cerrarlo, y
/// sin el `sectPr` final—.
///
/// Aparte de [bibliographyDocumentXml] para que `DocxExporter` pueda
/// agregarla al pie de una nota exportada (F15, D13), después de su propio
/// contenido y en el mismo `<w:body>`, en vez de en un documento aparte.
void writeBibliographyBody(XmlBuilder builder, Bibliography bibliography) {
  _heading(builder, bibliography.title);
  for (final entry in bibliography.entries) {
    _entry(builder, entry.citation);
  }
}

/// El título de la lista: un encabezado de primer nivel, en negrita.
void _heading(XmlBuilder builder, String title) {
  builder.element(
    'p',
    namespace: _w,
    nest: () {
      builder
        ..element(
          'pPr',
          namespace: _w,
          nest: () {
            builder
              ..element(
                'pStyle',
                namespace: _w,
                attributes: {'w:val': 'Heading1'},
              )
              ..element(
                'outlineLvl',
                namespace: _w,
                attributes: {'w:val': '0'},
              );
          },
        )
        ..element(
          'r',
          namespace: _w,
          nest: () {
            builder
              ..element(
                'rPr',
                namespace: _w,
                nest: () {
                  builder
                    ..element('b', namespace: _w)
                    ..element('sz', namespace: _w, attributes: {'w:val': '32'});
                },
              )
              ..element(
                't',
                namespace: _w,
                attributes: {'xml:space': 'preserve'},
                nest: title,
              );
          },
        );
    },
  );
}

/// Una entrada: un párrafo con sangría francesa —1,27 cm— y un poco de aire
/// debajo, con cada corrida en su formato.
void _entry(XmlBuilder builder, Citation citation) {
  builder.element(
    'p',
    namespace: _w,
    nest: () {
      builder.element(
        'pPr',
        namespace: _w,
        nest: () {
          builder
            ..element('spacing', namespace: _w, attributes: {'w:after': '120'})
            ..element(
              'ind',
              namespace: _w,
              attributes: {'w:left': '720', 'w:hanging': '720'},
            );
        },
      );
      for (final run in citation.runs) {
        builder.element(
          'r',
          namespace: _w,
          nest: () {
            if (run is ItalicRun) {
              builder.element(
                'rPr',
                namespace: _w,
                nest: () => builder.element('i', namespace: _w),
              );
            }
            builder.element(
              't',
              namespace: _w,
              attributes: {'xml:space': 'preserve'},
              nest: run.text,
            );
          },
        );
      }
    },
  );
}

const _w = kWordNamespace;
