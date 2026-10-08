import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_providers.dart';
import 'package:sinapsis/features/inbox/data/repositories/inbox_repository_impl.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_standing.dart';
import 'package:sinapsis/features/inbox/domain/entities/note_reference.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_source.dart';
import 'package:sinapsis/features/inbox/domain/entities/source_extent.dart';
import 'package:sinapsis/features/inbox/domain/repositories/inbox_repository.dart';

/// Cascada de inyección del feature. La capa de presentación depende de
/// este repositorio; nunca de la base de datos directamente.
final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  return InboxRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Los ids de las fuentes que esperan triaje, actualizándose solos.
/// `autoDispose`: sin nadie mirando la Bandeja ni la insignia de la
/// navegación, no hace falta mantener la suscripción viva.
final inboxPendingIdsProvider = StreamProvider.autoDispose<List<String>>((ref) {
  return ref.watch(inboxRepositoryProvider).watchPendingIds();
});

/// La cola entera de la Bandeja, para la lista detrás de «N pendientes»
/// (F28). `autoDispose`: solo hace falta mientras la lista está abierta.
final inboxPendingProvider = StreamProvider.autoDispose<List<PendingSource>>((
  ref,
) {
  return ref.watch(inboxRepositoryProvider).watchPending();
});

/// La fuente que se eligió de la lista de la cola para tenerla arriba del
/// mazo (F28), o la que se acaba de devolver con «Deshacer». `null` es el
/// orden de siempre: la que lleva más tiempo esperando.
///
/// Sin `autoDispose`: el detalle de un elemento la pone antes de abrir la
/// Bandeja —«Triar ahora»—, cuando todavía nadie la mira. Si esa fuente ya
/// no está pendiente, el mazo la ignora y sigue con la primera.
final inboxFocusedIdProvider = StateProvider<String?>((ref) => null);

/// Dónde está un elemento respecto de la Bandeja, y desde cuándo (F28): el
/// chip del detalle.
final inboxStandingProvider = StreamProvider.autoDispose
    .family<InboxStanding?, String>((ref, itemId) {
      return ref.watch(inboxRepositoryProvider).watchStanding(itemId);
    });

/// Cuánto es lo que espera en la Bandeja —las páginas, lo que dura—, para la
/// línea de datos de la tarjeta (F30, decisión 68).
final inboxExtentProvider = StreamProvider.autoDispose
    .family<SourceExtent, String>((ref, itemId) {
      return ref.watch(inboxRepositoryProvider).watchExtent(itemId);
    });

/// El texto de un archivo del «Contenido» de `itemId`, con su nombre: lo que
/// la tarjeta de la Bandeja muestra cuando el elemento en sí no tiene texto
/// (F30, decisión 68) —una publicación sin pie de foto cuyas fotos traen
/// texto, una página que solo enlaza un PDF—. `null` si ningún archivo lo
/// tiene.
///
/// El primero en el orden de la página que tenga algo que leer: la tarjeta
/// muestra un fragmento, no el «Contenido» entero.
final inboxContentTextProvider = FutureProvider.autoDispose
    .family<({String name, String text})?, String>((ref, itemId) async {
      final attachments = ref.watch(attachmentRepositoryProvider);
      for (final attachment in await attachments.attachmentsOf(itemId)) {
        if (!attachment.hasText) continue;
        final text = await attachments.textOf(attachment.id);
        if (text != null && text.trim().isNotEmpty) {
          return (name: attachment.displayName, text: text);
        }
      }
      return null;
    });

/// Si ya se leyó —y se cerró— la tarjeta que explica qué es triar (F28),
/// entre reinicios: se muestra una vez, no cada vez que se abre la Bandeja.
class InboxIntroNotifier extends StateNotifier<bool> {
  InboxIntroNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(prefs.getBool(prefsKey) ?? false);

  static const prefsKey = 'inbox_intro_dismissed';

  final SharedPreferences _prefs;

  Future<void> dismiss() async {
    state = true;
    await _prefs.setBool(prefsKey, true);
  }
}

final inboxIntroDismissedProvider =
    StateNotifierProvider<InboxIntroNotifier, bool>((ref) {
      return InboxIntroNotifier(prefs: ref.watch(sharedPreferencesProvider));
    });

/// Las notas vivas que existen, para el selector de "vincular a nota
/// viva". `null` como clave de familia es "sin texto buscado", todas.
final livingNotesProvider = StreamProvider.autoDispose
    .family<List<NoteReference>, String?>((ref, searchText) {
      return ref
          .watch(inboxRepositoryProvider)
          .watchLivingNotes(searchText: searchText);
    });

/// La madurez de un elemento, si es una nota, actualizándose sola.
final noteMaturityProvider = StreamProvider.autoDispose
    .family<NoteMaturity?, String>((ref, itemId) {
      return ref.watch(inboxRepositoryProvider).watchNoteMaturity(itemId);
    });

/// El tipo de un elemento, si es una nota, actualizándose solo.
final noteKindProvider = StreamProvider.autoDispose.family<NoteKind?, String>((
  ref,
  itemId,
) {
  return ref.watch(inboxRepositoryProvider).watchNoteKind(itemId);
});
