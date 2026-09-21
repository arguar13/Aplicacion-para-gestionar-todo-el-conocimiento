import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/presentation/providers/citation_preferences.dart';

/// El estilo y el idioma con que se cita por defecto (F15): lo que Ajustes
/// recuerda y lo que se usa mientras nadie elige.
void main() {
  Future<ProviderContainer> container({
    Map<String, Object> stored = const {},
    Locale appLocale = const Locale('es'),
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final result = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        effectiveLocaleProvider.overrideWithValue(appLocale),
      ],
    );
    addTearDown(result.dispose);
    return result;
  }

  test('sin nada elegido: APA 7 y el idioma de la app', () async {
    final es = await container();
    final en = await container(appLocale: const Locale('en'));

    expect(es.read(defaultCitationStyleProvider).id, 'apa7');
    expect(es.read(defaultCitationLanguageProvider), CitationLanguage.es);
    expect(en.read(defaultCitationLanguageProvider), CitationLanguage.en);
  });

  test('lo elegido se recuerda y se usa', () async {
    final c = await container();

    await c.read(citationPreferencesProvider.notifier).setStyle('ieee');
    await c
        .read(citationPreferencesProvider.notifier)
        .setLanguage(CitationLanguage.en);

    expect(c.read(defaultCitationStyleProvider).id, 'ieee');
    expect(c.read(defaultCitationLanguageProvider), CitationLanguage.en);

    // Otra sesión, con el mismo almacén.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('citation_style'), 'ieee');
    expect(prefs.getString('citation_language'), 'en');
  });

  test('lo guardado de una sesión anterior se lee al empezar', () async {
    final c = await container(
      stored: {'citation_style': 'mla9', 'citation_language': 'en'},
    );

    expect(c.read(defaultCitationStyleProvider).id, 'mla9');
    expect(c.read(defaultCitationLanguageProvider), CitationLanguage.en);
  });

  test('un estilo que la app ya no ofrece cae en el predeterminado', () async {
    final c = await container(stored: {'citation_style': 'vancouver'});

    expect(c.read(defaultCitationStyleProvider).id, 'apa7');
  });

  test('un idioma guardado que no se conoce sigue el de la app', () async {
    final c = await container(stored: {'citation_language': 'fr'});

    expect(c.read(citationPreferencesProvider).language, isNull);
    expect(c.read(defaultCitationLanguageProvider), CitationLanguage.es);
  });

  test('quitar la elección vuelve al predeterminado', () async {
    final c = await container(
      stored: {'citation_style': 'ieee', 'citation_language': 'en'},
    );
    final notifier = c.read(citationPreferencesProvider.notifier);

    await notifier.setStyle(null);
    await notifier.setLanguage(null);

    expect(c.read(defaultCitationStyleProvider).id, 'apa7');
    expect(c.read(defaultCitationLanguageProvider), CitationLanguage.es);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('citation_style'), isFalse);
    expect(prefs.containsKey('citation_language'), isFalse);
  });

  test('cambiar el estilo no cambia el idioma, ni al revés', () async {
    final c = await container(
      stored: {'citation_style': 'ieee', 'citation_language': 'en'},
    );
    final notifier = c.read(citationPreferencesProvider.notifier);

    await notifier.setStyle('mla9');
    expect(c.read(citationPreferencesProvider).language, CitationLanguage.en);

    await notifier.setLanguage(CitationLanguage.es);
    expect(c.read(citationPreferencesProvider).styleId, 'mla9');
  });
}
