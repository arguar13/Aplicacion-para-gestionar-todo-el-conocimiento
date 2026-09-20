import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/features/vault/data/repositories/merge_conflict_repository_impl.dart';
import 'package:sinapsis/features/vault/domain/entities/merge_conflict.dart';
import 'package:sinapsis/features/vault/domain/repositories/merge_conflict_repository.dart';

final mergeConflictRepositoryProvider = Provider<MergeConflictRepository>((
  ref,
) {
  return MergeConflictRepositoryImpl(database: ref.watch(appDatabaseProvider));
});

/// Los conflictos que dejó una fusión y nadie revisó (F11), en vivo: al
/// resolver uno desaparece, y al fusionar aparecen los nuevos.
final pendingMergeConflictsProvider =
    StreamProvider.autoDispose<List<MergeConflict>>((ref) {
      return ref.watch(mergeConflictRepositoryProvider).watchPending();
    });
