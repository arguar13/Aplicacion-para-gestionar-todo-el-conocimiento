import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/processed/data/services/pdfium_outline_reader.dart';
import 'package:sinapsis/features/processed/domain/services/headings/pdf_outline_reader.dart';

/// Quien lee los marcadores de un PDF para el Índice (F46, decisión B): el
/// que usan la escritura de `processed_headings` y su relleno (paso 2). Las
/// pruebas lo reemplazan por un doble que no abre ningún archivo.
final pdfOutlineReaderProvider = Provider<PdfOutlineReader>(
  (ref) => const PdfiumOutlineReader(),
);
