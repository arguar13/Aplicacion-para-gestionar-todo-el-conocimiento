import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/flashcard.dart';

/// Arma un mazo de Anki (`.apkg`) a partir de las tarjetas de la bóveda.
///
/// Existe como interfaz por la misma razón que el resto de los servicios de
/// exportación: quien arma el paquete de verdad pasa por un archivo de
/// trabajo temporal (ver `AnkiPackageBuilder`), y una interfaz deja
/// reemplazarlo en las pruebas que no necesitan ese detalle.
// ignore: one_member_abstracts
abstract interface class AnkiDeckBuilder {
  /// El `.apkg` completo, listo para guardar o compartir: un `.zip` con la
  /// base de datos SQLite del mazo adentro, en el formato que Anki importa.
  Future<Uint8List> build(List<Flashcard> cards);
}
