import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';

/// Lo que gastó una cuenta en un día de cuota (F32), contado por la app: los
/// proveedores no dicen cuánto queda de la capa gratuita, así que esto es lo
/// que se sabe —cuánto se pidió desde este teléfono— y cuándo dijo el
/// proveedor que se terminó.
@immutable
class AccountUsage {
  const AccountUsage({
    required this.accountId,
    required this.day,
    this.requests = 0,
    this.backgroundRequests = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.images = 0,
    this.imageTokens = 0,
    this.spentMicroUsd = 0,
    this.exhaustedUntil,
    this.lastFailure,
  });

  /// Lo leído de [toJson], o `null` si no se entiende.
  static AccountUsage? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['accountId'];
    final day = json['day'];
    if (id is! String || day is! String) return null;
    int count(String key) {
      final value = json[key];
      return value is int && value >= 0 ? value : 0;
    }

    final until = DateTime.tryParse(json['exhaustedUntil'] as String? ?? '');
    final failure = json['lastFailure'];
    return AccountUsage(
      accountId: id,
      day: day,
      requests: count('requests'),
      backgroundRequests: count('backgroundRequests'),
      inputTokens: count('inputTokens'),
      outputTokens: count('outputTokens'),
      images: count('images'),
      imageTokens: count('imageTokens'),
      spentMicroUsd: count('spentMicroUsd'),
      exhaustedUntil: until?.toUtc(),
      lastFailure: CloudModelFailure.values
          .where((f) => f.name == failure)
          .firstOrNull,
    );
  }

  final String accountId;

  /// El día de la cuota (`quotaDayOf`).
  final String day;

  /// Pedidos hechos ese día, de la persona y de la IA de fondo.
  final int requests;

  /// De esos, los de la IA de fondo: es lo que topea
  /// `AiModelSettings.backgroundDailyCap`.
  final int backgroundRequests;

  final int inputTokens;
  final int outputTokens;

  /// Ilustraciones dibujadas ese día (F43). Cada una cuenta también como un
  /// pedido; sus tokens van aparte, en [imageTokens]: [inputTokens] y
  /// [outputTokens] siguen siendo los del texto, que se cobran a otro precio.
  final int images;

  /// Los tokens de las ilustraciones de ese día (la descripción y la imagen).
  final int imageTokens;

  /// Todos los tokens del día: los del texto y los de las ilustraciones.
  int get totalTokens => inputTokens + outputTokens + imageTokens;

  /// Lo gastado en las ilustraciones de ese día, en millonésimas de dólar
  /// (F43): con los tokens que contó el proveedor y la tabla de precios
  /// fechada. Es una estimación —el proveedor no dice lo cobrado—, y lo de
  /// texto no está: sale de los tokens y el modelo, al calcularlo.
  final int spentMicroUsd;

  /// Lo gastado en ilustraciones, en dólares.
  double get spentUsd => spentMicroUsd / 1e6;

  /// Hasta cuándo esta cuenta no tiene cuota, según lo último que dijo el
  /// proveedor. `null`: no se sabe que esté agotada.
  final DateTime? exhaustedUntil;

  /// El último problema que tuvo, para mostrarlo.
  final CloudModelFailure? lastFailure;

  /// Si en [now] la cuenta sigue sin cuota.
  bool isExhaustedAt(DateTime now) {
    final until = exhaustedUntil;
    return until != null && now.toUtc().isBefore(until);
  }

  AccountUsage copyWith({
    int? requests,
    int? backgroundRequests,
    int? inputTokens,
    int? outputTokens,
    int? images,
    int? imageTokens,
    int? spentMicroUsd,
    DateTime? exhaustedUntil,
    bool clearExhausted = false,
    CloudModelFailure? lastFailure,
    bool clearFailure = false,
  }) => AccountUsage(
    accountId: accountId,
    day: day,
    requests: requests ?? this.requests,
    backgroundRequests: backgroundRequests ?? this.backgroundRequests,
    inputTokens: inputTokens ?? this.inputTokens,
    outputTokens: outputTokens ?? this.outputTokens,
    images: images ?? this.images,
    imageTokens: imageTokens ?? this.imageTokens,
    spentMicroUsd: spentMicroUsd ?? this.spentMicroUsd,
    exhaustedUntil: clearExhausted
        ? null
        : (exhaustedUntil ?? this.exhaustedUntil),
    lastFailure: clearFailure ? null : (lastFailure ?? this.lastFailure),
  );

  Map<String, Object> toJson() => {
    'accountId': accountId,
    'day': day,
    'requests': requests,
    'backgroundRequests': backgroundRequests,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    if (images > 0) 'images': images,
    if (imageTokens > 0) 'imageTokens': imageTokens,
    if (spentMicroUsd > 0) 'spentMicroUsd': spentMicroUsd,
    if (exhaustedUntil != null)
      'exhaustedUntil': exhaustedUntil!.toUtc().toIso8601String(),
    if (lastFailure != null) 'lastFailure': lastFailure!.name,
  };

  @override
  bool operator ==(Object other) =>
      other is AccountUsage &&
      other.accountId == accountId &&
      other.day == day &&
      other.requests == requests &&
      other.backgroundRequests == backgroundRequests &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens &&
      other.images == images &&
      other.imageTokens == imageTokens &&
      other.spentMicroUsd == spentMicroUsd &&
      other.exhaustedUntil == exhaustedUntil &&
      other.lastFailure == lastFailure;

  @override
  int get hashCode => Object.hash(
    accountId,
    day,
    requests,
    backgroundRequests,
    inputTokens,
    outputTokens,
    images,
    imageTokens,
    spentMicroUsd,
    exhaustedUntil,
    lastFailure,
  );
}
