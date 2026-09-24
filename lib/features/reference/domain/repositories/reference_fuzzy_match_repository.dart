import 'package:sinapsis/features/reference/domain/entities/reference_fuzzy_index.dart';

/// Arma [ReferenceFuzzyIndex] a partir de lo que ya hay en la bóveda (F15,
/// D9), una vez por corrida de importación —igual que el de identidad
/// exacta—.
// ignore: one_member_abstracts
abstract interface class ReferenceFuzzyMatchRepository {
  Future<ReferenceFuzzyIndex> buildIndex();
}
