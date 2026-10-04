import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';

/// Dónde se recuerda en qué parte del teléfono correr el modelo de lenguaje
/// y lo que se midió para elegirlo (F30). Uno por modelo: lo que vale para
/// Gemma 4 E4B no tiene por qué valer para Gemma 3n.
class LanguageModelBackendStore {
  LanguageModelBackendStore({
    required SharedPreferences preferences,
    required String Function() modelKey,
  }) : _preferences = preferences,
       _modelKey = modelKey;

  final SharedPreferences _preferences;

  /// El modelo elegido ahora (`ChatModelOption.name`).
  final String Function() _modelKey;

  String get _choiceKey => 'language_model_backend.${_modelKey()}';
  String get _resultsKey => 'language_model_benchmark.${_modelKey()}';

  /// La elección recordada; `null` si no hay ninguna.
  LanguageModelBackendChoice? get choice {
    final raw = _preferences.getString(_choiceKey);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final backend = _backendNamed(json['backend'] as String?);
    final reason = LanguageModelBackendReason.values
        .where((r) => r.name == json['reason'])
        .firstOrNull;
    if (backend == null || reason == null) return null;
    return LanguageModelBackendChoice(
      backend: backend,
      reason: reason,
      speculative: json['speculative'] as bool?,
    );
  }

  Future<void> saveChoice(LanguageModelBackendChoice choice) =>
      _preferences.setString(
        _choiceKey,
        jsonEncode({
          'backend': choice.backend.name,
          'reason': choice.reason.name,
          'speculative': ?choice.speculative,
        }),
      );

  /// Lo que se midió la última vez, en el orden en que se probó.
  List<LanguageModelBenchmarkResult> get results {
    final raw = _preferences.getString(_resultsKey);
    if (raw == null) return const [];
    return [
      for (final entry in jsonDecode(raw) as List<dynamic>)
        ?_resultFrom(entry as Map<String, dynamic>),
    ];
  }

  Future<void> saveResults(List<LanguageModelBenchmarkResult> results) =>
      _preferences.setString(
        _resultsKey,
        jsonEncode([
          for (final result in results)
            {
              'backend': result.backend.name,
              'speculative': ?result.speculative,
              'failure': ?result.failure,
              if (result.reply case final reply?) ...{
                'firstMs': ?reply.firstToken?.inMilliseconds,
                'totalMs': reply.total.inMilliseconds,
                'tokens': ?reply.tokens,
                'words': reply.words,
              },
            },
        ]),
      );

  static LanguageModelBenchmarkResult? _resultFrom(Map<String, dynamic> json) {
    final backend = _backendNamed(json['backend'] as String?);
    if (backend == null) return null;
    final totalMs = json['totalMs'] as int?;
    final firstMs = json['firstMs'] as int?;
    return LanguageModelBenchmarkResult(
      backend: backend,
      speculative: json['speculative'] as bool?,
      failure: json['failure'] as String?,
      reply: totalMs == null
          ? null
          : LanguageModelReply(
              kind: LanguageModelReplyKind.task,
              firstToken: firstMs == null
                  ? null
                  : Duration(milliseconds: firstMs),
              total: Duration(milliseconds: totalMs),
              tokens: json['tokens'] as int?,
              words: json['words'] as int? ?? 0,
            ),
    );
  }

  static LanguageModelBackend? _backendNamed(String? name) =>
      LanguageModelBackend.values.where((b) => b.name == name).firstOrNull;
}
