import 'dart:convert';
import 'dart:typed_data';

import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';

/// La bibliografía de un conjunto como un archivo de Markdown (F15): el
/// título de la lista como encabezado de primer nivel y una entrada por
/// párrafo, con las cursivas del estilo entre asteriscos.
Uint8List buildBibliographyMarkdown(Bibliography bibliography) {
  final text = '# ${bibliography.title}\n\n${bibliography.toMarkdown()}\n';
  return Uint8List.fromList(utf8.encode(text));
}
