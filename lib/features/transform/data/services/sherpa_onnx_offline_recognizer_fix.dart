import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

/// Arregla un defecto real de `sherpa_onnx_web` 1.13.8: sin esto,
/// `sherpa_onnx.OfflineRecognizer(...)` —el que hace falta para Whisper,
/// no el `OnlineRecognizer` de reconocimiento en vivo— siempre revienta
/// con `Bad state: OfflineRecognizer not found. Is sherpa-onnx-asr.js
/// loaded?`, incluso después de un `initBindingsAsync()` sin errores.
///
/// La causa, confirmada compilando una app Dart de verdad y probándola en
/// un Chromium real: `sherpa-onnx-asr.js` declara `OfflineRecognizer` con
/// `class`, no con `var` ni con una función —a diferencia de
/// `createOnlineRecognizer`, que sí es una función y por eso el
/// reconocimiento en vivo no tiene este problema—. `SherpaOnnxWeb.loadWasm()`
/// carga ese archivo con un `eval` indirecto, y ahí es donde se pierde:
/// una clase declarada dentro de un `eval` indirecto no queda alcanzable
/// ni por `globalThis.OfflineRecognizer` —que es como la lee
/// `dart:js_interop`— ni siquiera por su nombre desde otro `eval`
/// posterior, porque cada `eval` indirecto tiene su propio entorno léxico
/// que desaparece en cuanto esa llamada termina. Verificado a mano, en ese
/// orden, antes de escribir este arreglo.
///
/// La solución es cargar el mismo archivo una segunda vez, pero como una
/// etiqueta `<script>` de verdad en vez de un `eval`: los `<script>`, a
/// diferencia de los `eval`, comparten un mismo entorno global persistente
/// entre ellos, así que la clase declarada en uno sigue existiendo para el
/// siguiente. Un segundo `<script>`, inyectado después, la copia a
/// `globalThis.OfflineRecognizer` —el único lugar donde `dart:js_interop`
/// sabe buscarla—, y desde ahí `sherpa_onnx.OfflineRecognizer(...)`
/// funciona sin que haya hecho falta tocar ni una línea del paquete.
///
/// Repite la carga de un archivo que `initBindingsAsync()` ya cargó una
/// vez —así que el motor de JavaScript lo analiza dos veces—, pero es la
/// única forma de dejar la clase alcanzable sin parchear `sherpa_onnx_web`
/// directamente. Si una versión futura del paquete expone la clase por su
/// cuenta, esta función se puede borrar entera.
///
/// Sin pruebas propias: manipula el DOM y el entorno global de JavaScript,
/// ninguno de los dos disponible bajo `flutter test`. Verificado a mano en
/// un Chromium real (ver la fase 8 en docs/arquitectura.md).
Future<void> ensureOfflineRecognizerIsReachable() async {
  if (_done) return;

  final data = await rootBundle.load(
    'packages/sherpa_onnx_web/assets/sherpa-onnx-asr.js',
  );
  final source = utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );

  _injectScript(source);
  _injectScript('globalThis.OfflineRecognizer = OfflineRecognizer;');

  _done = true;
}

bool _done = false;

void _injectScript(String source) {
  final script = web.HTMLScriptElement()..textContent = source;
  web.document.head!.appendChild(script);
}
