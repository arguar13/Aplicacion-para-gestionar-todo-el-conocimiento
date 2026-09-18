import 'package:sinapsis/features/duplicates/domain/entities/merged_provenance.dart';

/// Procedencias fusionadas ya persistidas — F7, deduplicación.
///
/// De solo lectura: quien las crea es `MergeDuplicateItemsUseCase`, al
/// fusionar; esto solo las expone para mostrarlas en el detalle del
/// elemento que sobrevivió.
// ignore: one_member_abstracts
abstract interface class DuplicateProvenanceRepository {
  Stream<List<MergedProvenance>> watchMergedProvenancesForItem(String itemId);
}
