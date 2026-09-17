import 'package:url_launcher/url_launcher.dart';

/// Le pasa [url] a la app o al navegador que el sistema tenga asociado,
/// devolviendo si se pudo abrir.
///
/// Atrapa cualquier fallo del plugin —sin ninguna app que entienda el
/// enlace, sin permiso del sistema, lo que sea— en vez de dejarlo escapar:
/// a quien llama solo le importa si funcionó o no, no por qué no.
///
/// Sin pruebas propias, igual que `SherpaOnnxAudioTranscriberIo` o
/// `MlKitImageTextExtractor`: en Windows —la plataforma de escritorio de
/// este proyecto— `url_launcher` no habla por un `MethodChannel` mockeable,
/// sino con el plugin nativo directo, así que no hay con qué correr esto
/// bajo `flutter test`.
Future<bool> launchExternalUrl(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    // `launchUrl` puede fallar con cualquier tipo de excepción según la
    // plataforma —una `PlatformException` en Android/iOS si no hay
    // permiso, un `FormatException` si la URL guardada quedó mal formada—,
    // y ninguna cambia lo que hay que hacer: devolver que no se pudo.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return false;
  }
}
