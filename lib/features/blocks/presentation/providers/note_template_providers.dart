import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/note_template.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/blocks/data/repositories/note_template_repository_impl.dart';
import 'package:sinapsis/features/blocks/domain/repositories/note_template_repository.dart';

/// Cascada de inyección de las plantillas de nota (F16).
final noteTemplateRepositoryProvider = Provider<NoteTemplateRepository>((ref) {
  return NoteTemplateRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Las plantillas de nota, actualizándose solas.
final noteTemplatesProvider = StreamProvider.autoDispose<List<NoteTemplate>>((
  ref,
) {
  return ref.watch(noteTemplateRepositoryProvider).watchAll();
});
