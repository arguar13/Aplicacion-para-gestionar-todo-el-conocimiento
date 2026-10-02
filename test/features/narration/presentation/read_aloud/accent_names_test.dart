import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';

void main() {
  group('los nombres de los acentos (F25)', () {
    test('cada uno en su idioma', () {
      expect(accentDisplayName('es-AR'), 'Español (Argentina)');
      expect(accentDisplayName('es-ES'), 'Español (España)');
      expect(accentDisplayName('en-US'), 'English (United States)');
      expect(accentDisplayName('pt-BR'), 'Português (Brasil)');
    });

    test('entiende cómo escribe el locale cada motor', () {
      expect(normalizeAccent('es_us'), 'es-US');
      expect(normalizeAccent('ES-mx'), 'es-MX');
      expect(normalizeAccent('fr'), 'fr');
      expect(accentDisplayName('es_MX'), 'Español (México)');
      expect(accentLanguage('en_GB'), 'en');
    });

    test('lo que no conoce lo muestra con su código', () {
      expect(accentDisplayName('nl-SR'), 'Nederlands (SR)');
      expect(accentDisplayName('xx-YY'), 'xx-YY');
      expect(accentDisplayName('de'), 'Deutsch');
    });
  });
}
