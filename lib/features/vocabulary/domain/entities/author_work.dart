import 'package:sinapsis/core/domain/entities/contributor_role.dart';

/// Una obra en la que figura una persona (F15): lo que «las obras de este
/// autor» muestra de cada una.
class AuthorWork {
  const AuthorWork({
    required this.itemId,
    required this.title,
    required this.role,
  });

  /// La fuente.
  final String itemId;

  /// Su título.
  final String title;

  /// Qué hizo la persona en la obra: autora, traductora, editora o directora.
  final ContributorRole role;
}
