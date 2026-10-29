import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

/// Dibuja un widget fuera de pantalla y lo devuelve como imagen (F43): las
/// diapositivas del PDF, la lámina de una infografía guardada como PNG.
///
/// Es el mismo dibujo que se ve en pantalla —el mismo árbol de widgets, las
/// mismas letras y los mismos pintores—, no una copia hecha a mano con otra
/// librería: así lo exportado es fiel por construcción. El widget se arma en
/// su propio árbol, con su propio dueño de construcción, sin tocar lo que hay
/// en pantalla.
///
/// Las imágenes que use el widget (una ilustración) tienen que estar ya
/// cargadas en la caché: ver [precache].
abstract final class CreationRasterizer {
  /// [widget] dibujado en un lienzo de [logicalSize], a [pixelRatio] píxeles
  /// por punto. Quien la recibe la tiene que liberar (`dispose`).
  static Future<ui.Image> render(
    Widget widget, {
    required Size logicalSize,
    double pixelRatio = 1,
  }) async {
    final binding = WidgetsBinding.instance;
    final view =
        binding.platformDispatcher.implicitView ??
        binding.platformDispatcher.views.first;
    final boundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: view,
      child: RenderPositionedBox(child: boundary),
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(logicalSize),
        physicalConstraints: BoxConstraints.tight(logicalSize),
      ),
    );
    final pipeline = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();
    final build = BuildOwner(focusManager: FocusManager());
    final root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: MediaQuery(
        data: MediaQueryData(size: logicalSize),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.fromSize(size: logicalSize, child: widget),
        ),
      ),
    ).attachToRenderTree(build);
    try {
      // Dos pasadas: una imagen que ya estaba en la caché llega al widget
      // durante la primera, y la segunda la dibuja.
      for (var pass = 0; pass < 2; pass++) {
        build
          ..buildScope(root)
          ..finalizeTree();
        pipeline
          ..flushLayout()
          ..flushCompositingBits()
          ..flushPaint();
      }
      return await boundary.toImage(pixelRatio: pixelRatio);
    } finally {
      // Se desarma el árbol: lo de adentro se desmonta y suelta lo suyo.
      RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
        child: const SizedBox.shrink(),
      ).attachToRenderTree(build, root);
      build.finalizeTree();
      renderView.child = null;
    }
  }

  /// Carga [provider] en la caché de imágenes y espera a que esté: después,
  /// un `Image` con él se dibuja en la primera pasada. Una imagen que no
  /// carga no detiene nada: el widget pone lo suyo en su lugar.
  static Future<void> precache(ImageProvider provider) {
    final done = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(listener);
      },
      onError: (_, _) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return done.future;
  }

  /// [image] como JPEG de calidad [quality], codificado en otro hilo.
  static Future<Uint8List> toJpeg(ui.Image image, {int quality = 90}) async {
    final rgba = await image.toByteData();
    if (rgba == null) throw StateError('No se pudo leer la imagen.');
    final width = image.width;
    final height = image.height;
    final bytes = rgba.buffer.asUint8List();
    return Isolate.run(() {
      final decoded = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: bytes.buffer,
        numChannels: 4,
      );
      return img.encodeJpg(decoded, quality: quality);
    });
  }

  /// [image] como PNG, sin pérdida.
  static Future<Uint8List> toPng(ui.Image image) async {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('No se pudo leer la imagen.');
    return png.buffer.asUint8List();
  }
}
