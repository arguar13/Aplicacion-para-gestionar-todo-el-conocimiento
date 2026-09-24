import 'dart:convert';
import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter.dart';

/// Exporta a Markdown con una cabecera YAML de procedencia.
///
/// Es el formato de intercambio del proyecto: lo leen Obsidian, Logseq,
/// Notion y cualquier editor de texto — y la cabecera YAML es justamente lo
/// que Obsidian y Logseq usan como "propiedades" de una nota, así que la
/// procedencia queda disponible ahí sin que la app tenga que inventar su
/// propio formato.
///
/// La procedencia se repite además al pie, en texto corriente. La cabecera
/// la leen las herramientas; el pie lo lee una persona que abre el archivo
/// en cualquier editor que no muestre "propiedades" — que sigue siendo la
/// mayoría de los editores de texto del mundo.
class MarkdownExporter implements Exporter {
  const MarkdownExporter();

  @override
  ExportFormat get format => ExportFormat.markdown;

  @override
  String suggestedFileName(KnowledgeItem item) =>
      '${sanitizeFileName(item.title)}.${format.fileExtension}';

  @override
  Future<Uint8List> export(
    KnowledgeItem item, {
    Bibliography? bibliography,
  }) async {
    final buffer = StringBuffer()
      ..write(_frontMatter(item))
      ..writeln()
      ..writeln('# ${item.title}');

    if (item.subtitle != null) {
      buffer
        ..writeln()
        ..writeln('*${item.subtitle}*');
    }

    if (item.notes?.isNotEmpty ?? false) {
      buffer
        ..writeln()
        ..writeln('> ${item.notes!.replaceAll('\n', '\n> ')}');
    }

    final texts = item.renditions.whereType<TextRendition>();
    if (texts.isEmpty) {
      buffer
        ..writeln()
        ..writeln('*Sin contenido extraído todavía.*');
    } else {
      for (final rendition in texts) {
        buffer
          ..writeln()
          ..writeln(rendition.content);
      }
    }

    buffer
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln(_provenanceFooter(item));

    if (bibliography != null && !bibliography.isEmpty) {
      buffer
        ..writeln()
        ..writeln('## ${bibliography.title}')
        ..writeln()
        ..writeln(bibliography.toMarkdown());
    }

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  String _frontMatter(KnowledgeItem item) {
    final source = item.source;
    final lines = <String>[
      '---',
      'title: ${_yamlString(item.title)}',
      'source_kind: ${source.kind.name}',
      'captured_at: ${_yamlString(_isoDate(source.capturedAt))}',
      if (source.url != null) 'url: ${_yamlString(source.url!)}',
      if (source.authorName != null)
        'author: ${_yamlString(source.authorName!)}',
      if (source.authorUrl != null)
        'author_url: ${_yamlString(source.authorUrl!)}',
      if (source.publishedAt != null)
        'published_at: ${_yamlString(_isoDate(source.publishedAt!))}',
    ];

    if (item.tags.isNotEmpty) {
      lines
        ..add('tags:')
        ..addAll(item.tags.map((tag) => '  - ${_yamlString(tag.name)}'));
    }

    lines.add('---');
    return lines.join('\n');
  }

  /// La procedencia otra vez, en texto corriente y no en YAML.
  ///
  /// La fecha va en formato ISO y no como "11 de septiembre de 2026": el
  /// exportador no recibe el idioma de la interfaz —ni tendría sentido que
  /// lo recibiera, porque el archivo puede abrirse mucho después, en otra
  /// sesión, en otro idioma— y una fecha en un formato ambiguo según el país
  /// de quien lea ("09/11" ¿es 9 de noviembre o 11 de septiembre?) es peor
  /// que una sin traducir.
  String _provenanceFooter(KnowledgeItem item) {
    final source = item.source;
    final lines = <String>[
      'Guardado el ${_isoDate(source.capturedAt).substring(0, 10)}.',
    ];

    if (source.url != null) lines.add('Fuente: <${source.url}>');
    if (source.authorUrl != null) {
      lines.add('Autor: <${source.authorUrl}>');
    } else if (source.authorName != null) {
      lines.add('Autor: ${source.authorName}');
    }

    return lines.join('  \n');
  }

  String _isoDate(DateTime date) => date.toIso8601String();

  /// Envuelve entre comillas dobles y escapa lo que haga falta.
  ///
  /// No se confía en la sintaxis "sin comillas" de YAML para valores
  /// simples: un título que empiece con un signo, o que contenga dos puntos
  /// seguidos de un espacio, se interpreta distinto sin comillas — y
  /// confiar en adivinar cuáles títulos son "seguros" es exactamente el
  /// tipo de casos borde que después aparece con un archivo real. Comillas
  /// siempre, sin excepción, es la única regla que no tiene casos borde.
  String _yamlString(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
