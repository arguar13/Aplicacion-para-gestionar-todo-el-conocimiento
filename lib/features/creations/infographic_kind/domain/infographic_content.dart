import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_json.dart';

/// Lo que se guarda como contenido de una infografía de «Lo creado» (F43,
/// paso 12): la lámina que escribió la IA —con sus ilustraciones ya hechas
/// en `illustrationRef`— y lo que se sabe de las que no salieron, para que el
/// visor diga por qué y ofrezca completarlas.
///
/// El diseño no va acá sino en las opciones (decisión G, ver
/// `InfographicOptionKeys.design`).
///
/// Se guarda así:
///
/// ```json
/// {
///   "sheet": { …la forma de `InfographicJson.encode`… },
///   "illustrations": {
///     "account": "Personal",
///     "failed": {"header": "noBilling", "block-3": "quotaExhausted"}
///   }
/// }
/// ```
///
/// [InfographicContent.decode] lee con tolerancia: también la lámina sola,
/// sin el sobre (la que guardaría una versión que no anotara las
/// ilustraciones), y nunca falla.
@immutable
class InfographicContent {
  const InfographicContent({
    required this.sheet,
    this.failures = const {},
    this.accountLabel,
  });

  factory InfographicContent.decode(String? content) {
    Object? json;
    try {
      json = content == null || content.isEmpty ? null : jsonDecode(content);
    } on FormatException {
      json = content;
    }
    if (json is Map && json['sheet'] != null) {
      final illustrations = json['illustrations'];
      final failed = illustrations is Map ? illustrations['failed'] : null;
      final account = illustrations is Map ? illustrations['account'] : null;
      return InfographicContent(
        sheet: InfographicJson.decode(json['sheet']),
        failures: {
          if (failed is Map)
            for (final MapEntry(:key, :value) in failed.entries)
              if (key is String && _failure(value) != null)
                key: _failure(value)!,
        },
        accountLabel: account is String && account.isNotEmpty ? account : null,
      );
    }
    return InfographicContent(sheet: InfographicJson.decode(json));
  }

  /// La versión de esta forma (`StudyCreation.contentVersion`).
  static const version = 1;

  final Infographic sheet;

  /// Las ilustraciones que no salieron, por lugar (`InfographicSlot.id`), con
  /// el porqué. Una que sale después deja de estar.
  final Map<String, ImageFailure> failures;

  /// El nombre de la cuenta que dibujó (o lo intentó): el porqué se dice con
  /// él («tu cuenta Personal no tiene facturación activa»).
  final String? accountLabel;

  String encode() => jsonEncode({
    'sheet': InfographicJson.encode(sheet),
    if (failures.isNotEmpty || accountLabel != null)
      'illustrations': {
        if (accountLabel != null) 'account': accountLabel,
        if (failures.isNotEmpty)
          'failed': {
            for (final MapEntry(:key, :value) in failures.entries)
              key: value.name,
          },
      },
  });

  InfographicContent copyWith({
    Infographic? sheet,
    Map<String, ImageFailure>? failures,
    String? accountLabel,
  }) => InfographicContent(
    sheet: sheet ?? this.sheet,
    failures: failures ?? this.failures,
    accountLabel: accountLabel ?? this.accountLabel,
  );

  static ImageFailure? _failure(Object? name) {
    for (final failure in ImageFailure.values) {
      if (failure.name == name) return failure;
    }
    return null;
  }
}
