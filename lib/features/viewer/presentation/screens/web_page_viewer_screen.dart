import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// La página tal como quedó archivada al guardarla: con sus imágenes y sus
/// estilos incrustados, no la versión en Markdown que ya se ve en el
/// detalle.
///
/// Existe aparte de [DocumentReaderScreen] porque cumple un propósito
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
class WebPageViewerScreen extends StatefulWidget {
  const WebPageViewerScreen({
    required this.path,
    required this.title,
    super.key,
  });

  final String path;
  final String title;

  @override
  State<WebPageViewerScreen> createState() => _WebPageViewerScreenState();
}

class _WebPageViewerScreenState extends State<WebPageViewerScreen> {
  final _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.disabled)
    ..setBackgroundColor(Colors.white);

  late final Future<void> _loaded = _load();

  Future<void> _load() async {
    final html = await File(widget.path).readAsString();
    await _controller.loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, snapshot) {
          // El `WebView` ya se ve mientras carga: mostrarlo desde el
          // principio, y no solo cuando `_loaded` se resuelve, es lo que
          // hace que la carga se sienta instantánea en vez de un salto de
          // pantalla en blanco a contenido.
          if (snapshot.hasError) {
            return const Center(child: Icon(Icons.error_outline, size: 48));
          }
          return WebViewWidget(controller: _controller);
        },
      ),
    );
  }
}
