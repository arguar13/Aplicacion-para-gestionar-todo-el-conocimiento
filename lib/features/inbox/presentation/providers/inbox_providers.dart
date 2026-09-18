import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/inbox/data/repositories/inbox_repository_impl.dart';
import 'package:sinapsis/features/inbox/domain/entities/note_reference.dart';
import 'package:sinapsis/features/inbox/domain/repositories/inbox_repository.dart';

/// Cascada de inyección del feature. La capa de presentación depende de
/// este repositorio; nunca de la base de datos directamente.
final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  return InboxRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  );
});

/// Los ids de las fuentes que esperan triaje, actualizándose solos.
/// `autoDispose`: sin nadie mirando la Bandeja ni la insignia de la
/// navegación, no hace falta mantener la suscripción viva.
final inboxPendingIdsProvider = StreamProvider.autoDispose<List<String>>((ref) {
  return ref.watch(inboxRepositoryProvider).watchPendingIds();
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
