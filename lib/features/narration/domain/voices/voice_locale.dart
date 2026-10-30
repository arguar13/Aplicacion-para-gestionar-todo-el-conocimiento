/// El idioma y el acento de una voz, como los escriben los motores de voz
/// (`es_us`, `es-US`, `ES-us`) y como los usa la app (`es-US`).
///
/// Nacieron con el panel de voz del lector flotante (F25, `accent_names.dart`)
/// y bajaron acá con la biblioteca de voces (F47, paso 3): el dominio —qué voz
/// lee qué idioma— los necesita sin depender de cómo se muestran.
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

/// La región de un acento: `es-AR` → `AR`; `null` si solo dice el idioma.
String? accentRegion(String locale) {
  final parts = normalizeAccent(locale).split('-');
  return parts.length < 2 ? null : parts[1];
}

/// La bandera de la región de un acento, con los dos símbolos regionales de
/// Unicode que la forman: `es-AR` → 🇦🇷. `null` si el acento no dice de dónde
/// es, o la región no son dos letras (`es-419`).
String? accentFlag(String locale) {
  final region = accentRegion(locale);
  if (region == null || !RegExp(r'^[A-Z]{2}$').hasMatch(region)) return null;
  const regionalA = 0x1F1E6;
  return String.fromCharCodes([
    for (final unit in region.codeUnits) regionalA + unit - 0x41,
  ]);
}
