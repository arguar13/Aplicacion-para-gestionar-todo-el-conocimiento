import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_notice.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/screens/language_model_screen.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_notice_listener.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/fake_chat_model_manager.dart';

/// Un Google de mentira: la clave «buena» anda; cualquier otra no.
class _FakeWire implements CloudWire {
  _FakeWire([this.provider = AiProvider.gemini]);

  final keysTried = <String>[];

  @override
  final AiProvider provider;

  @override
  Future<List<CloudModelInfo>> listModels(String key) async {
    keysTried.add(key);
    if (!key.startsWith('buena')) {
      throw const CloudModelException(CloudModelFailure.invalidKey);
    }
    return const [
      CloudModelInfo(id: 'gemini-3.8-flash', displayName: 'Gemini 3.8 Flash'),
      CloudModelInfo(id: 'gemini-3.5-flash-lite', displayName: 'Lite'),
    ];
  }

  @override
  String? recommendedModel(List<CloudModelInfo> models) =>
      models.isEmpty ? null : models.first.id;

  @override
  Stream<CloudDelta> stream(
    CloudRequest request, {
    required String key,
    CancelToken? cancel,
  }) => const Stream.empty();
}

void main() {
  final l10n = AppLocalizationsEs();
  final now = DateTime.utc(2026, 10, 16, 15);
  late ProviderContainer container;
  late _FakeWire wire;
  late SharedPreferences prefs;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    wire = _FakeWire();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => now),
        cloudWiresProvider.overrideWithValue({AiProvider.gemini: wire}),
        chatModelManagerProvider.overrideWithValue(FakeChatModelManager()),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LanguageModelScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<AiAccount> addAccount(String key, String label) => container
      .read(aiAccountRepositoryProvider)
      .add(provider: AiProvider.gemini, key: key, label: label);

  testWidgets('sin cuentas: la primera clave pide antes el aviso de '
      'privacidad, se prueba, una mala no se guarda y una buena queda en '
      'uso', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('lm-accounts-empty')), findsOneWidget);
    expect(
      find.text(l10n.lmStatusNeedsAccount(l10n.lmProviderGemini)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('lm-add-account')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.lmPrivacyTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('lm-privacy-continue')));
    await tester.pumpAndSettle();
    expect(prefs.getBool(aiPrivacySeenKey(AiProvider.gemini)), isTrue);

    await tester.enterText(find.byKey(const Key('ai-key-name')), 'Personal');
    await tester.enterText(find.byKey(const Key('ai-key-value')), 'mala');
    // El botón se habilita al redibujar con la clave escrita.
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-key-save')));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.lmTestFailed(l10n.lmFailureInvalidKey)),
      findsOneWidget,
    );
    expect(await container.read(aiAccountRepositoryProvider).list(), isEmpty);
    // Tocar el campo mueve el cursor —el controlador avisa—, pero la clave es
    // la misma: el error sigue a la vista.
    await tester.tap(find.byKey(const Key('ai-key-value')));
    await tester.pump();
    expect(
      find.text(l10n.lmTestFailed(l10n.lmFailureInvalidKey)),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('ai-key-value')), ' buena-1 ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-key-save')));
    await tester.pumpAndSettle();

    final saved = await container.read(aiAccountRepositoryProvider).list();
    expect(saved.single.label, 'Personal');
    expect(
      await container.read(aiAccountRepositoryProvider).keyOf(saved.single.id),
      'buena-1',
    );
    expect(
      container
          .read(aiModelSettingsProvider)
          .activeAccountOf(AiProvider.gemini),
      saved.single.id,
    );
    expect(find.text(l10n.lmAccountInUse), findsOneWidget);
    expect(find.text(l10n.lmStatusReady), findsOneWidget);
    // La prueba trajo la lista de modelos: el recomendado se ve por nombre.
    expect(find.text('Gemini 3.8 Flash'), findsOneWidget);
  });

  testWidgets('tocar otra cuenta la deja en uso; nada más cambia', (
    tester,
  ) async {
    final first = await addAccount('buena-1', 'Personal');
    final second = await addAccount('buena-2', 'Trabajo');
    await container
        .read(aiModelSettingsProvider.notifier)
        .chooseAccount(AiProvider.gemini, first.id);
    await pump(tester);

    await tester.tap(find.byKey(Key('lm-account-${second.id}')));
    await tester.pumpAndSettle();

    final settings = container.read(aiModelSettingsProvider);
    expect(settings.activeAccountOf(AiProvider.gemini), second.id);
    expect(settings.provider, AiProvider.gemini);
  });

  testWidgets('el menú desplegable cambia de cuenta con un toque y lo dice', (
    tester,
  ) async {
    await addAccount('buena-1', 'Personal');
    final second = await addAccount('buena-2', 'Trabajo');
    await pump(tester);

    await tester.tap(find.byKey(const Key('ai-account-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('ai-switcher-${second.id}')));
    await tester.pumpAndSettle();

    expect(
      container
          .read(aiModelSettingsProvider)
          .activeAccountOf(AiProvider.gemini),
      second.id,
    );
    expect(find.text(l10n.lmNowUsing('Trabajo')), findsOneWidget);
  });

  testWidgets('una cuenta agotada dice hasta cuándo', (tester) async {
    final account = await addAccount('buena-1', 'Personal');
    await container
        .read(aiUsageLedgerProvider)
        .markExhausted(
          account.id,
          now: now,
          until: now.add(const Duration(hours: 2)),
          failure: CloudModelFailure.quotaExhausted,
        );
    await pump(tester);

    expect(
      find.textContaining(l10n.lmAccountExhaustedUntil('').trim()),
      findsWidgets,
    );
  });

  testWidgets('elegir Gemma no pide aviso de privacidad, y volver a Gemini '
      'sí, la primera vez', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('lm-provider-gemma')));
    await tester.pumpAndSettle();
    expect(container.read(aiModelSettingsProvider).provider, AiProvider.gemma);
    expect(find.byKey(const Key('lm-gemma-manage')), findsOneWidget);
    // OpenAI y Claude, sin cómo hablarles todavía, no se ofrecen.
    expect(find.byKey(const Key('lm-provider-openai')), findsNothing);

    await tester.tap(find.byKey(const Key('lm-provider-gemini')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.lmPrivacyTitle), findsOneWidget);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(container.read(aiModelSettingsProvider).provider, AiProvider.gemma);

    await tester.tap(find.byKey(const Key('lm-provider-gemini')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lm-privacy-continue')));
    await tester.pumpAndSettle();
    expect(container.read(aiModelSettingsProvider).provider, AiProvider.gemini);
  });

  testWidgets('con cómo hablarles, se ofrecen OpenAI y Claude; elegir '
      'Claude avisa que es de pago y pide su clave', (tester) async {
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => now),
        cloudWiresProvider.overrideWithValue({
          AiProvider.gemini: wire,
          AiProvider.openAi: _FakeWire(AiProvider.openAi),
          AiProvider.anthropic: _FakeWire(AiProvider.anthropic),
        }),
        chatModelManagerProvider.overrideWithValue(FakeChatModelManager()),
      ],
    );
    addTearDown(container.dispose);
    await pump(tester);
    expect(find.byKey(const Key('lm-provider-openai')), findsOneWidget);
    expect(find.byKey(const Key('lm-provider-anthropic')), findsOneWidget);

    await tester.tap(find.byKey(const Key('lm-provider-anthropic')));
    await tester.pumpAndSettle();
    // El aviso es el de pago; el de la capa gratuita de Google sigue solo en
    // la página de atrás, que todavía es la de Gemini.
    final dialog = find.byType(AlertDialog);
    Finder inDialog(String text) =>
        find.descendant(of: dialog, matching: find.text(text));
    expect(inDialog(l10n.lmPrivacyPaid), findsOneWidget);
    expect(inDialog(l10n.lmPrivacyFreeTier), findsNothing);
    await tester.tap(find.byKey(const Key('lm-privacy-continue')));
    await tester.pumpAndSettle();

    expect(
      container.read(aiModelSettingsProvider).provider,
      AiProvider.anthropic,
    );
    expect(
      find.text(l10n.lmAccountsEmptyPaid(l10n.lmProviderAnthropic)),
      findsOneWidget,
    );
  });

  testWidgets('borrar una cuenta pide confirmar y la saca', (tester) async {
    final account = await addAccount('buena-1', 'Personal');
    await pump(tester);

    await tester.tap(find.byKey(Key('lm-account-menu-${account.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonDelete).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.lmAccountDeleteTitle('Personal')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lm-account-delete-confirm')));
    await tester.pumpAndSettle();

    expect(await container.read(aiAccountRepositoryProvider).list(), isEmpty);
    expect(find.byKey(const Key('lm-accounts-empty')), findsOneWidget);
  });

  group('los avisos', () {
    Future<void> pumpListener(WidgetTester tester, List<int> opened) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => AiNoticeListener(
              now: () => now,
              onOpenAccounts: () => opened.add(1),
              child: child!,
            ),
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
    }

    final from = AiAccount(
      id: 'a',
      provider: AiProvider.gemini,
      label: 'Personal',
      addedAt: now,
    );
    final to = AiAccount(
      id: 'b',
      provider: AiProvider.gemini,
      label: 'Trabajo',
      addedAt: now,
    );

    testWidgets('el cambio de cuenta dice a cuál, por qué y lleva a las '
        'cuentas', (tester) async {
      final opened = <int>[];
      await pumpListener(tester, opened);

      container
          .read(aiNoticeBusProvider)
          .notify(
            AccountSwitchedNotice(
              at: now,
              from: from,
              to: to,
              reason: CloudModelFailure.quotaExhausted,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(l10n.noticeSwitchedTitle('Trabajo')), findsOneWidget);
      expect(
        find.text(
          l10n.noticeSwitchedBodyNoTime(
            'Personal',
            l10n.lmFailureQuotaExhausted,
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.noticeActionAccounts));
      expect(opened, [1]);
    });

    testWidgets('un pedido que falló dice qué pasó de verdad y qué hacer', (
      tester,
    ) async {
      await pumpListener(tester, []);

      container
          .read(aiNoticeBusProvider)
          .notify(
            AiRequestFailedNotice(
              at: now,
              provider: AiProvider.gemini,
              failure: CloudModelFailure.timeout,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(l10n.lmHelpTimeout), findsOneWidget);
    });

    testWidgets('los reintentos no abren un aviso arriba de todo: los muestra '
        'quien espera', (tester) async {
      await pumpListener(tester, []);
      container.read(aiNoticeBusProvider)
        ..notify(
          AiRetryNotice(
            at: now,
            provider: AiProvider.gemini,
            failure: CloudModelFailure.network,
            attempt: 2,
            maxAttempts: 4,
            wait: const Duration(seconds: 3),
          ),
        )
        ..notify(AiRetryEndedNotice(at: now, provider: AiProvider.gemini));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('el mismo aviso seguido no se repite', (tester) async {
      await pumpListener(tester, []);
      final bus = container.read(aiNoticeBusProvider);
      final failed = AiRequestFailedNotice(
        at: now,
        provider: AiProvider.gemini,
        failure: CloudModelFailure.network,
      );

      bus.notify(failed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(l10n.noticeRequestFailedTitle), findsOneWidget);

      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold)),
      ).removeCurrentSnackBar();
      await tester.pump();
      bus.notify(failed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(l10n.noticeRequestFailedTitle), findsNothing);
    });
  });
}
