import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_semantic_colors.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/screens/language_model_screen.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_model_picker.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_model_screen.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La barra de arriba del chat (F42): la píldora del modelo hace lo que
/// hacían el robot y el círculo de la cuenta —elegir quién contesta, con qué
/// modelo y qué cuenta, y llegar a la pantalla de la IA—.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Finder inPill(String text) => find.descendant(
    of: find.byKey(const Key('chat-model-pill')),
    matching: find.text(text),
  );

  Future<void> pumpChat(
    WidgetTester tester, {
    AiProvider provider = AiProvider.gemma,
    bool chatModelReady = false,
    void Function(LibraryHarness harness)? before,
  }) async {
    harness = await LibraryHarness.create(
      languageModelProvider: provider,
      chatModelReady: chatModelReady,
    );
    before?.call(harness);
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('chat-model-pill')));
    await tester.pumpAndSettle();
  }

  testWidgets('la píldora dice el modelo y abre la hoja para elegir quién '
      'contesta', (tester) async {
    await pumpChat(tester);

    expect(inPill(es.chatModelOptionGemma4Title), findsOneWidget);
    await openPicker(tester);

    expect(find.text(es.aiPickerTitle), findsOneWidget);
    final gemma = tester.widget<ChoiceChip>(
      find.byKey(const Key('ai-picker-provider-gemma')),
    );
    expect(gemma.selected, isTrue);
    expect(find.byKey(const Key('ai-picker-gemma-manage')), findsOneWidget);
    // Con Gemma no hay cuenta que elegir.
    expect(find.text(es.aiPickerAccount), findsNothing);
  });

  Color dotColor(WidgetTester tester) {
    final dot = tester.widget<Container>(
      find.byKey(const Key('chat-model-pill-dot')),
    );
    return (dot.decoration! as BoxDecoration).color!;
  }

  testWidgets('sin el modelo, el punto avisa que le falta algo', (
    tester,
  ) async {
    await pumpChat(tester);

    final theme = Theme.of(tester.element(find.byType(ChatScreen)));
    expect(dotColor(tester), theme.colorScheme.tertiary);
  });

  testWidgets('con el modelo listo, el punto es el de «listo»', (tester) async {
    await pumpChat(tester, chatModelReady: true);

    final theme = Theme.of(tester.element(find.byType(ChatScreen)));
    expect(
      dotColor(tester),
      theme.extension<AppSemanticColors>()?.success ??
          theme.colorScheme.primary,
    );
  });

  group('elegir el proveedor', () {
    testWidgets('pasar a Gemini pide antes el aviso de privacidad; aceptarlo '
        'lo deja elegido y la píldora lo dice', (tester) async {
      await pumpChat(tester);
      await openPicker(tester);

      await tester.tap(find.byKey(const Key('ai-picker-provider-gemini')));
      await tester.pumpAndSettle();
      expect(find.byType(AiPrivacyDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('lm-privacy-continue')));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(aiModelSettingsProvider).provider,
        AiProvider.gemini,
      );
      expect(
        harness.container
            .read(sharedPreferencesProvider)
            .getBool(aiPrivacySeenKey(AiProvider.gemini)),
        isTrue,
      );
      expect(inPill(es.lmProviderGemini), findsOneWidget);
      // Y ahora hay cuenta: falta cargar una.
      expect(find.byKey(const Key('ai-picker-add-key')), findsOneWidget);
    });

    testWidgets('cancelar el aviso deja todo como estaba', (tester) async {
      await pumpChat(tester);
      await openPicker(tester);

      await tester.tap(find.byKey(const Key('ai-picker-provider-gemini')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(aiModelSettingsProvider).provider,
        AiProvider.gemma,
      );
    });
  });

  testWidgets('en la nube, el modelo se elige de la lista y la píldora lo '
      'dice; «recomendado» vuelve al del proveedor', (tester) async {
    await pumpChat(
      tester,
      provider: AiProvider.gemini,
      before: (harness) => harness.container
          .read(sharedPreferencesProvider)
          .setString(
            'ai_models_cache_gemini',
            jsonEncode({
              'fetchedAt': DateTime.utc(2026, 9, 11).toIso8601String(),
              'models': [
                {'id': 'gemini-3.1-flash-lite', 'displayName': 'Flash Lite'},
                {'id': 'gemini-3-pro', 'displayName': 'Pro'},
              ],
            }),
          ),
    );
    final recommended = harness.container
        .read(cloudModelCatalogProvider)
        .recommended(AiProvider.gemini);
    final recommendedName = recommended == 'gemini-3-pro'
        ? 'Pro'
        : 'Flash Lite';
    final otherId = recommended == 'gemini-3-pro'
        ? 'gemini-3.1-flash-lite'
        : 'gemini-3-pro';
    final otherName = recommended == 'gemini-3-pro' ? 'Flash Lite' : 'Pro';
    expect(inPill(recommendedName), findsOneWidget);

    await openPicker(tester);
    await tester.tap(find.byKey(Key('ai-picker-model-$otherId')));
    await tester.pumpAndSettle();

    expect(
      harness.container
          .read(aiModelSettingsProvider)
          .modelOf(AiProvider.gemini),
      otherId,
    );
    expect(inPill(otherName), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-picker-model-recommended')));
    await tester.pumpAndSettle();
    expect(
      harness.container
          .read(aiModelSettingsProvider)
          .modelOf(AiProvider.gemini),
      isNull,
    );
  });

  testWidgets('con cuentas, la hoja cambia la que escribe con un toque', (
    tester,
  ) async {
    await pumpChat(tester, provider: AiProvider.gemini);
    final accounts = harness.container.read(aiAccountRepositoryProvider);
    await accounts.add(
      provider: AiProvider.gemini,
      key: 'clave-1',
      label: 'Personal',
    );
    final second = await accounts.add(
      provider: AiProvider.gemini,
      key: 'clave-2',
      label: 'Trabajo',
    );
    await tester.pumpAndSettle();

    await openPicker(tester);
    await tester.tap(find.byKey(const Key('ai-account-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('ai-switcher-${second.id}')));
    await tester.pumpAndSettle();

    expect(
      harness.container
          .read(aiModelSettingsProvider)
          .activeAccountOf(AiProvider.gemini),
      second.id,
    );
  });

  group('las pantallas de la IA, a un toque', () {
    Future<void> pumpRouted(
      WidgetTester tester, {
      AiProvider provider = AiProvider.gemma,
    }) async {
      harness = await LibraryHarness.create(languageModelProvider: provider);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      harness.goTo(RoutePaths.chat);
      await tester.pumpAndSettle();
    }

    testWidgets('«Más ajustes de la IA» abre la pantalla del modelo', (
      tester,
    ) async {
      await pumpRouted(tester);
      await openPicker(tester);

      await tester.tap(find.byKey(const Key('ai-picker-more')));
      await tester.pumpAndSettle();

      expect(find.byType(LanguageModelScreen), findsOneWidget);
    });

    testWidgets('con Gemma, lleva a bajarlo o cambiarlo', (tester) async {
      await pumpRouted(tester);
      await openPicker(tester);

      await tester.tap(find.byKey(const Key('ai-picker-gemma-manage')));
      await tester.pumpAndSettle();

      expect(find.byType(ChatModelScreen), findsOneWidget);
    });

    testWidgets('en la nube sin cuenta, lleva a cargar la clave', (
      tester,
    ) async {
      await pumpRouted(tester, provider: AiProvider.gemini);
      await openPicker(tester);

      await tester.tap(find.byKey(const Key('ai-picker-add-key')));
      await tester.pumpAndSettle();

      expect(find.byType(LanguageModelScreen), findsOneWidget);
    });
  });
}
