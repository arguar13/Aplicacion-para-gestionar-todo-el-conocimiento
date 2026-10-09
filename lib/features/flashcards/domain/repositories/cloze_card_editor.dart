import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/error/failures.dart';

/// Qué pasó con las tarjetas de un texto de huecos al editarlo.
@immutable
class ClozeEditOutcome {
  const ClozeEditOutcome({
    required this.updated,
    required this.created,
    required this.removed,
  });

  /// Las que siguen con su hueco y recibieron el texto nuevo (conservan su
  /// calendario).
  final int updated;

  /// Las de los huecos que se agregaron.
  final int created;

  /// Las de los huecos que se sacaron: se borran con su calendario.
  final int removed;
}

/// Edita el texto de una tarjeta de huecos y deja al día a todas sus
/// hermanas (F31, decisión 73).
///
/// Cada tarjeta de huecos guarda el texto ENTERO, y las de un texto comparten
/// grupo: editar una a una dejaría unas con el texto viejo y otras con el
/// nuevo. Esto reconcilia el grupo entero en una transacción —todo o nada—:
///
/// - el hueco que sigue: su tarjeta recibe el texto y el complemento nuevos y
///   conserva su calendario;
/// - el hueco que se agregó: una tarjeta nueva en el mismo grupo;
/// - el hueco que se sacó: su tarjeta se borra.
// ignore: one_member_abstracts
abstract interface class ClozeCardEditor {
  /// Cambia el texto de huecos de la tarjeta [cardId] (y de sus hermanas) a
  /// [text], con [extra] de complemento. Se rechaza sin tocar nada si [text]
  /// no sirve (sin huecos, o con uno roto) o si la tarjeta no es de huecos.
  Future<Either<Failure, ClozeEditOutcome>> edit({
    required String cardId,
    required String text,
    required String extra,
  });
}
