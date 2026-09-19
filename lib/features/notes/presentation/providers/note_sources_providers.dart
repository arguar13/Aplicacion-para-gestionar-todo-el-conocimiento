import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/notes/data/repositories/note_sources_repository_impl.dart';
import 'package:sinapsis/features/notes/domain/entities/cited_source.dart';
import 'package:sinapsis/features/notes/domain/repositories/note_sources_repository.dart';

final noteSourcesRepositoryProvider = Provider<NoteSourcesRepository>((ref) {
  return NoteSourcesRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  );
});

/// Las fuentes que cita una nota, actualizándose solas.
final citedSourcesProvider = StreamProvider.autoDispose
    .family<List<CitedSource>, String>((ref, noteId) {
      return ref.watch(noteSourcesRepositoryProvider).watchCitedSources(noteId);
    });
