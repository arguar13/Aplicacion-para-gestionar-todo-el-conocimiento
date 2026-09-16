import 'dart:typed_data';
// Solo para el enlace [FileChooser] del comentario de la clase; el análisis
// estático no ve esa referencia dentro de un doc comment.
// ignore: unused_import
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';

/// Junta varias fotos de página en un solo documento.
///
/// Existe como contrato de dominio, y no como una llamada directa al
/// paquete que arma el PDF, por el mismo motivo que [FileChooser]: separa
/// la decisión de "escanear varias páginas es un documento, no varias
/// fotos sueltas" de con qué biblioteca se arma ese documento en concreto.
// ignore: one_member_abstracts
abstract interface class DocumentScanAssembler {
  /// Arma un documento con una página por cada elemento de [pages], en el
  /// mismo orden. [pages] no puede estar vacía.
  Future<Uint8List> assemble(List<Uint8List> pages);
}
