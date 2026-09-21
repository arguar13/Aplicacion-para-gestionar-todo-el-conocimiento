import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// El espacio de nombres del formato de Word. Igual que en `DocxParser`: se
/// declara el prefijo `w:` a mano en vez de dejar que `XmlBuilder` elija uno,
/// porque es el prefijo que todo lector de `.docx` espera encontrar.
const kWordNamespace =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// Arma un `.docx` de verdad alrededor del XML de su cuerpo: el ZIP con su
/// tipo de contenido, sus relaciones y sus propiedades, que es lo que Word,
/// LibreOffice y cualquier procesador de texto piden para abrirlo.
///
/// Es lo que comparten el exportador de un elemento y la bibliografía de un
/// conjunto: cada uno arma su `word/document.xml` y este paquete lo envuelve.
/// Se escribe con `archive` + `xml` en vez de con un paquete dedicado —ver la
/// decisión 3 en `docs/arquitectura.md`—.
///
/// [title] y [creator] van a las propiedades del documento.
Uint8List buildDocxPackage({
  required String documentXml,
  required String title,
  required String creator,
}) {
  final archive = Archive()
    ..addFile(_entry('[Content_Types].xml', _contentTypesXml()))
    ..addFile(_entry('_rels/.rels', _rootRelsXml()))
    ..addFile(_entry('docProps/core.xml', _coreXml(title, creator)))
    ..addFile(_entry('word/document.xml', documentXml));

  final bytes = ZipEncoder().encode(archive);
  return Uint8List.fromList(bytes);
}

ArchiveFile _entry(String name, String xml) {
  final bytes = Uint8List.fromList(utf8.encode(xml));
  return ArchiveFile(name, bytes.length, bytes);
}

String _contentTypesXml() {
  final builder = XmlBuilder();
  builder
    ..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"')
    ..element(
      'Types',
      namespace: _ct,
      namespaces: {_ct: ''},
      nest: () {
        builder
          ..element(
            'Default',
            attributes: {
              'Extension': 'rels',
              'ContentType':
                  'application/vnd.openxmlformats-package.relationships'
                  '+xml',
            },
          )
          ..element(
            'Default',
            attributes: {'Extension': 'xml', 'ContentType': 'application/xml'},
          )
          ..element(
            'Override',
            attributes: {
              'PartName': '/word/document.xml',
              'ContentType':
                  'application/vnd.openxmlformats-officedocument'
                  '.wordprocessingml.document.main+xml',
            },
          )
          ..element(
            'Override',
            attributes: {
              'PartName': '/docProps/core.xml',
              'ContentType':
                  'application/vnd.openxmlformats-package'
                  '.core-properties+xml',
            },
          );
      },
    );
  return builder.buildDocument().toXmlString();
}

String _rootRelsXml() {
  final builder = XmlBuilder();
  builder
    ..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"')
    ..element(
      'Relationships',
      namespace: _rel,
      namespaces: {_rel: ''},
      nest: () {
        builder
          ..element(
            'Relationship',
            attributes: {
              'Id': 'rId1',
              'Type':
                  'http://schemas.openxmlformats.org/officeDocument/2006'
                  '/relationships/officeDocument',
              'Target': 'word/document.xml',
            },
          )
          ..element(
            'Relationship',
            attributes: {
              'Id': 'rId2',
              'Type':
                  'http://schemas.openxmlformats.org/package/2006'
                  '/relationships/metadata/core-properties',
              'Target': 'docProps/core.xml',
            },
          );
      },
    );
  return builder.buildDocument().toXmlString();
}

String _coreXml(String title, String creator) {
  final builder = XmlBuilder();
  builder
    ..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"')
    ..element(
      'coreProperties',
      namespace: _cp,
      namespaces: {_cp: 'cp', _dc: 'dc'},
      nest: () {
        builder
          ..element('title', namespace: _dc, nest: title)
          ..element('creator', namespace: _dc, nest: creator);
      },
    );
  return builder.buildDocument().toXmlString();
}

const _cp =
    'http://schemas.openxmlformats.org/package/2006/metadata'
    '/core-properties';

const _dc = 'http://purl.org/dc/elements/1.1/';

const _ct = 'http://schemas.openxmlformats.org/package/2006/content-types';

const _rel = 'http://schemas.openxmlformats.org/package/2006/relationships';
