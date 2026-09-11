import 'dart:convert';
import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter.dart';

/// Exporta a texto sin marcado, para cuando solo importa poder pegar el
/// contenido en cualquier lado sin símbolos de por medio.
///
/// El contenido guardado ya viene casi siempre en Markdown, y no se
/// convierte "de verdad": interpretar `#`, `**`, listas y tablas para
/// quitarles la sintaxis es un trabajo considerable y con muchos casos
/// borde, y el resultado de hacerlo mal —una tabla que pierde sus columnas,
/// un asterisco que se come una palabra— sería peor que dejar los símbolos.
/// La mayoría del contenido capturado (transcripciones, artículos) usa
/// Markdown liviano que se lee bien igual, con o sin marcado.
class PlainTextExporter implements Exporter {
  const PlainTextExporter();

  @override
  ExportFormat get format => ExportFormat.plainText;

  @override
  String suggestedFileName(KnowledgeItem item) =>
      '${sanitizeFileName(item.title)}.${format.fileExtension}';

  @override
  Future<Uint8List> export(KnowledgeItem item) async {
    final buffer = StringBuffer()
      ..writeln(item.title)
      ..writeln('=' * item.title.length);

    if (item.subtitle != null) {
      buffer
        ..writeln()
        ..writeln(item.subtitle);
    }

    if (item.notes?.isNotEmpty ?? false) {
      buffer
        ..writeln()
        ..writeln(item.notes);
    }

    final texts = item.renditions.whereType<TextRendition>();
    if (texts.isEmpty) {
      buffer
        ..writeln()
        ..writeln('Sin contenido extraído todavía.');
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
      ..writeln(_provenance(item));

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  String _provenance(KnowledgeItem item) {
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

    return lines.join('\n');
  }
}
