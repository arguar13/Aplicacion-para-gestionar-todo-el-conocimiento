import 'dart:typed_data';

import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';

/// Trae los bytes crudos de un recurso —una imagen, una hoja de estilos, una
/// fuente— para incrustarlo al archivar una página completa.
///
/// Aparte de [WebPageClient] a propósito, y no un método más ahí: archivar
/// una sola página pide decenas de estos, y que uno falle es lo esperado y
/// no algo que el usuario deba resolver — por eso devuelve `null` en vez de
/// lanzar, para que cada recurso roto se salte sin tumbar el archivado
/// entero. [WebPageClient.fetchHtml] en cambio trae la página principal, y
/// que esa sí falle es un fallo real de la captura.
// ignore: one_member_abstracts
abstract interface class ResourceFetcher {
  Future<Uint8List?> fetchBytes(Uri url);
}
