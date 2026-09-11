import 'dart:typed_data';

import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';

/// Archiva una página web completa, al modo de la extensión SingleFile:
/// incrusta sus imágenes y hojas de estilo como datos, para que se pueda
/// abrir después sin conexión y aunque el original ya no exista.
///
/// Aparte de [ArticleExtractor] a propósito, igual que ese está aparte del
/// transformador: uno separa el artículo del resto de la página, este
/// conserva la página entera tal como estaba. Son dos lecturas distintas del
/// mismo HTML, y cada una puede fallar o mejorar sin tocar a la otra.
// ignore: one_member_abstracts
abstract interface class PageArchiver {
  /// El HTML con sus recursos incrustados, listo para guardarse como un
  /// archivo autocontenido. `null` si no se pudo producir nada aprovechable
  /// —el archivado es un extra, y que falle no puede costarle al usuario el
  /// artículo que sí se extrajo.
  Future<Uint8List?> archive(String html, {required Uri baseUri});
}
