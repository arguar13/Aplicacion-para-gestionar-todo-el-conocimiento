import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';

/// Algo que la persona tiene que saber de su IA en la nube mientras pasa
/// (F32, decisión B): que se cambió de cuenta, que hay que esperar, que una
/// clave no anda o que no queda cuota. La app lo muestra en el momento, con
/// qué cuenta, por qué y hasta cuándo.
@immutable
sealed class AiNotice {
  const AiNotice({required this.at});

  /// Cuándo pasó.
  final DateTime at;
}

/// Una cuenta se quedó sin cuota (o su clave dejó de andar) y la app siguió
/// sola con otra.
final class AccountSwitchedNotice extends AiNotice {
  const AccountSwitchedNotice({
    required super.at,
    required this.from,
    required this.to,
    required this.reason,
    this.fromResetsAt,
  });

  final AiAccount from;
  final AiAccount to;

  /// Por qué se dejó [from].
  final CloudModelFailure reason;

  /// Cuándo vuelve a tener cuota [from], si se sabe.
  final DateTime? fromResetsAt;
}

/// No queda ninguna cuenta con cuota: hasta [resetsAt] la IA en la nube no
/// contesta.
final class AllAccountsExhaustedNotice extends AiNotice {
  const AllAccountsExhaustedNotice({
    required super.at,
    required this.provider,
    required this.accounts,
    this.resetsAt,
  });

  final AiProvider provider;

  /// Cuántas cuentas probó.
  final int accounts;

  /// La renovación más cercana de todas, si se sabe.
  final DateTime? resetsAt;
}

/// Se pasó el tope por minuto: la respuesta sigue sola en [wait].
final class RateLimitWaitNotice extends AiNotice {
  const RateLimitWaitNotice({
    required super.at,
    required this.account,
    required this.wait,
  });

  final AiAccount account;
  final Duration wait;
}

/// La clave de [account] no anda (mal copiada, revocada o sin permiso).
final class AccountKeyRejectedNotice extends AiNotice {
  const AccountKeyRejectedNotice({
    required super.at,
    required this.account,
    required this.reason,
  });

  final AiAccount account;
  final CloudModelFailure reason;
}

/// La IA de fondo llegó a su tope del día: deja la cuota restante para lo que
/// pide la persona.
final class BackgroundCapReachedNotice extends AiNotice {
  const BackgroundCapReachedNotice({
    required super.at,
    required this.cap,
    this.resetsAt,
  });

  final int cap;
  final DateTime? resetsAt;
}
