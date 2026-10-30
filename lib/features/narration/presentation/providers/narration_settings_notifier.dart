import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_locale.dart';

/// Qué voces y qué velocidad eligió la persona que usa la app para escuchar
/// sus documentos, y si quiere la Lectura enfocada, entre reinicios.
class NarrationSettings {
  const NarrationSettings({
    this.voice,
    this.speed = 1,
    this.voicesByLanguage = const {},
    this.focusedReading = false,
  });

  /// La última voz elegida; `null` es la voz por defecto del sistema —nadie
  /// tocó el selector todavía—. Lee lo que no se sabe en qué idioma está.
  final NarrationVoice? voice;

  /// De 0.5x a 3.0x (F47, decisión H). 1.0 es la velocidad normal del
  /// motor.
  final double speed;

  /// La voz elegida para cada idioma, por su código (`es`, `en`): la voz
  /// sigue al idioma del texto (F47, paso 3, decisión L). Un idioma que no
  /// está no tiene una elegida.
  final Map<String, NarrationVoice> voicesByLanguage;

  /// Lectura enfocada (F47, paso 2): el reproductor de lectura se achica
  /// solo mientras te desplazás, y vuelve a abrirse al soltar. Apagada de
  /// entrada: un reproductor que cambia de tamaño sin que se lo pidan
  /// sorprende si no se eligió.
  final bool focusedReading;

  NarrationSettings copyWith({double? speed, bool? focusedReading}) =>
      NarrationSettings(
        voice: voice,
        speed: speed ?? this.speed,
        voicesByLanguage: voicesByLanguage,
        focusedReading: focusedReading ?? this.focusedReading,
      );
}

/// Recuerda las voces y la velocidad elegidas para leer en voz alta, mismo
/// criterio que `ThemeModeNotifier`/`ReaderFontScaleNotifier`.
///
/// Cada voz se guarda como `"nombre\u0000locale"` —un solo campo de texto,
/// separado por un carácter que ninguna voz real trae en su nombre— en vez
/// de dos claves sueltas: así una lectura a medio guardar nunca deja el
/// nombre de una voz emparejado con el locale de otra. Una voz sin conexión
/// suma un tercer campo, `offline` (F47, paso 3); las guardadas antes, de
/// dos, son del sistema, como eran.
///
/// Las voces por idioma van juntas en un JSON. La voz guardada antes de
/// F47 —una sola para todo— cuenta como la elegida para su idioma, si ese
/// idioma no tiene otra.
class NarrationSettingsNotifier extends StateNotifier<NarrationSettings> {
  NarrationSettingsNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_readInitial(prefs));

  static const _voiceKey = 'narration_voice';
  static const _speedKey = 'narration_speed';
  static const _byLanguageKey = 'narration_voices_by_language';
  static const _focusedReadingKey = 'narration_focused_reading';
  static const _voiceSeparator = '\u0000';
  static const _offlineMark = 'offline';

  final SharedPreferences _prefs;

  static NarrationSettings _readInitial(SharedPreferences prefs) {
    final voice = _decode(prefs.getString(_voiceKey));
    final byLanguage = <String, NarrationVoice>{};
    final stored = prefs.getString(_byLanguageKey);
    if (stored != null) {
      try {
        final map = jsonDecode(stored);
        if (map is Map) {
          for (final MapEntry(:key, :value) in map.entries) {
            final decoded = value is String ? _decode(value) : null;
            if (key is String && decoded != null) byLanguage[key] = decoded;
          }
        }
      } on FormatException {
        // Un JSON roto no deja sin voces: se sigue con la de siempre.
      }
    }
    if (voice != null) {
      byLanguage.putIfAbsent(accentLanguage(voice.locale), () => voice);
    }

    final speed = prefs.getDouble(_speedKey) ?? 1.0;
    return NarrationSettings(
      voice: voice,
      speed: speed,
      voicesByLanguage: Map.unmodifiable(byLanguage),
      focusedReading: prefs.getBool(_focusedReadingKey) ?? false,
    );
  }

  static NarrationVoice? _decode(String? stored) {
    final parts = stored?.split(_voiceSeparator);
    if (parts == null) return null;
    if (parts.length == 2) {
      return NarrationVoice(name: parts[0], locale: parts[1]);
    }
    if (parts.length == 3 && parts[2] == _offlineMark) {
      return NarrationVoice(
        name: parts[0],
        locale: parts[1],
        engine: NarrationEngine.offline,
      );
    }
    return null;
  }

  static String _encode(NarrationVoice voice) => [
    voice.name,
    voice.locale,
    if (voice.engine == NarrationEngine.offline) _offlineMark,
  ].join(_voiceSeparator);

  /// Elige [voice] para leer —y para su idioma, de ahora en más—. `null` es
  /// la voz del sistema: deja sin elegida a [language], el idioma que se
  /// estaba leyendo, si se sabe.
  Future<void> selectVoice(NarrationVoice? voice, {String? language}) async {
    final byLanguage = {...state.voicesByLanguage};
    if (voice != null) {
      byLanguage[accentLanguage(voice.locale)] = voice;
    } else if (language != null) {
      byLanguage.remove(language);
    }
    // No `copyWith`: con `voice: null` dejaría la voz anterior (F25).
    state = NarrationSettings(
      voice: voice,
      speed: state.speed,
      voicesByLanguage: Map.unmodifiable(byLanguage),
      focusedReading: state.focusedReading,
    );
    if (voice == null) {
      await _prefs.remove(_voiceKey);
    } else {
      await _prefs.setString(_voiceKey, _encode(voice));
    }
    await _saveByLanguage(byLanguage);
  }

  /// Deja [language] sin voz elegida: se lee con la mejor que haya en el
  /// teléfono para ese idioma.
  Future<void> clearLanguage(String language) async {
    if (!state.voicesByLanguage.containsKey(language)) return;
    final byLanguage = {...state.voicesByLanguage}..remove(language);
    final voice = state.voice;
    final keepsVoice =
        voice == null || accentLanguage(voice.locale) != language;
    state = NarrationSettings(
      voice: keepsVoice ? voice : null,
      speed: state.speed,
      voicesByLanguage: Map.unmodifiable(byLanguage),
      focusedReading: state.focusedReading,
    );
    if (!keepsVoice) await _prefs.remove(_voiceKey);
    await _saveByLanguage(byLanguage);
  }

  Future<void> _saveByLanguage(Map<String, NarrationVoice> byLanguage) =>
      _prefs.setString(
        _byLanguageKey,
        jsonEncode({
          for (final MapEntry(:key, :value) in byLanguage.entries)
            key: _encode(value),
        }),
      );

  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _prefs.setDouble(_speedKey, speed);
  }

  Future<void> setFocusedReading({required bool enabled}) async {
    state = state.copyWith(focusedReading: enabled);
    await _prefs.setBool(_focusedReadingKey, enabled);
  }
}

final narrationSettingsNotifierProvider =
    StateNotifierProvider<NarrationSettingsNotifier, NarrationSettings>((ref) {
      return NarrationSettingsNotifier(
        prefs: ref.watch(sharedPreferencesProvider),
      );
    });
