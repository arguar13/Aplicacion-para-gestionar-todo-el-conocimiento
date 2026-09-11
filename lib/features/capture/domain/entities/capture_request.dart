import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';

part 'capture_request.freezed.dart';

/// Lo que el usuario aporta al capturar algo.
///
/// Son dos formas y no una con campos opcionales: lo pegado y lo elegido. Con
/// un solo constructor que llevara texto **y** archivo, los dos nulos o los
/// dos llenos serían estados construibles, y cada adaptador tendría que
/// defenderse de combinaciones que no existen. Separadas, la que no
/// corresponde no se puede ni escribir.
@freezed
sealed class CaptureRequest with _$CaptureRequest {
  /// Lo pegado o escrito, tal cual.
  ///
  /// Es texto crudo y no un tipo ya resuelto a propósito: quien captura pega
  /// lo que tiene —un enlace, un párrafo, una frase— sin tener que declarar
  /// antes de qué se trata. Reconocerlo es trabajo de los adaptadores, no de
  /// la persona.
  const factory CaptureRequest.text({
    required String rawInput,

    /// Un título puesto a mano. Si viene, gana sobre el que dedujera el
    /// adaptador: nadie conoce mejor su propio material que quien lo guarda.
    String? title,

    /// Una nota del usuario sobre esto, separada del contenido.
    String? note,
  }) = TextCapture;

  /// Un archivo elegido con el selector del sistema o compartido desde otra
  /// app.
  const factory CaptureRequest.file({
    required CapturedFile file,
    String? title,
    String? note,
  }) = FileCapture;

  const CaptureRequest._();

  /// El texto sin espacios sobrantes, que es con lo que trabajan los
  /// adaptadores: una URL pegada suele venir con un salto de línea detrás.
  ///
  /// Vacío cuando lo que entró fue un archivo. Así los adaptadores de texto
  /// no necesitan preguntar de qué clase de captura se trata: la respuesta
  /// que reciben ya los descarta.
  String get trimmedInput => switch (this) {
    TextCapture(:final rawInput) => rawInput.trim(),
    FileCapture() => '',
  };

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

  /// El archivo, si lo que entró fue uno.
  CapturedFile? get asFile => switch (this) {
    FileCapture(:final file) => file,
    TextCapture() => null,
  };
}
