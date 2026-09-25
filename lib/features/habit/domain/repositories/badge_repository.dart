import 'package:sinapsis/features/habit/domain/entities/badge_kind.dart';

/// Las insignias ganadas ahora mismo (F17, D7).
abstract interface class BadgeRepository {
  Future<Set<BadgeKind>> earned();

  /// Se vuelve a emitir sola cuando cambia algo que puede ganar o perder
  /// una insignia.
  Stream<Set<BadgeKind>> watch();
}
