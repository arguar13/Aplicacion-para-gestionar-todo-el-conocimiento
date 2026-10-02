/// Cómo se llama cada acento en el panel de voz del lector flotante (F25):
/// "Español (Argentina)", "English (United States)", "Português (Brasil)".
///
/// Cada uno **en su propio idioma**, como en el selector de idiomas del
/// teléfono: quien busca su acento lo reconoce aunque la app esté en otro
/// idioma. Una tabla corta con los idiomas y las regiones que traen los
/// motores de voz de siempre; lo que no está ahí se muestra con su código
/// —"Nederlands (NL)", o "xx-YY" tal cual—, que es feo pero no miente.
library;

/// `es_us`, `es-US` o `ES-us` → `es-US`: los motores de voz no se ponen de
/// acuerdo en cómo escribir un locale.
String normalizeAccent(String locale) {
  final parts = locale.trim().split(RegExp('[-_]'));
  final language = parts.first.toLowerCase();
  if (parts.length < 2 || parts[1].isEmpty) return language;
  return '$language-${parts[1].toUpperCase()}';
}

/// El idioma de un acento: `es-AR` → `es`.
String accentLanguage(String locale) =>
    normalizeAccent(locale).split('-').first;

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
