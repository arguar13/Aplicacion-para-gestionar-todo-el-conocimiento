import 'package:freezed_annotation/freezed_annotation.dart';

part 'capture_request.freezed.dart';

/// Lo que el usuario aporta al capturar algo.
///
/// Es texto crudo y no un tipo ya resuelto a propósito: quien captura pega
/// lo que tiene —un enlace, un párrafo, una frase— sin tener que declarar
/// antes de qué se trata. Reconocerlo es trabajo de los adaptadores, no de
/// la persona.
@freezed
sealed class CaptureRequest with _$CaptureRequest {
  const factory CaptureRequest({
    /// Lo pegado o escrito, tal cual.
    required String rawInput,

    /// Un título puesto a mano. Si viene, gana sobre el que dedujera el
    /// adaptador: nadie conoce mejor su propio material que quien lo guarda.
    String? title,

    /// Una nota del usuario sobre esto, separada del contenido.
    String? note,
  }) = _CaptureRequest;

  const CaptureRequest._();

  /// El texto sin espacios sobrantes, que es con lo que trabajan los
  /// adaptadores: una URL pegada suele venir con un salto de línea detrás.
  String get trimmedInput => rawInput.trim();

  /// La URL, si lo que entró es una.
  ///
  /// Devuelve `null` para cualquier otra cosa. Se exige esquema http o https
  /// y un host: sin eso, `Uri.parse` acepta casi cualquier texto —"hola" es
  /// una URI válida con path "hola"— y media biblioteca de notas terminaría
  /// clasificada como páginas web.
  Uri? get asUrl {
    final parsed = Uri.tryParse(trimmedInput);
    if (parsed == null) return null;

    final isWebScheme = parsed.scheme == 'http' || parsed.scheme == 'https';
    return isWebScheme && parsed.host.isNotEmpty ? parsed : null;
  }
}
