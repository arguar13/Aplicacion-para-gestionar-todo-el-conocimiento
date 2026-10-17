import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/language_model_missing.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Lo que dicen los botones que le piden algo a la IA cuando al modelo
/// elegido le falta algo (F32): con Gemma, bajarlo; con la nube, una clave o
/// la cuota. Cada caso con el botón que lo resuelve y adónde lleva.
void main() {
  final l10n = AppLocalizationsEs();
  late BuildContext hostContext;
  late List<bool?> results;

  Future<void> pump(
    WidgetTester tester,
    LanguageModelStatus status, {
    String? downloadMessage,
    String? downloadLabel,
  }) async {
    results = [];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                hostContext = context;
                return Column(
                  children: [
                    TextButton(
                      key: const Key('ask'),
                      onPressed: () async => results.add(
                        await ensureLanguageModelReady(
                          context,
                          ref,
                          downloadMessage: downloadMessage,
                          downloadLabel: downloadLabel,
                        ),
                      ),
                      child: const Text('pedir'),
                    ),
                    TextButton(
                      key: const Key('sheet'),
                      onPressed: () => unawaited(
                        showModalBottomSheet<void>(
                          context: context,
                          builder: (_) => Padding(
                            padding: const EdgeInsets.all(16),
                            child: LanguageModelMissingBanner(
                              status: status,
                              downloadMessage: downloadMessage,
                              downloadLabel: downloadLabel,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('hoja'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        GoRoute(
          path: RoutePaths.languageModel,
          builder: (_, _) => const Scaffold(body: Text('pantalla-modelo')),
        ),
        GoRoute(
          path: RoutePaths.chatModel,
          builder: (_, _) => const Scaffold(body: Text('pantalla-gemma')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          languageModelStatusCheckProvider.overrideWithValue(
            ({bool background = false}) async => status,
          ),
        ],
        child: MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ask(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ask')));
    await tester.pumpAndSettle();
  }

  Future<void> tapSnackAction(WidgetTester tester) async {
    await tester.tap(find.byType(SnackBarAction));
    await tester.pumpAndSettle();
  }

  testWidgets('con el modelo listo, deja pedir y no dice nada', (tester) async {
    await pump(tester, const LanguageModelReady(provider: AiProvider.gemini));
    await ask(tester);

    expect(results, [true]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Gemini sin clave: dice que es gratis y lleva a cargarla', (
    tester,
  ) async {
    await pump(
      tester,
      const LanguageModelNeedsAccount(provider: AiProvider.gemini),
      downloadMessage: 'lo de Gemma',
    );
    await ask(tester);

    expect(results, [false]);
    // Lo de bajar Gemma no tiene nada que ver con la nube.
    expect(find.text('lo de Gemma'), findsNothing);
    expect(
      find.text(l10n.lmMissingAccount(l10n.lmProviderGemini)),
      findsOneWidget,
    );
    expect(find.text(l10n.lmActionAddKey), findsOneWidget);

    await tapSnackAction(tester);
    expect(find.text('pantalla-modelo'), findsOneWidget);
  });

  testWidgets('un proveedor pago sin clave no promete que es gratis', (
    tester,
  ) async {
    await pump(
      tester,
      const LanguageModelNeedsAccount(provider: AiProvider.openAi),
    );
    await ask(tester);

    expect(
      find.text(l10n.lmMissingAccountPaid(l10n.lmProviderOpenAi)),
      findsOneWidget,
    );
    expect(
      find.text(l10n.lmMissingAccount(l10n.lmProviderOpenAi)),
      findsNothing,
    );
  });

  testWidgets('Gemma sin bajar: dice lo de cada pantalla y lleva a bajarlo', (
    tester,
  ) async {
    await pump(
      tester,
      const LanguageModelNeedsDownload(),
      downloadMessage: 'Para resumir hace falta Gemma.',
      downloadLabel: 'Bajar el modelo',
    );
    await ask(tester);

    expect(results, [false]);
    expect(find.text('Para resumir hace falta Gemma.'), findsOneWidget);
    await tester.tap(find.text('Bajar el modelo'));
    await tester.pumpAndSettle();
    expect(find.text('pantalla-gemma'), findsOneWidget);
  });

  testWidgets('Gemma sin bajar y sin texto propio: el de siempre', (
    tester,
  ) async {
    await pump(tester, const LanguageModelNeedsDownload());
    await ask(tester);

    expect(find.text(l10n.lmMissingDownload), findsOneWidget);
    expect(find.text(l10n.lmActionDownload), findsOneWidget);
  });

  testWidgets('sin cuota: dice hasta cuándo y lleva a las cuentas', (
    tester,
  ) async {
    final resetsAt = DateTime.now().add(const Duration(hours: 3));
    await pump(
      tester,
      LanguageModelOutOfQuota(
        provider: AiProvider.gemini,
        accounts: 2,
        resetsAt: resetsAt,
      ),
    );
    await ask(tester);

    expect(results, [false]);
    expect(
      find.text(l10n.lmMissingQuota(aiResetTime(hostContext, resetsAt))),
      findsOneWidget,
    );
    expect(find.text(l10n.noticeActionAccounts), findsOneWidget);
    await tapSnackAction(tester);
    expect(find.text('pantalla-modelo'), findsOneWidget);
  });

  testWidgets('sin cuota y sin saber hasta cuándo, no inventa una hora', (
    tester,
  ) async {
    await pump(
      tester,
      const LanguageModelOutOfQuota(provider: AiProvider.gemini, accounts: 1),
    );
    await ask(tester);

    expect(find.text(l10n.lmMissingQuotaNoTime), findsOneWidget);
  });

  testWidgets('con las claves rechazadas, dice que no andan, no la cuota', (
    tester,
  ) async {
    await pump(
      tester,
      LanguageModelOutOfQuota(
        provider: AiProvider.gemini,
        accounts: 2,
        resetsAt: DateTime.now().add(const Duration(hours: 3)),
        keysRejected: true,
      ),
    );
    await ask(tester);

    expect(find.text(l10n.lmMissingKeys), findsOneWidget);
    expect(find.textContaining('cuota'), findsNothing);
  });

  group('dentro de una hoja', () {
    testWidgets('sin clave: el aviso con la llave, y el botón cierra la hoja '
        'antes de ir', (tester) async {
      await pump(
        tester,
        const LanguageModelNeedsAccount(provider: AiProvider.gemini),
      );
      await tester.tap(find.byKey(const Key('sheet')));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.lmMissingAccount(l10n.lmProviderGemini)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.key_outlined), findsOneWidget);

      await tester.tap(find.text(l10n.lmActionAddKey));
      await tester.pumpAndSettle();
      // Fuera de escena también: si quedara abierta, estaría debajo de la
      // pantalla nueva y volvería al ir para atrás.
      expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
      expect(find.text('pantalla-modelo'), findsOneWidget);
    });

    testWidgets('Gemma sin bajar: el aviso de bajar y lleva a Gemma', (
      tester,
    ) async {
      await pump(
        tester,
        const LanguageModelNeedsDownload(),
        downloadMessage: 'Para las tarjetas hace falta Gemma.',
      );
      await tester.tap(find.byKey(const Key('sheet')));
      await tester.pumpAndSettle();

      expect(find.text('Para las tarjetas hace falta Gemma.'), findsOneWidget);
      expect(find.byIcon(Icons.download_for_offline_outlined), findsOneWidget);

      await tester.tap(find.text(l10n.lmActionDownload));
      await tester.pumpAndSettle();
      // Fuera de escena también: si quedara abierta, estaría debajo de la
      // pantalla nueva y volvería al ir para atrás.
      expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
      expect(find.text('pantalla-gemma'), findsOneWidget);
    });
  });
}
