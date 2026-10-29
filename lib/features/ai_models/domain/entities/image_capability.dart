import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';

/// Lo que se sabe de una cuenta para dibujar (F43): **puede**, **no puede**
/// (con el porqué) o **sin probar**.
enum ImageCapabilityState { can, cannot, untested }

/// Lo que se sabe de una cuenta para dibujar, recordado del primer pedido de
/// imagen de verdad (o de «Probar ahora»).
///
/// Solo cambia por lo que dice algo de la cuenta: una imagen que salió (puede)
/// o un rechazo de la cuenta —sin facturación, organización sin verificar,
/// sin créditos, la clave— (no puede). Sin internet, el tope por minuto o un
/// dibujo rechazado por su contenido no dicen nada de la cuenta y no la
/// cambian.
@immutable
class ImageCapability {
  const ImageCapability({
    required this.state,
    this.reason,
    this.model,
    this.checkedAt,
  });

  const ImageCapability.untested() : this(state: ImageCapabilityState.untested);

  /// Lo que se sabe después de un pedido que salió con [model].
  factory ImageCapability.succeeded(String model, DateTime at) =>
      ImageCapability(
        state: ImageCapabilityState.can,
        model: model,
        checkedAt: at.toUtc(),
      );

  /// Lo que se sabe después de un pedido que falló por [failure]: si es de la
  /// cuenta, no puede; si no, lo de antes ([previous]).
  factory ImageCapability.afterFailure(
    ImageCapability previous,
    ImageFailure failure, {
    required DateTime at,
    String? model,
  }) {
    if (!failure.isAboutAccount) return previous;
    return ImageCapability(
      state: ImageCapabilityState.cannot,
      reason: failure,
      model: model ?? previous.model,
      checkedAt: at.toUtc(),
    );
  }

  static ImageCapability? fromJson(Object? json) {
    if (json is! Map) return null;
    final state = ImageCapabilityState.values
        .where((s) => s.name == json['state'])
        .firstOrNull;
    if (state == null) return null;
    final reason = ImageFailure.values
        .where((f) => f.name == json['reason'])
        .firstOrNull;
    final model = json['model'];
    return ImageCapability(
      state: state,
      reason: state == ImageCapabilityState.cannot ? reason : null,
      model: model is String && model.isNotEmpty ? model : null,
      checkedAt: DateTime.tryParse(json['checkedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final ImageCapabilityState state;

  /// Por qué no puede; solo con [ImageCapabilityState.cannot].
  final ImageFailure? reason;

  /// Con qué modelo se probó.
  final String? model;

  /// Cuándo se supo.
  final DateTime? checkedAt;

  bool get can => state == ImageCapabilityState.can;
  bool get cannot => state == ImageCapabilityState.cannot;
  bool get untested => state == ImageCapabilityState.untested;

  Map<String, Object> toJson() => {
    'state': state.name,
    if (reason != null) 'reason': reason!.name,
    'model': ?model,
    if (checkedAt != null) 'checkedAt': checkedAt!.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is ImageCapability &&
      other.state == state &&
      other.reason == reason &&
      other.model == model &&
      other.checkedAt == checkedAt;

  @override
  int get hashCode => Object.hash(state, reason, model, checkedAt);

  @override
  String toString() => 'ImageCapability(${state.name}, ${reason?.name})';
}
