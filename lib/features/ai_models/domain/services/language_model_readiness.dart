import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';

/// Si el modelo de lenguaje elegido puede contestar ahora y, si no, qué le
/// falta (F32). Antes había una sola respuesta —«falta bajar el modelo»—;
/// con la nube faltan cosas distintas, y cada pantalla dice la que es.
@immutable
sealed class LanguageModelStatus {
  const LanguageModelStatus({required this.provider});

  /// El proveedor elegido.
  final AiProvider provider;

  bool get isReady => this is LanguageModelReady;
}

/// Puede contestar.
final class LanguageModelReady extends LanguageModelStatus {
  const LanguageModelReady({required super.provider});
}

/// Está elegido Gemma y falta bajarlo.
final class LanguageModelNeedsDownload extends LanguageModelStatus {
  const LanguageModelNeedsDownload() : super(provider: AiProvider.gemma);
}

/// Está elegido un proveedor en la nube y no tiene ninguna cuenta con clave.
final class LanguageModelNeedsAccount extends LanguageModelStatus {
  const LanguageModelNeedsAccount({required super.provider});
}

/// Ninguna cuenta que se pueda usar tiene cuota (o todas tienen la clave
/// rechazada): hasta [resetsAt] no contesta.
final class LanguageModelOutOfQuota extends LanguageModelStatus {
  const LanguageModelOutOfQuota({
    required super.provider,
    required this.accounts,
    this.resetsAt,
    this.keysRejected = false,
  });

  /// Cuántas cuentas se miraron.
  final int accounts;

  /// La renovación más cercana, si se sabe.
  final DateTime? resetsAt;

  /// Si lo que las deja afuera es la clave, no la cuota.
  final bool keysRejected;
}

/// La IA de fondo llegó a su tope de pedidos del día; lo que pide la persona
/// sigue andando. Solo lo ve quien pregunta por la IA de fondo.
final class LanguageModelBackgroundCapReached extends LanguageModelStatus {
  const LanguageModelBackgroundCapReached({
    required super.provider,
    required this.cap,
    required this.resetsAt,
  });

  final int cap;
  final DateTime resetsAt;
}

/// Lo que pasa ahora con el modelo elegido (F32). Con `background`, también
/// cuenta el tope diario de la IA de fondo.
typedef LanguageModelStatusCheck =
    Future<LanguageModelStatus> Function({bool background});
