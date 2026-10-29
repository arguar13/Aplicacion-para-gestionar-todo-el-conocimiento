/// Lo común de dibujar las ilustraciones con IA de «Lo creado» (F43, decisión
/// H), para la infografía, el mazo y el cuestionario.
library;

import 'dart:async';

import 'package:sinapsis/features/ai_models/data/services/illustration_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// La cuenta que dibuja: la elegida en «Con tu IA actual» ([accountId]) o,
/// si no se eligió otra, la misma que escribe ([textAccountId]), como lo
/// estima el aviso (`CreationCostEstimator`). Nunca una que la persona no
/// vio: `null` si la IA actual no dibuja (Claude, Gemma) y no se eligió otra,
/// o si la elegida ya no está.
Future<IllustrationAccount?> creationIllustrationAccount(
  IllustrationService service, {
  required String? accountId,
  required Future<String?> Function() textAccountId,
}) async {
  final id = accountId ?? await textAccountId();
  if (id == null) return null;
  for (final account in await service.accounts()) {
    if (account.id == id) return account;
  }
  return null;
}

/// [work], o [CreationCancelledException] en cuanto se cancele [signal]: un
/// motor que no atiende el corte (el del teléfono a mitad de un paso) no deja
/// la creación esperando. Lo que [work] termine después se descarta.
Future<T> creationOrCancelled<T>(Future<T> work, CancellationSignal? signal) {
  if (signal == null) return work;
  final cut = signal.whenCancelled.then<T>(
    (_) => throw const CreationCancelledException(),
  );
  // Si la cancelación llega después de que [work] terminó, nadie la espera.
  unawaited(cut.then((_) {}, onError: (_) {}));
  work.ignore();
  return Future.any([work, cut]);
}

/// Lanza [CreationCancelledException] si [signal] ya se canceló.
void throwIfCreationCancelled(CancellationSignal? signal) {
  if (signal?.isCancelled ?? false) {
    throw const CreationCancelledException();
  }
}
