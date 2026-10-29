import 'package:meta/meta.dart';

/// La cuota diaria de una cuenta (F43), como la fija la persona en Ajustes →
/// IA: pedidos, tokens e imágenes por día, o un tope en dólares. Cualquiera
/// puede faltar; la que falta no cuenta.
///
/// Los proveedores no dicen cuánto queda de la capa gratuita (F32): el «≈ 18 %
/// de tu cuota de hoy» es contra esto. Hasta que la persona la fija, se usa
/// la estimada de la tabla fechada ([isEstimate]).
@immutable
class DailyQuota {
  const DailyQuota({
    this.requests,
    this.tokens,
    this.images,
    this.usd,
    this.isEstimate = false,
  });

  /// Sin ningún tope.
  static const none = DailyQuota();

  static DailyQuota? fromJson(Object? json) {
    if (json is! Map) return null;
    int? count(String key) {
      final value = json[key];
      return value is int && value > 0 ? value : null;
    }

    final usd = json['usd'];
    return DailyQuota(
      requests: count('requests'),
      tokens: count('tokens'),
      images: count('images'),
      usd: usd is num && usd > 0 ? usd.toDouble() : null,
    );
  }

  final int? requests;
  final int? tokens;
  final int? images;
  final double? usd;

  /// Si es la de la tabla, no la que puso la persona: se muestra «estimado».
  final bool isEstimate;

  /// Si no topea nada.
  bool get isEmpty =>
      requests == null && tokens == null && images == null && usd == null;

  Map<String, Object> toJson() => {
    'requests': ?requests,
    'tokens': ?tokens,
    'images': ?images,
    'usd': ?usd,
  };

  DailyQuota asEstimate() => DailyQuota(
    requests: requests,
    tokens: tokens,
    images: images,
    usd: usd,
    isEstimate: true,
  );

  @override
  bool operator ==(Object other) =>
      other is DailyQuota &&
      other.requests == requests &&
      other.tokens == tokens &&
      other.images == images &&
      other.usd == usd &&
      other.isEstimate == isEstimate;

  @override
  int get hashCode => Object.hash(requests, tokens, images, usd, isEstimate);

  @override
  String toString() =>
      'DailyQuota(requests: $requests, tokens: $tokens, images: $images, '
      'usd: $usd${isEstimate ? ', estimado' : ''})';
}
