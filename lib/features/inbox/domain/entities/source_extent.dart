import 'package:freezed_annotation/freezed_annotation.dart';

part 'source_extent.freezed.dart';

/// Cuánto es lo que espera en la Bandeja (F30, decisión 68): las páginas de un
/// PDF o lo que dura un audio o un video, para la línea de datos de la
/// tarjeta.
///
/// No se guarda en ningún lado: sale de los fragmentos del texto, que ya
/// llevan la página de cada uno —un PDF— o el momento en que termina —lo
/// transcripto—. Lo que no tiene ninguna de las dos cosas, un artículo o un
/// Word, queda con las dos en `null`: no se inventa una extensión.
@freezed
sealed class SourceExtent with _$SourceExtent {
  const factory SourceExtent({int? pages, Duration? duration}) = _SourceExtent;

  const SourceExtent._();

  static const none = SourceExtent();

  bool get isEmpty => pages == null && duration == null;
}
