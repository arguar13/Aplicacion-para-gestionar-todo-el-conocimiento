import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_receipt.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/flashcard_option.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/sibling_card_draft.dart';

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
  ///
  /// Las formas de F31: con `cloze`, [front] es el texto ENTERO con sus huecos
  /// marcados, [back] un complemento que puede quedar vacío, y [clozeIndex]
  /// (desde 1) dice cuál hueco tapa esta tarjeta —obligatorio con `cloze`,
  /// prohibido con las demás—. `typedAnswer` es como `freeRecall`: [back] es la
  /// respuesta con la que se compara lo que la persona escribe. [groupId] la
  /// declara hermana de otras (ver [createSiblings], que lo arma solo).
  ///
  /// Con [ai] la crea la IA (F27): queda marcada como suya, con su pasada. Se
  /// rechaza, sin escribir nada, si la persona ya dijo que esa pregunta
  /// —normalizada: sin mayúsculas, acentos ni signos— «no era» en este
  /// elemento.
  Future<Either<Failure, Flashcard>> create({
    required String itemId,
    required String front,
    required String back,
    int? sourceCharStart,
    int? sourceCharEnd,
    FlashcardKind kind = FlashcardKind.freeRecall,
    AiProvenance? ai,
    String? groupId,
    int? clozeIndex,
  });

  /// Crea varias tarjetas hermanas de una vez (F31): las dos direcciones de una
  /// pregunta o los huecos de un texto (`SiblingCardDraft.bothDirections`,
  /// `SiblingCardDraft.clozes`). Todas comparten un `group_id` nuevo; se crean
  /// en UNA transacción —todas o ninguna— y se devuelven en el orden de
  /// [drafts]. Hace falta al menos dos.
  ///
  /// Cada una pasa por las mismas validaciones que [create], y con [ai] por el
  /// mismo filtro de lo que «no era».
  Future<Either<Failure, List<Flashcard>>> createSiblings({
    required String itemId,
    required List<SiblingCardDraft> drafts,
    AiProvenance? ai,
  });

  /// Crea una tarjeta de opción múltiple (F20) para [itemId]: [front] es la
  /// pregunta, [options] sus opciones —cada una con su propio texto, si es
  /// la correcta y su propia procedencia—.
  ///
  /// Se rechaza sin guardar nada si [options] tiene menos de dos, si ninguna
  /// —o más de una— está marcada correcta, o si alguna llega con el texto
  /// vacío. La tarjeta y sus opciones se guardan en UNA transacción
  /// (decisión D, F20): todo o nada.
  ///
  /// [ai], igual que en [create] (F27).
  Future<Either<Failure, Flashcard>> createMultipleChoice({
    required String itemId,
    required String front,
    required List<FlashcardOptionDraft> options,
    AiProvenance? ai,
  });

  /// Las opciones de la tarjeta [flashcardId], en el orden en que se
  /// guardaron. Vacío si la tarjeta no es de opción múltiple.
  Future<Either<Failure, List<FlashcardOption>>> optionsFor(String flashcardId);

  /// Cambia la pregunta y la respuesta de la tarjeta [id]. El calendario de
  /// repaso no cambia: es la misma tarjeta, mejor escrita.
  ///
  /// Editar es adoptar (F27): una que hizo la IA pasa a ser de la persona, sin
  /// pasada, y «deshacer todo» ya no se la lleva.
  Future<Either<Failure, Flashcard>> update({
    required String id,
    required String front,
    required String back,
  });

  Future<Either<Failure, Unit>> delete(String id);

  /// «No era» (F27): borra la tarjeta que hizo la IA y recuerda su pregunta
  /// en ese elemento, para que no la vuelva a proponer. El comprobante sirve
  /// para [restoreRejectedFlashcard]. Se rechaza si la tarjeta es de la
  /// persona: eso se borra, no se le dice a la IA que no.
  Future<Either<Failure, AiRejectionReceipt>> rejectAiFlashcard(String id);

  /// Deshace un [rejectAiFlashcard]: la tarjeta vuelve entera —su
  /// calendario, sus opciones y sus repasos— y la IA la puede volver a
  /// proponer.
  Future<Either<Failure, Unit>> restoreRejectedFlashcard(
    AiRejectionReceipt receipt,
  );

  /// Aplica [grade] a la tarjeta [id] con el algoritmo SM-2 y guarda el
  /// resultado. Devuelve la tarjeta ya actualizada, con su próxima fecha de
  /// repaso.
  Future<Either<Failure, Flashcard>> review({
    required String id,
    required ReviewGrade grade,
  });

  /// Deshace la última respuesta (F31): devuelve la tarjeta EXACTAMENTE a como
  /// estaba antes —facilidad, intervalo, repeticiones, paso de aprendizaje,
  /// cuándo tocaba y cuándo se había repasado— y borra el renglón de
  /// `review_log` de esa respuesta.
  ///
  /// La racha y las insignias no necesitan un trato aparte: salen de
  /// `review_log` (ver `HabitActivityDays`), así que al borrarse el renglón,
  /// un día que solo tenía esa respuesta deja de contar, y «100 repasos»
  /// vuelve a 99. Lo mismo la cola de estudio: el límite del día recupera la
  /// tarjeta nueva o el repaso, y sus hermanas vuelven a aparecer hoy.
  ///
  /// «La última» es la más reciente de ESTE dispositivo. Con [since], solo si
  /// es de ese momento en adelante —la pantalla pasa cuándo empezó la
  /// sesión—, para no deshacer algo de ayer al abrir el repaso. Se rechaza, sin
  /// tocar nada, si:
  ///
  /// - no hay respuesta que deshacer;
  /// - es de antes de v39, que no guardó cómo estaba la tarjeta;
  /// - la tarjeta ya cambió después de esa respuesta (por ejemplo, otra
  ///   respuesta más nueva llegada de otro dispositivo, o ya se deshizo):
  ///   restaurarla pisaría un repaso real.
  ///
  /// Se puede llamar varias veces seguidas: deshace una respuesta tras otra,
  /// de la más nueva a la más vieja.
  Future<Either<Failure, Flashcard>> undoLastReview({DateTime? since});

  /// Pausa las tarjetas [ids] (F31): no entran en ninguna sesión hasta
  /// reactivarlas con [unsuspend]. Su calendario no cambia, y exportadas a Anki
  /// salen como suspendidas.
  Future<Either<Failure, Unit>> suspend(Iterable<String> ids);

  /// Reactiva las tarjetas [ids] pausadas: vuelven con el calendario que
  /// tenían.
  Future<Either<Failure, Unit>> unsuspend(Iterable<String> ids);

  /// Pospone las tarjetas [ids] hasta el próximo día de estudio (F31): hoy no
  /// aparecen más, y mañana desde las 4:00 vuelven solas (`StudyDay`). No
  /// cambia su calendario.
  Future<Either<Failure, Unit>> buryUntilTomorrow(Iterable<String> ids);

  /// Quita la posposición de [ids]: vuelven a entrar hoy. Para deshacer un
  /// [buryUntilTomorrow].
  Future<Either<Failure, Unit>> unbury(Iterable<String> ids);

  /// Las tarjetas de un elemento, en el orden en que se crearon.
  Stream<List<Flashcard>> watchForItem(String itemId);

  /// Todas las tarjetas de la bóveda, sin importar si ya toca repasarlas.
  ///
  /// No filtra por fecha: es lo que necesita exportar «todo el mazo» a Anki
  /// (F17, D4) —o repasar sin límite—, donde el repaso sigue después de
  /// exportado y no solo lo que vence hoy. Lo que toca estudiar hoy lo
  /// decide la cola de estudio (`StudyRepository`), no esta lectura.
  Future<Either<Failure, List<Flashcard>>> getAll();

  /// Las tarjetas que nunca entraron en ninguna exportación exitosa a Anki
  /// —`lastExportedAt` nulo—, para el camino incremental (F17, D4).
  /// «Exportar todo» sigue siendo [getAll], sin este filtro.
  Future<Either<Failure, List<Flashcard>>> getPendingExport();

  /// Marca [ids] como recién exportadas, con la hora de ahora (F17, D4): el
  /// próximo incremental las deja afuera hasta que vuelvan a ser «nuevas»
  /// —por ejemplo, si se borran y se recrean—.
  Future<Either<Failure, Unit>> markExported(Set<String> ids);
}
