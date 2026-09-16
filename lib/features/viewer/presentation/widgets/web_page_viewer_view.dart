import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// La página tal como quedó archivada al guardarla: con sus imágenes y sus
/// estilos incrustados, no la versión en Markdown que ya se ve en el
/// detalle.
///
/// Existe aparte del lector de documentos porque cumple un propósito
/// distinto: el Markdown del detalle es para leer y buscar, este visor es
/// para *ver la página como era* — el diseño, las imágenes en su lugar,
/// cualquier cosa que la extracción del artículo no haya conservado. Es el
/// mismo archivo que sirve de seguro contra el enlace que un día da 404 (ver
/// `WebArticleTransformer`), ahora con una forma de mirarlo sin salir de la
/// app.
///
/// Corre sobre un `WebView` con el archivo local leído del disco y volcado
/// directo con `loadHtmlString` —nunca vuelve a pedir nada por red—, así que
/// funciona igual con o sin conexión y no hay forma de que la página
/// archivada termine mostrando algo distinto de lo que se guardó.
///
/// No se usa `loadRequest(Uri.file(...))`: desde Android 10, el proceso del
/// `WebView` corre aislado del de la app —la razón detrás de las
/// vulnerabilidades de `file://` que motivaron el cambio— y no tiene permiso
/// para leer directamente el almacenamiento privado de la app, así que
/// termina en `net::ERR_ACCESS_DENIED` aunque el archivo exista y la app
/// misma pueda leerlo sin problema. Como el archivo ya trae sus imágenes y
/// estilos incrustados (ver `HtmlPageArchiver`), volcar el HTML tal cual con
/// `loadHtmlString` evita el problema de raíz: no hay ningún `file://` que
/// resolver.
///
/// Sin `Scaffold` propio a propósito: `WebPageViewerScreen` lo envuelve para
/// mostrarlo a pantalla completa, y `EmbeddedFileViewer` lo embebe tal cual
/// dentro de un marco acotado en el detalle del elemento.
class WebPageViewerView extends StatefulWidget {
  const WebPageViewerView({required this.path, super.key});

  final String path;

  @override
  State<WebPageViewerView> createState() => _WebPageViewerViewState();
}

class _WebPageViewerViewState extends State<WebPageViewerView> {
  final _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.disabled)
    ..setBackgroundColor(Colors.white);

  late final Future<bool> _loaded = _load();

  Future<bool> _load() async {
    try {
      final html = await File(widget.path).readAsString();
      await _controller.loadHtmlString(html);
      return true;
      // El archivo puede haberse borrado del disco después de indexarse, o
      // `WebViewController` puede no tener implementación nativa en esta
      // plataforma —de escritorio, por ejemplo—: cualquiera de las dos cosas
      // es un motivo tan válido como el otro para caer en el aviso en vez
      // de una excepción sin atrapar.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loaded,
      builder: (context, snapshot) {
        // El `WebView` ya se ve mientras carga: mostrarlo desde el
        // principio, y no solo cuando `_loaded` se resuelve, es lo que hace
        // que la carga se sienta instantánea en vez de un salto de pantalla
        // en blanco a contenido.
        if (snapshot.data == false) {
          return Center(
            child: Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        return WebViewWidget(controller: _controller);
      },
    );
  }
}
