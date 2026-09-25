import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/notes/data/repositories/derived_note_repository_impl.dart';
import 'package:sinapsis/features/notes/domain/entities/derived_note_mark.dart';
import 'package:sinapsis/features/notes/domain/repositories/derived_note_repository.dart';

final derivedNoteRepositoryProvider = Provider<DerivedNoteRepository>((ref) {
  return DerivedNoteRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
  );
});

/// La marca de procedencia de una nota, actualizándose sola. `null` si no es
/// un derivado.
final derivedNoteMarkProvider = StreamProvider.autoDispose
    .family<DerivedNoteMark?, String>((ref, itemId) {
      return ref.watch(derivedNoteRepositoryProvider).watchMark(itemId);
    });
