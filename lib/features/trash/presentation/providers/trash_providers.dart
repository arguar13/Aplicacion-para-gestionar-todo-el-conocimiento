import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/library/domain/entities/trashed_item.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';

/// Lo que hay en la papelera, del más reciente al más viejo, actualizándose
/// solo (F11).
///
/// `autoDispose` porque el stream mantiene abierta una suscripción a los
/// cambios de la base: sin nadie mirando la papelera no hace falta.
final trashProvider = StreamProvider.autoDispose<List<TrashedItem>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchTrash();
});
