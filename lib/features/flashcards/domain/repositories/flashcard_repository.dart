import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/flashcard_option.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';

/// Crear, repasar y borrar tarjetas: todo lo que necesita esta parte de la
/// app.
abstract interface class FlashcardRepository {
  /// Crea una tarjeta nueva para [itemId], lista para repasarse desde ya
  /// —`dueAt` en el momento de crearla, no en el futuro—: una tarjeta recién
  /// hecha es, por definición, algo que todavía no se repasó ni una vez.
  ///
  /// [sourceCharStart] y [sourceCharEnd], juntos, dicen de qué fragmento de la
  /// fuente sale (F11): el rango `[start, end)` de la forma principal del
  /// elemento. Con él la tarjeta puede llevar de vuelta a su fuente. Se rechaza
  /// un rango a medias, negativo o vacío. El chunk que lo contiene lo busca el
  /// repositorio; si el elemento no tiene chunks, se guarda solo el rango.
  ///
  /// [kind] es `freeRecall` por defecto —pregunta y respuesta libres, lo que
  /// esto siempre fue—. Con `trueFalse` (F20), [front] es la afirmación y
  /// [back] por qué es verdadera o falsa; no lleva opciones aparte, así que
  /// no hace falta [createMultipleChoice] para esta forma. `multipleChoice`
  /// no se crea acá: usa [createMultipleChoice], que además necesita sus
  /// opciones.
  Future<Either<Failure, Flashcard>> create({
    required String itemId,
    required String front,
    required String back,
    int? sourceCharStart,
    int? sourceCharEnd,
    FlashcardKind kind = FlashcardKind.freeRecall,
  });

  /// Crea una tarjeta de opción múltiple (F20) para [itemId]: [front] es la
  /// pregunta, [options] sus opciones —cada una con su propio texto, si es
  /// la correcta y su propia procedencia—.
  ///
  /// Se rechaza sin guardar nada si [options] tiene menos de dos, si ninguna
  /// —o más de una— está marcada correcta, o si alguna llega con el texto
  /// vacío. La tarjeta y sus opciones se guardan en UNA transacción
  /// (decisión D, F20): todo o nada.
  Future<Either<Failure, Flashcard>> createMultipleChoice({
    required String itemId,
    required String front,
    required List<FlashcardOptionDraft> options,
  });

  /// Las opciones de la tarjeta [flashcardId], en el orden en que se
  /// guardaron. Vacío si la tarjeta no es de opción múltiple.
  Future<Either<Failure, List<FlashcardOption>>> optionsFor(String flashcardId);

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

  /// Todas las tarjetas de la bóveda, sin importar si ya toca repasarlas.
  ///
  /// A diferencia de [watchDue], no filtra por fecha: es lo que necesita
  /// exportar «todo el mazo» a Anki (F17, D4) —o repasar sin límite—, donde
  /// el repaso sigue después de exportado y no solo lo que vence hoy.
  Future<Either<Failure, List<Flashcard>>> getAll();

  /// Las tarjetas que nunca entraron en ninguna exportación exitosa a Anki
  /// —`lastExportedAt` nulo—, para el camino incremental (F17, D4).
  /// «Exportar todo» sigue siendo [getAll], sin este filtro.
  Future<Either<Failure, List<Flashcard>>> getPendingExport();

  /// Marca [ids] como recién exportadas, con la hora de ahora (F17, D4): el
  /// próximo incremental las deja afuera hasta que vuelvan a ser «nuevas»
  /// —por ejemplo, si se borran y se recrean—.
  Future<Either<Failure, Unit>> markExported(Set<String> ids);

  /// Las tarjetas de toda la bóveda que ya toca repasar —`dueAt` vencido—,
  /// para la pantalla de repaso diario.
  Stream<List<Flashcard>> watchDue();

  /// Cuántas tarjetas hay para repasar ahora, sin traerlas: para la
  /// insignia del ícono de repaso en la biblioteca.
  Stream<int> watchDueCount();
}
