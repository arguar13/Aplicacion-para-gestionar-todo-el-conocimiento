import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/network/network_providers.dart';

/// Los límites de las descargas de modelos: sin `receiveTimeout`, un
/// servidor que acepta la conexión y no contesta dejaba la descarga
/// esperando para siempre. En dio 5.11 ese límite es solo para las
/// cabeceras, así que no corta una descarga lenta: el cuerpo lo vigila
/// `ResumableDownload.stallTimeout` (ver su prueba).
void main() {
  test('una descarga de modelo tiene límite para conectar y para recibir '
      'las cabeceras', () {
    final options = modelDownloadBaseOptions();

    expect(options.connectTimeout, const Duration(seconds: 15));
    expect(options.receiveTimeout, const Duration(seconds: 30));
  });
}
