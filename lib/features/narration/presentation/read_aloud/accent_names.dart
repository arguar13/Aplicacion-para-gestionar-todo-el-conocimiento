/// Cómo se llama cada acento en el panel de voz del lector flotante (F25):
/// "Español (Argentina)", "English (United States)", "Português (Brasil)".
///
/// Cada uno **en su propio idioma**, como en el selector de idiomas del
/// teléfono: quien busca su acento lo reconoce aunque la app esté en otro
/// idioma. Una tabla corta con los idiomas y las regiones que traen los
/// motores de voz de siempre; lo que no está ahí se muestra con su código
/// —"Nederlands (NL)", o "xx-YY" tal cual—, que es feo pero no miente.
library;

import 'package:sinapsis/features/narration/domain/voices/voice_locale.dart';

export 'package:sinapsis/features/narration/domain/voices/voice_locale.dart'
    show accentLanguage, normalizeAccent;

/// El nombre de un acento para mostrar, en su propio idioma.
String accentDisplayName(String locale) {
  final normalized = normalizeAccent(locale);
  final parts = normalized.split('-');
  final language = _languages[parts.first];
  if (language == null) return normalized;
  if (parts.length < 2) return language;
  final region = _regions[parts.first]?[parts[1]] ?? parts[1];
  return '$language ($region)';
}

/// El nombre de la región de un acento, en su propio idioma —«Argentina»,
/// «United Kingdom»—, o su código si la tabla no la tiene; `null` si el
/// acento no dice de dónde es. Es lo que muestra el filtro de acento de la
/// biblioteca de voces (F47, paso 3).
String? accentRegionName(String locale) {
  final normalized = normalizeAccent(locale);
  final region = accentRegion(normalized);
  if (region == null) return null;
  return _regions[accentLanguage(normalized)]?[region] ?? region;
}

/// El nombre de un idioma en su propio idioma —«Español», «English»—, o su
/// código si la tabla no lo tiene.
String languageDisplayName(String language) =>
    _languages[language.toLowerCase()] ?? language;

const _languages = {
  'es': 'Español',
  'en': 'English',
  'pt': 'Português',
  'fr': 'Français',
  'it': 'Italiano',
  'de': 'Deutsch',
  'ca': 'Català',
  'gl': 'Galego',
  'eu': 'Euskara',
  'nl': 'Nederlands',
  'ru': 'Русский',
  'ja': '日本語',
  'zh': '中文',
  'ko': '한국어',
  'ar': 'العربية',
  'hi': 'हिन्दी',
};

const _regions = {
  'es': {
    'AR': 'Argentina',
    'BO': 'Bolivia',
    'CL': 'Chile',
    'CO': 'Colombia',
    'CR': 'Costa Rica',
    'CU': 'Cuba',
    'DO': 'República Dominicana',
    'EC': 'Ecuador',
    'ES': 'España',
    'GT': 'Guatemala',
    'HN': 'Honduras',
    'MX': 'México',
    'NI': 'Nicaragua',
    'PA': 'Panamá',
    'PE': 'Perú',
    'PR': 'Puerto Rico',
    'PY': 'Paraguay',
    'SV': 'El Salvador',
    'US': 'Estados Unidos',
    'UY': 'Uruguay',
    'VE': 'Venezuela',
  },
  'en': {
    'AU': 'Australia',
    'CA': 'Canada',
    'GB': 'United Kingdom',
    'IE': 'Ireland',
    'IN': 'India',
    'NG': 'Nigeria',
    'NZ': 'New Zealand',
    'SG': 'Singapore',
    'US': 'United States',
    'ZA': 'South Africa',
  },
  'pt': {'BR': 'Brasil', 'PT': 'Portugal'},
  'fr': {'BE': 'Belgique', 'CA': 'Canada', 'CH': 'Suisse', 'FR': 'France'},
  'it': {'CH': 'Svizzera', 'IT': 'Italia'},
  'de': {'AT': 'Österreich', 'CH': 'Schweiz', 'DE': 'Deutschland'},
  'ca': {'ES': 'Espanya'},
  'gl': {'ES': 'España'},
  'eu': {'ES': 'Espainia'},
  'nl': {'BE': 'België', 'NL': 'Nederland'},
  'ru': {'RU': 'Россия'},
  'ja': {'JP': '日本'},
  'zh': {'CN': '中国', 'HK': '香港', 'TW': '台灣'},
  'ko': {'KR': '대한민국'},
  'hi': {'IN': 'भारत'},
};
