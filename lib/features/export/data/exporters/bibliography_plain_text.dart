import 'dart:convert';
import 'dart:typed_data';

import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';

/// La bibliografía de un conjunto como texto sin marcado (F15): sin las
/// cursivas del estilo, que el texto plano no lleva.
Uint8List buildBibliographyPlainText(Bibliography bibliography) {
  final text = '${bibliography.title}\n\n${bibliography.toPlainText()}\n';
  return Uint8List.fromList(utf8.encode(text));
}
