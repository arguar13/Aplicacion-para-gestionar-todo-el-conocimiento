// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'package:sinapsis/features/transform/domain/services/image_text_extractor.dart';

/// Devuelve el texto que el test le ponga, sin ningún motor de verdad
/// detrás.
class FakeImageTextExtractor implements ImageTextExtractor {
  FakeImageTextExtractor({this.text = ''});

  /// Lo que "reconoce" en cualquier imagen. Cadena vacía por defecto, igual
  /// que una foto sin ninguna letra adentro. Mutable a propósito: una
  /// prueba puede cambiarlo a mitad de camino.
  String text;

  /// Si está, se lanza en vez de devolver.
  Object? error;

  /// Las rutas que se le pidió reconocer, para comprobar en las pruebas que
  /// se le pide la absoluta y no la relativa que guarda la base.
  final requested = <String>[];

  @override
  Future<String> extractText(String absolutePath) async {
    requested.add(absolutePath);
    if (error != null) throw error!;

    return text;
  }
}
