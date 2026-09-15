import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_model_option_notifier.dart';

/// [isDesktopChatPlatform]/[defaultChatModelOption]/
/// [availableChatModelOptions] dependen de `defaultTargetPlatform`, no de
/// `dart:io.Platform` —ver el porqué en el propio archivo—, así que se
/// prueban forzándolo con `debugDefaultTargetPlatformOverride`, que existe
/// justo para esto.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('isDesktopChatPlatform', () {
    test('es verdadero en Windows', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(isDesktopChatPlatform, isTrue);
    });

    test('es verdadero en macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(isDesktopChatPlatform, isTrue);
    });

    test('es verdadero en Linux', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(isDesktopChatPlatform, isTrue);
    });

    test('es falso en Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(isDesktopChatPlatform, isFalse);
    });

    test('es falso en iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(isDesktopChatPlatform, isFalse);
    });
  });

  group('availableChatModelOptions', () {
    test('en escritorio incluye las tres opciones', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(availableChatModelOptions, [
        ChatModelOption.gemma4E4b,
        ChatModelOption.gemma3nE4b,
        ChatModelOption.gemma412b,
      ]);
    });

    test('en Android no incluye la opción de 12B', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(availableChatModelOptions, [
        ChatModelOption.gemma4E4b,
        ChatModelOption.gemma3nE4b,
      ]);
    });
  });

  group('defaultChatModelOption', () {
    test('en escritorio, la opción más pesada', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(defaultChatModelOption, ChatModelOption.gemma412b);
    });

    test('en Android, Gemma 4 E4B de siempre', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(defaultChatModelOption, ChatModelOption.gemma4E4b);
    });
  });

  group('ChatModelOptionNotifier', () {
    test('sin nada guardado, arranca en la opción por defecto de esta '
        'plataforma', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final notifier = ChatModelOptionNotifier(prefs: prefs);

      expect(notifier.state, ChatModelOption.gemma412b);
    });

    test('una opción guardada que esta plataforma no puede correr no se '
        'restaura: cae al valor por defecto', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'chat_model_option': ChatModelOption.gemma412b.name,
      });
      final prefs = await SharedPreferences.getInstance();

      final notifier = ChatModelOptionNotifier(prefs: prefs);

      expect(notifier.state, ChatModelOption.gemma4E4b);
    });

    test(
      'una opción guardada válida para esta plataforma sí se restaura',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        SharedPreferences.setMockInitialValues({
          'chat_model_option': ChatModelOption.gemma3nE4b.name,
        });
        final prefs = await SharedPreferences.getInstance();

        final notifier = ChatModelOptionNotifier(prefs: prefs);

        expect(notifier.state, ChatModelOption.gemma3nE4b);
      },
    );
  });
}
