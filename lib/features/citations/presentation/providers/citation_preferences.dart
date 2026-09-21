import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/reference_style.dart';
import 'package:sinapsis/features/citations/domain/services/reference_styles.dart';

/// El estilo y el idioma con que se cita cuando el usuario no elige otros
/// (F15): lo que Ajustes recuerda entre sesiones.
///
/// `null` en cada uno quiere decir «sin elección»: el estilo es el primero del
/// registro y el idioma, el de la app. Un estilo guardado que la app ya no
/// ofrece cae en el predeterminado sin romper nada.
class CitationPreferences {
  const CitationPreferences({this.styleId, this.language});

  /// El identificador del estilo elegido —`apa7`, `mla9`…—.
  final String? styleId;

  /// El idioma elegido, o `null` para seguir el de la app.
  final CitationLanguage? language;
}

/// Guarda y recuerda las preferencias de cita, con el mismo almacén que el
/// tema y el idioma de la app.
class CitationPreferencesNotifier extends StateNotifier<CitationPreferences> {
  CitationPreferencesNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_read(prefs));

  static const _styleKey = 'citation_style';
  static const _languageKey = 'citation_language';

  final SharedPreferences _prefs;

  static CitationPreferences _read(SharedPreferences prefs) =>
      CitationPreferences(
        styleId: prefs.getString(_styleKey),
        language: switch (prefs.getString(_languageKey)) {
          'es' => CitationLanguage.es,
          'en' => CitationLanguage.en,
          _ => null,
        },
      );

  /// Elige el estilo por defecto; `null` vuelve al primero del registro.
  Future<void> setStyle(String? styleId) async {
    state = CitationPreferences(styleId: styleId, language: state.language);
    if (styleId == null) {
      await _prefs.remove(_styleKey);
    } else {
      await _prefs.setString(_styleKey, styleId);
    }
  }

  /// Elige el idioma por defecto; `null` vuelve a seguir el de la app.
  Future<void> setLanguage(CitationLanguage? language) async {
    state = CitationPreferences(styleId: state.styleId, language: language);
    if (language == null) {
      await _prefs.remove(_languageKey);
    } else {
      await _prefs.setString(_languageKey, language.name);
    }
  }
}

final citationPreferencesProvider =
    StateNotifierProvider<CitationPreferencesNotifier, CitationPreferences>(
      (ref) => CitationPreferencesNotifier(
        prefs: ref.watch(sharedPreferencesProvider),
      ),
    );

/// El estilo con que se cita por defecto.
final defaultCitationStyleProvider = Provider<ReferenceStyle>(
  (ref) =>
      kReferenceStyles.resolve(ref.watch(citationPreferencesProvider).styleId),
);

/// El idioma con que se cita por defecto: el elegido o, si no hay, el de la
/// app.
final defaultCitationLanguageProvider = Provider<CitationLanguage>((ref) {
  final chosen = ref.watch(citationPreferencesProvider).language;
  if (chosen != null) return chosen;
  return CitationLanguage.fromCode(
    ref.watch(effectiveLocaleProvider).languageCode,
  );
});
