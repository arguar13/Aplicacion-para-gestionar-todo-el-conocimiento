import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:sinapsis/features/capture/data/services/captured_file_on_disk.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/services/shared_content_listener.dart';

/// [SharedContentListener] sobre [`receive_sharing_intent`]
/// (https://pub.dev/packages/receive_sharing_intent), configurado por ahora
/// solo del lado Android (ver la decisión 7 en docs/arquitectura.md).
///
/// El plugin entrega texto, URLs y archivos con la misma forma —una ruta en
/// [SharedMediaFile.path]— y es esta clase la que decide, según
/// [SharedMediaFile.type], si esa ruta es el contenido en sí (texto o URL) o
/// hay que leerla como archivo. El resto de la app nunca ve un
/// `SharedMediaFile`: solo `CaptureRequest`, que es lo mismo que produce
/// pegar algo a mano o elegir un archivo con el selector.
class ReceiveSharingIntentListener implements SharedContentListener {
  const ReceiveSharingIntentListener();

  @override
  Future<List<CaptureRequest>> initial() async {
    try {
      // Copiada, no la lista tal cual: el plugin puede reciclar la misma
      // referencia interna para `reset()`, y vaciarla ahí después vaciaría
      // también esto sin que el código de acá lo esté pidiendo.
      final media = List<SharedMediaFile>.of(
        await ReceiveSharingIntent.instance.getInitialMedia(),
      );
      // Sin este aviso, lo mismo que arrancó la app se procesaría de nuevo
      // cada vez que algo más vuelva a preguntar por `getInitialMedia()`.
      await ReceiveSharingIntent.instance.reset();
      return await _toRequests(media);
      // Sin plugin nativo del otro lado —una plataforma no configurada, o
      // los tests, que corren sin ningún sistema operativo real— esta
      // llamada no tiene con qué responder. No es un error del usuario: es
      // que acá no hay nada que compartir todavía.
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Stream<List<CaptureRequest>> get stream => ReceiveSharingIntent.instance
      .getMediaStream()
      // Los mismos dos motivos que en initial(): un error puntual del
      // plugin nativo, o directamente no haber ninguno del otro lado.
      // Cortar el stream por esto dejaría de escuchar el resto de lo que se
      // comparta en lo que queda de la sesión de la app.
      .handleError(
        (Object _) {},
        test: (error) =>
            error is PlatformException || error is MissingPluginException,
      )
      .asyncMap(_toRequests)
      .where((requests) => requests.isNotEmpty);

  Future<List<CaptureRequest>> _toRequests(List<SharedMediaFile> media) async {
    final requests = <CaptureRequest>[];
    for (final item in media) {
      final request = await _toRequest(item);
      if (request != null) requests.add(request);
    }
    return requests;
  }

  Future<CaptureRequest?> _toRequest(SharedMediaFile media) async =>
      switch (media.type) {
        SharedMediaType.text ||
        SharedMediaType.url => CaptureRequest.text(rawInput: media.path),
        SharedMediaType.image ||
        SharedMediaType.video ||
        SharedMediaType.file => await _toFileRequest(media),
      };

  /// En disco, sin leerlo entero (F21): un video de varios GB compartido
  /// desde la galería se copia al almacén por partes al guardarlo. Antes se
  /// cargaba entero en memoria, y lo que pasaba de 500 MB se descartaba en
  /// silencio.
  Future<CaptureRequest?> _toFileRequest(SharedMediaFile media) async {
    try {
      final file = await capturedFileOnDisk(
        File(media.path),
        name: p.basename(media.path),
      );
      return file == null ? null : CaptureRequest.file(file: file);
      // El plugin copia lo compartido a una carpeta temporal antes de
      // avisar, pero esa copia puede haber desaparecido si el sistema
      // limpió la caché entre que se compartió y que Sinapsis la leyó.
    } on FileSystemException {
      return null;
    }
  }
}
