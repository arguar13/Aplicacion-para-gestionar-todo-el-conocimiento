import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/text_script.dart';

/// La escritura de un texto (F45, paso 4): la pista más firme de que no está
/// en el idioma que se esperaba.
void main() {
  group('las letras de cada escritura', () {
    test('el español es latín, con sus tildes y su eñe', () {
      final census = scriptCensusOf('Año: ¿Cómo está? Él sí. 1234 ×÷');
      expect(census.dominant, TextScript.latin);
      expect(census.shareOf(TextScript.latin), 1);
      // «Año», «Cómo», «está», «Él», «sí»: los números, los signos y el × y
      // el ÷ no son letras.
      expect(census.letters, 15);
    });

    test('el árabe, sin sus números ni su puntuación', () {
      final census = scriptCensusOf('مرحبا بكم، ١٢٣ في الفيديو؟');
      expect(census.dominant, TextScript.arabic);
      expect(census.shareOf(TextScript.arabic), 1);
      expect(census.letters, 'مرحبابكمفيالفيديو'.length);
    });

    test('el cirílico, el griego, el hebreo, el hindi, el coreano y el '
        'japonés', () {
      expect(scriptCensusOf('Привет мир').dominant, TextScript.cyrillic);
      expect(scriptCensusOf('Καλημέρα κόσμε').dominant, TextScript.greek);
      expect(scriptCensusOf('שלום עולם').dominant, TextScript.hebrew);
      expect(scriptCensusOf('नमस्ते दुनिया').dominant, TextScript.devanagari);
      expect(scriptCensusOf('안녕하세요').dominant, TextScript.hangul);
      expect(scriptCensusOf('こんにちは世界').dominant, TextScript.cjk);
    });

    test('sin letras no hay escritura', () {
      final census = scriptCensusOf('[0:00] 1, 2, 3… ♪');
      expect(census.letters, 0);
      expect(census.dominant, isNull);
      expect(census.shareOf(TextScript.latin), 0);
    });

    test('una escritura clara pide largo y casi todo de una sola', () {
      expect(
        scriptCensusOf('Las reliquias de San Francisco').clearScript(),
        TextScript.latin,
      );
      // Corto.
      expect(scriptCensusOf('Hola').clearScript(), isNull);
      // Mitad y mitad.
      expect(scriptCensusOf('Hola amigos مرحبا بكم').clearScript(), isNull);
    });
  });

  group('la escritura de cada idioma', () {
    test('los que ofrece la app y casi todos los demás, en latín', () {
      for (final code in ['es', 'en', 'pt-BR', 'fr', 'it', 'de', 'tr', 'vi']) {
        expect(scriptOfLanguage(code), TextScript.latin, reason: code);
      }
    });

    test('los de otras escrituras, con región o sin ella', () {
      expect(scriptOfLanguage('ar'), TextScript.arabic);
      expect(scriptOfLanguage('fa_IR'), TextScript.arabic);
      expect(scriptOfLanguage('ru'), TextScript.cyrillic);
      expect(scriptOfLanguage('el'), TextScript.greek);
      expect(scriptOfLanguage('he'), TextScript.hebrew);
      expect(scriptOfLanguage('hi'), TextScript.devanagari);
      expect(scriptOfLanguage('ko'), TextScript.hangul);
      expect(scriptOfLanguage('ja'), TextScript.cjk);
      expect(scriptOfLanguage('zh-Hant'), TextScript.cjk);
    });

    test('los de una escritura que no se cuenta —o dos—, ninguna', () {
      expect(scriptOfLanguage('sr'), isNull);
      expect(scriptOfLanguage('hy'), isNull);
      expect(scriptOfLanguage('und'), isNull);
    });

    test('el idioma que dice una escritura sola', () {
      expect(languageOfScript(TextScript.arabic), 'ar');
      expect(languageOfScript(TextScript.cyrillic), 'ru');
      expect(languageOfScript(TextScript.latin), isNull);
      expect(languageOfScript(TextScript.cjk), isNull);
    });
  });
}
