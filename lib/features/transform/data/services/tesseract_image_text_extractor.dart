import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/transform/domain/services/image_text_extractor.dart';
import 'package:web/web.dart' as web;

/// `ImageTextExtractor` sobre Tesseract compilado a WebAssembly, para la
/// web —donde Google ML Kit no tiene ninguna versión—. Ver la decisión 10
/// en docs/arquitectura.md.
///
/// Los archivos de Tesseract —motor, worker y los datos entrenados de
/// español e inglés— los trae `tool/fetch_tesseract_web.sh` a `web/`, y se
/// sirven junto con el resto de la app: nada se pide a una CDN en tiempo
/// de ejecución.
///
/// La ruta que recibe [extractText] es la relativa que guarda la base, no
/// una absoluta —acá no existe tal cosa—: se leen los bytes con
/// `FileStore.read()` y se los entrega a Tesseract como una URL de blob en
/// memoria.
///
/// Sin pruebas propias, igual que el resto de lo que habla con una
/// librería de JavaScript de terceros: `ImageTransformer` es lo que se
/// prueba a fondo, contra un doble de esta interfaz.
class TesseractImageTextExtractor implements ImageTextExtractor {
  const TesseractImageTextExtractor({required FileStore files})
    : _files = files;

  final FileStore _files;

  static Completer<JSObject>? _loading;

  /// Carga `tesseract.min.js` una sola vez —el script UMD deja `Tesseract`
  /// como variable global— y reutiliza esa carga si dos reconocimientos
  /// arrancan casi al mismo tiempo.
  static Future<JSObject> _tesseract() {
    final existing = globalContext.getProperty<JSObject?>('Tesseract'.toJS);
    if (existing != null) return Future.value(existing);

    final inProgress = _loading;
    if (inProgress != null) return inProgress.future;

    final completer = Completer<JSObject>();
    _loading = completer;

    final script = web.HTMLScriptElement()
      ..src = 'tesseract/tesseract.min.js'
      ..addEventListener(
        'load',
        (() {
          completer.complete(
            globalContext.getProperty<JSObject>('Tesseract'.toJS),
          );
        }).toJS,
      )
      ..addEventListener(
        'error',
        (() {
          _loading = null;
          completer.completeError(
            StateError('No se pudo cargar tesseract/tesseract.min.js'),
          );
        }).toJS,
      );
    web.document.head!.appendChild(script);

    return completer.future;
  }

  @override
  Future<String> extractText(String path) async {
    final bytes = await _files.read(path);
    if (bytes == null) return '';

    final tesseract = await _tesseract();

    final blob = web.Blob([bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    try {
      final options = JSObject()
        ..['workerPath'] = 'tesseract/worker.min.js'.toJS
        ..['corePath'] = 'tesseract/'.toJS
        ..['langPath'] = 'tessdata/'.toJS
        // Los datos entrenados quedan sin comprimir en el propio
        // repositorio: pedirle a Tesseract que los descomprima sería
        // fallar por dar por sentado un formato que no es el que hay.
        ..['gzip'] = false.toJS;

      final recognize = tesseract.getProperty<JSFunction>('recognize'.toJS);
      final resultPromise =
          recognize.callAsFunction(
                tesseract,
                url.toJS,
                'spa+eng'.toJS,
                options,
              )!
              as JSPromise;
      final result = (await resultPromise.toDart)! as JSObject;

      final data = result.getProperty<JSObject>('data'.toJS);
      final text = data.getProperty<JSString?>('text'.toJS);
      return text?.toDart ?? '';
    } finally {
      web.URL.revokeObjectURL(url);
    }
  }
}
