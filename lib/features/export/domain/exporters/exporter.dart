import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';

/// Convierte un elemento en un archivo, en un formato concreto.
///
/// Un exportador entiende de *cómo se ve* el resultado —la sintaxis de
/// Markdown, la disposición de una página de PDF— y no de *qué* elemento es
/// ni de *dónde* termina guardado. Eso es simétrico con los transformadores:
/// allá se entiende de formato de entrada, acá de formato de salida, y
/// ninguno de los dos sabe nada del otro.
abstract interface class Exporter {
  ExportFormat get format;

  /// El nombre del elemento, en el idioma del sistema de archivos: sin
  /// caracteres que un sistema operativo rechace, con la extensión que
  /// corresponde. No incluye la ruta ni la carpeta — eso lo decide quien
  /// pide guardar, no quien exporta.
  String suggestedFileName(KnowledgeItem item);

  /// Convierte [item] al formato de este exportador.
  ///
  /// Con [bibliography], la agrega al pie del documento —F15, D13—: quien
  /// llama ya decidió qué cita la nota y en qué estilo. `null`, o una
  /// bibliografía vacía, no agrega nada. No todos los exportadores saben
  /// mostrarla —un `.bib` exporta una referencia, no un documento con
  /// secciones; un texto plano no tiene con qué separar una sección de
  /// otra—: cada uno decide si la usa o la ignora en silencio.
  Future<Uint8List> export(KnowledgeItem item, {Bibliography? bibliography});
}
