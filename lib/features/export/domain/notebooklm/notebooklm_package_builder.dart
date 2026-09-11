import 'dart:convert';
import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter.dart';

/// Arma un paquete de archivos listo para subir a NotebookLM: uno por
/// elemento, más un índice que los enumera y explica adónde llevarlos.
///
/// Se arma con Markdown en la práctica —quien lo conecta elige el
/// exportador de Markdown, que además le da a cada archivo una cabecera de
/// procedencia: de dónde salió, cuándo, quién lo escribió— pero esta clase
/// no sabe nada de formatos concretos, solo de [Exporter]. Es lo que separa
/// "cómo se arma el paquete" de "en qué formato queda cada archivo", y lo
/// que permite probar esta clase con cualquier exportador de mentira.
///
/// No tiene nada de entrada/salida: solo arma bytes en memoria. Guardarlos
/// en una carpeta de verdad es trabajo de quien orqueste esto, para poder
/// probar el armado del paquete sin tocar el disco.
class NotebookLmPackageBuilder {
  const NotebookLmPackageBuilder({required this.exporter});

  final Exporter exporter;

  /// Con un `00-` adelante para que, en cualquier explorador de archivos que
  /// ordene alfabéticamente, sea lo primero que se vea al abrir la carpeta.
  static const indexFileName = '00-indice.md';

  /// El paquete completo: nombre de archivo → contenido.
  ///
  /// Los nombres repetidos entre elementos —dos títulos iguales, o un
  /// artículo que se llame igual que el índice— se resuelven agregando un
  /// número, en vez de que uno le gane el lugar al otro en silencio.
  Future<Map<String, Uint8List>> build(List<KnowledgeItem> items) async {
    final files = <String, Uint8List>{};
    final usedNames = {indexFileName};
    final entries = <String>[];

    for (final item in items) {
      final name = _uniqueName(exporter.suggestedFileName(item), usedNames);
      files[name] = await exporter.export(item);
      entries.add('- [${item.title}]($name)');
    }

    files[indexFileName] = Uint8List.fromList(
      utf8.encode(_index(itemCount: items.length, entries: entries)),
    );

    return files;
  }

  String _uniqueName(String suggested, Set<String> used) {
    if (used.add(suggested)) return suggested;

    final dot = suggested.lastIndexOf('.');
    final hasExtension = dot > 0;
    final base = hasExtension ? suggested.substring(0, dot) : suggested;
    final extension = hasExtension ? suggested.substring(dot) : '';

    var attempt = 2;
    while (!used.add('$base ($attempt)$extension')) {
      attempt++;
    }
    return '$base ($attempt)$extension';
  }

  String _index({required int itemCount, required List<String> entries}) {
    final plural = itemCount == 1 ? 'elemento' : 'elementos';
    final intro =
        '$itemCount $plural de Sinapsis, listos para subir como fuentes a '
        '[NotebookLM](https://notebooklm.google.com): abrí un cuaderno '
        'nuevo o uno existente y arrastrá ahí toda esta carpeta.';

    final lines = <String>[
      '# Paquete para NotebookLM',
      '',
      intro,
      '',
      '## Contenido',
      '',
      ...entries,
    ];

    return lines.join('\n');
  }
}
