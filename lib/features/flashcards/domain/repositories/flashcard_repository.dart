import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';

/// Crear, repasar y borrar tarjetas: todo lo que necesita esta parte de la
/// app.
abstract interface class FlashcardRepository {
  /// Crea una tarjeta nueva para [itemId], lista para repasarse desde ya
  /// —`dueAt` en el momento de crearla, no en el futuro—: una tarjeta recién
  /// hecha es, por definición, algo que todavía no se repasó ni una vez.
  Future<Either<Failure, Flashcard>> create({
    required String itemId,
    required String front,
    required String back,
  });

  Future<Either<Failure, Flashcard>> update({
    required String id,
    required String front,
    required String back,
  });

  Future<Either<Failure, Unit>> delete(String id);

  /// Aplica [grade] a la tarjeta [id] con el algoritmo SM-2 y guarda el
  /// resultado. Devuelve la tarjeta ya actualizada, con su próxima fecha de
  /// repaso.
  Future<Either<Failure, Flashcard>> review({
    required String id,
    required ReviewGrade grade,
  });

  /// Las tarjetas de un elemento, en el orden en que se crearon.
  Stream<List<Flashcard>> watchForItem(String itemId);

  /// Las tarjetas de toda la bóveda que ya toca repasar —`dueAt` vencido—,
  /// para la pantalla de repaso diario.
  Stream<List<Flashcard>> watchDue();

  /// Cuántas tarjetas hay para repasar ahora, sin traerlas: para la
  /// insignia del ícono de repaso en la biblioteca.
  Stream<int> watchDueCount();
}
