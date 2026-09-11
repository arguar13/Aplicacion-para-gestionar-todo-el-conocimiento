import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// El reloj del sistema. Se sobreescribe en los tests que necesiten controlar
/// el paso del tiempo.
final clockProvider = Provider<Clock>((ref) => DateTime.now);

/// El generador de identificadores. Se sobreescribe en los tests que
/// necesiten saber de antemano qué identificador va a tener lo que se guarde.
final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => const UuidV7Generator(),
);
