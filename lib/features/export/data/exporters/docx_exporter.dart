import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter.dart';
import 'package:xml/xml.dart';

/// Exporta a un `.docx` de verdad, para abrir y seguir editando en Word,
/// LibreOffice Writer o cualquier procesador de texto — no una plantilla ni
/// un archivo que finge serlo.
///
/// Un `.docx` es un ZIP con XML adentro, así que se escribe con `archive` +
/// `xml` en vez de con un paquete dedicado — ver la decisión 3 en
/// `docs/arquitectura.md`, y es la misma elección que ya usa `DocxParser`
/// para la dirección contraria (leer en vez de escribir).
///
/// Igual que el exportador de texto plano y el de PDF, el contenido
/// **no se convierte** desde Markdown: los símbolos (`#`, `**`, `-`) quedan
/// tal cual, cada uno en su propio párrafo. Interpretarlos para producir
/// encabezados y listas de Word de verdad es un trabajo considerable y con
/// muchos casos borde, y esta exportación ya cumple su propósito —un
/// documento que Word abre sin errores, con el contenido completo y
/// legible— sin necesitar eso.
class DocxExporter implements Exporter {
  const DocxExporter();

  @override
  ExportFormat get format => ExportFormat.docx;

  @override
  String suggestedFileName(KnowledgeItem item) =>
      '${sanitizeFileName(item.title)}.${format.fileExtension}';

  @override
  Future<Uint8List> export(KnowledgeItem item) async {
    final archive = Archive()
      ..addFile(_entry('[Content_Types].xml', _contentTypesXml()))
      ..addFile(_entry('_rels/.rels', _rootRelsXml()))
      ..addFile(_entry('docProps/core.xml', _coreXml(item)))
      ..addFile(_entry('word/document.xml', _documentXml(item)));

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
              attributes: {
                'Extension': 'xml',
                'ContentType': 'application/xml',
              },
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

  String _coreXml(KnowledgeItem item) {
    final builder = XmlBuilder();
    builder
      ..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"')
      ..element(
        'coreProperties',
        namespace: _cp,
        namespaces: {_cp: 'cp', _dc: 'dc'},
        nest: () {
          builder
            ..element('title', namespace: _dc, nest: item.title)
            ..element(
              'creator',
              namespace: _dc,
              nest: item.source.authorName ?? 'Sinapsis',
            );
        },
      );
    return builder.buildDocument().toXmlString();
  }

  String _documentXml(KnowledgeItem item) {
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
              _titleParagraph(builder, item.title);

              if (item.subtitle != null) {
                _paragraph(builder, item.subtitle!, italic: true);
              }
              if (item.notes?.isNotEmpty ?? false) {
                _paragraph(builder, item.notes!, italic: true);
              }

              final texts = item.renditions.whereType<TextRendition>();
              if (texts.isEmpty) {
                _paragraph(
                  builder,
                  'Sin contenido extraído todavía.',
                  italic: true,
                );
              } else {
                for (final rendition in texts) {
                  for (final paragraph in _paragraphs(rendition.content)) {
                    _paragraph(builder, paragraph);
                  }
                }
              }

              for (final line in _provenance(item)) {
                _paragraph(builder, line, size: 18, gray: true);
              }

              builder.element('sectPr', namespace: _w);
            },
          );
        },
      );
    return builder.buildDocument().toXmlString();
  }

  void _titleParagraph(XmlBuilder builder, String title) {
    builder.element(
      'p',
      namespace: _w,
      nest: () {
        builder.element(
          'pPr',
          namespace: _w,
          nest: () {
            builder.element(
              'pStyle',
              namespace: _w,
              attributes: {'w:val': 'Title'},
            );
          },
        );
        builder.element(
          'r',
          namespace: _w,
          nest: () {
            builder.element(
              'rPr',
              namespace: _w,
              nest: () {
                builder
                  ..element('b', namespace: _w)
                  ..element('sz', namespace: _w, attributes: {'w:val': '44'});
              },
            );
            builder.element(
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

  void _paragraph(
    XmlBuilder builder,
    String text, {
    bool italic = false,
    int? size,
    bool gray = false,
  }) {
    final lines = text.split('\n');

    builder.element(
      'p',
      namespace: _w,
      nest: () {
        for (var i = 0; i < lines.length; i++) {
          builder.element(
            'r',
            namespace: _w,
            nest: () {
              if (italic || size != null || gray) {
                builder.element(
                  'rPr',
                  namespace: _w,
                  nest: () {
                    if (italic) builder.element('i', namespace: _w);
                    if (size != null) {
                      builder.element(
                        'sz',
                        namespace: _w,
                        attributes: {'w:val': '$size'},
                      );
                    }
                    if (gray) {
                      builder.element(
                        'color',
                        namespace: _w,
                        attributes: {'w:val': '757575'},
                      );
                    }
                  },
                );
              }
              builder.element(
                't',
                namespace: _w,
                attributes: {'xml:space': 'preserve'},
                nest: lines[i],
              );
            },
          );
          if (i != lines.length - 1) builder.element('br', namespace: _w);
        }
      },
    );
  }

  Iterable<String> _paragraphs(String content) => content
      .split(RegExp(r'\n\s*\n'))
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty);

  List<String> _provenance(KnowledgeItem item) {
    final source = item.source;
    final lines = <String>[
      'Guardado el ${source.capturedAt.toIso8601String().substring(0, 10)}.',
    ];

    if (source.url != null) lines.add('Fuente: ${source.url}');
    if (source.authorUrl != null) {
      lines.add('Autor: ${source.authorUrl}');
    } else if (source.authorName != null) {
      lines.add('Autor: ${source.authorName}');
    }

    return lines;
  }
}

/// El espacio de nombres del formato de Word. Igual que en `DocxParser`: se
/// declara el prefijo `w:` a mano en vez de dejar que `XmlBuilder` elija uno,
/// porque es el prefijo que todo lector de `.docx` espera encontrar.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

const _cp =
    'http://schemas.openxmlformats.org/package/2006/metadata'
    '/core-properties';

const _dc = 'http://purl.org/dc/elements/1.1/';

const _ct = 'http://schemas.openxmlformats.org/package/2006/content-types';

const _rel = 'http://schemas.openxmlformats.org/package/2006/relationships';
