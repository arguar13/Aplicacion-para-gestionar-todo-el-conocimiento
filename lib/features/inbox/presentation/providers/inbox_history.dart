import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_step.dart';
import 'package:sinapsis/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';

/// El vínculo que crea «Vincular a nota viva»: la nota cita a la fuente. Uno
/// solo, para crearlo y para deshacerlo.
const kInboxLinkKind = RelationKind.cites;

/// Lo que se decidió en la Bandeja, de lo más viejo a lo más nuevo, para
/// deshacerlo de a un paso (F28).
///
/// **Alcance.** Vive mientras la app esté abierta: sobrevive a salir de la
/// Bandeja y volver —antes era un solo paso, en la memoria de la pantalla, y
/// se perdía al irse—, pero no a cerrar la app. Guarda hasta [capacity]
/// pasos; el más viejo se suelta cuando entra uno más.
///
/// Deshacer devuelve la fuente al estado en que estaba y revierte lo que la
/// acción hizo además: el vínculo con la nota viva y, si la nota nació en esa
/// misma acción, la manda a la papelera —de donde se recupera—. Lo que no es
/// de la acción sino de lo que se hizo después no se toca: las notas que se
/// extrajeron leyendo, o las sugerencias que se aplicaron al revisar, quedan;
/// se quitan desde el elemento, como cualquier otra.
class InboxHistory extends StateNotifier<List<InboxStep>> {
  InboxHistory({
    required InboxRepository Function() inbox,
    required OrganizeRepository Function() organize,
    required LibraryRepository Function() library,
  }) : _inbox = inbox,
       _organize = organize,
       _library = library,
       super(const []);

  /// Cuántos pasos se recuerdan: más que los que alguien deshace de un tirón,
  /// y pocos como para no acumular sin fin en una sesión larga de triaje.
  static const capacity = 50;

  final InboxRepository Function() _inbox;
  final OrganizeRepository Function() _organize;
  final LibraryRepository Function() _library;

  /// El último paso, el que deshace el próximo «Deshacer».
  InboxStep? get last => state.lastOrNull;

  void record(InboxStep step) {
    final steps = [...state, step];
    state = steps.length > capacity
        ? steps.sublist(steps.length - capacity)
        : steps;
  }

  /// Deshace el último paso y lo devuelve, o el fallo que lo impidió. `null`
  /// si no había nada que deshacer.
  ///
  /// El paso sale de la pila antes de intentarlo: uno que ya no se puede
  /// deshacer —la fuente se borró para siempre— se informa y se suelta, en
  /// vez de trabar los anteriores detrás de un fallo que se repetiría igual.
  Future<Either<Failure, InboxStep>?> undoLast() async {
    final step = last;
    if (step == null) return null;
    state = state.sublist(0, state.length - 1);

    final note = step.linkedNote;
    if (note != null) {
      final unlinked = await _organize().deleteRelationBetween(
        fromItemId: note.id,
        toItemId: step.itemId,
        kind: kInboxLinkKind,
      );
      if (unlinked.getLeft().toNullable() case final failure?) {
        return left(failure);
      }
      if (note.created) {
        final trashed = await _library().delete(note.id);
        if (trashed.getLeft().toNullable() case final failure?) {
          return left(failure);
        }
      }
    }

    final restored = await _inbox().transitionState(
      itemId: step.itemId,
      to: step.previousState,
    );
    return restored.map((_) => step);
  }
}

final inboxHistoryProvider =
    StateNotifierProvider<InboxHistory, List<InboxStep>>((ref) {
      return InboxHistory(
        inbox: () => ref.read(inboxRepositoryProvider),
        organize: () => ref.read(organizeRepositoryProvider),
        library: () => ref.read(libraryRepositoryProvider),
      );
    });
