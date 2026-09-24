import 'package:sinapsis/features/reference/domain/entities/reference_identity_index.dart';

/// Arma el índice de identidad de toda la bóveda (F15, D9), para que una
/// importación de muchas entradas no compare cada una contra la base por
/// separado.
// ignore: one_member_abstracts
abstract interface class ReferenceIdentityRepository {
  Future<ReferenceIdentityIndex> buildIndex();
}
