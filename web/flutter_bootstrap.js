// CanvasKit local, no la CDN de Google: el principio 1 de la arquitectura
// es tajante con esto — las únicas conexiones salientes son las que el
// usuario pide explícitamente, y cargar el motor de renderizado no es una
// de ellas. Sin esto, la app ni siquiera pinta el primer cuadro si
// gstatic.com está bloqueado, lento o inexistente para quien la abre.
// Ver la decisión 9 en docs/arquitectura.md.
//
// Los archivos de `canvaskit/` los trae `tool/prepare_web_assets.sh` desde
// el propio SDK de Flutter instalado, no de una descarga aparte: ya vienen
// con el SDK, en la versión exacta que este build está usando.

{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
