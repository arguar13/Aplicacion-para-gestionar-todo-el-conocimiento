import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/daily_quota.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_key_sheet.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/illustration_settings_section.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/illustration_harness.dart';

final _l10n = AppLocalizationsEs();
final _now = DateTime.utc(2026, 10, 28, 15);
String _pct(int n) => NumberFormat.percentPattern('es').format(n / 100);

void main() {
  late IllustrationHarness harness;

  setUp(() async {
    harness = await IllustrationHarness.create(now: _now);
    addTearDown(harness.container.dispose);
  });

  testWidgets('cada cuenta con si dibuja y su cuota de hoy: la estimada de '
      'Gemini, «sin cuota» en los pagos', (tester) async {
    final accounts = harness.container.read(aiAccountRepositoryProvider);
    final gemini = await accounts.add(
      provider: AiProvider.gemini,
      key: 'k',
      label: 'Personal',
    );
    final claude = await accounts.add(
      provider: AiProvider.anthropic,
      key: 'k',
      label: 'Escritura',
    );
    for (var i = 0; i < 25; i++) {
      await harness.container
          .read(aiUsageLedgerProvider)
          .recordRequest(
            gemini.id,
            now: _now,
            inputTokens: 1,
            outputTokens: 1,
            background: false,
          );
    }

    await harness.pump(tester, const IllustrationSettingsSection());

    expect(
      find.text(
        '${_l10n.f43AiQuotaPerDay(_l10n.f43AiQuotaRequests(250))} '
        '(${_l10n.f43AiEstimated}) · ${_l10n.f43AiQuotaTodayPercent(_pct(10))}',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('illustration-account-quota-${claude.id}')),
      findsOneWidget,
    );
    expect(find.text(_l10n.f43AiQuotaUnset), findsOneWidget);
    expect(
      find.text('${_l10n.lmProviderGemini} · ${_l10n.f43AiStateUntested}'),
      findsOneWidget,
    );
    expect(
      find.text('${_l10n.lmProviderAnthropic} · ${_l10n.f43AiTextOnly}'),
      findsOneWidget,
    );
  });

  testWidgets('tocar una cuenta abre su cuota; guardarla cambia el '
      'porcentaje, y se puede volver a la estimada', (tester) async {
    final gemini = await harness.container
        .read(aiAccountRepositoryProvider)
        .add(provider: AiProvider.gemini, key: 'k', label: 'Personal');
    await harness.pump(tester, const IllustrationSettingsSection());

    await tester.tap(find.byKey(Key('illustration-account-${gemini.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('daily-quota-sheet')), findsOneWidget);
    expect(
      find.text(_l10n.f43AiQuotaDefaultIs(_l10n.f43AiQuotaRequests(250))),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('daily-quota-images')), '0');
    await tester.tap(find.byKey(const Key('daily-quota-save')));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.f43AiQuotaInvalid), findsOneWidget);

    await tester.enterText(find.byKey(const Key('daily-quota-images')), '');
    await tester.enterText(find.byKey(const Key('daily-quota-requests')), '50');
    await tester.enterText(find.byKey(const Key('daily-quota-usd')), '1,5');
    await tester.tap(find.byKey(const Key('daily-quota-save')));
    await tester.pumpAndSettle();

    final store = harness.container.read(illustrationStoreProvider);
    expect(
      store.userQuotaOf(gemini.id),
      const DailyQuota(requests: 50, usd: 1.5),
    );
    expect(find.byKey(const Key('daily-quota-sheet')), findsNothing);
    expect(find.textContaining(_l10n.f43AiQuotaRequests(50)), findsOneWidget);
    expect(find.textContaining(_l10n.f43AiEstimated), findsNothing);

    await tester.tap(find.byKey(Key('illustration-account-${gemini.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('daily-quota-reset')));
    await tester.pumpAndSettle();
    expect(store.userQuotaOf(gemini.id), isNull);
  });

  testWidgets('agregar Hugging Face: el token se prueba; uno malo no se '
      'guarda, uno bueno sí, con sus modelos', (tester) async {
    await harness.pump(tester, const IllustrationSettingsSection());
    final wire = harness.wires[IllustrationProvider.huggingFace]!
      ..listFailure = ImageFailure.invalidKey;

    await tester.tap(find.byKey(const Key('illustration-settings-add-hf')));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.f43AiHfCredits), findsOneWidget);
    await tester.enterText(find.byKey(const Key('hf-token-value')), 'hf_malo');
    await tester.pump();
    await tester.tap(find.byKey(const Key('hf-token-save')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        _l10n.lmTestFailed(_l10n.f43AiReasonInvalidKey('Hugging Face')),
      ),
      findsOneWidget,
    );
    final repository = harness.container.read(imageAccountRepositoryProvider);
    expect(await repository.list(), isEmpty);

    wire
      ..listFailure = null
      ..models = const [
        ImageModelInfo(
          id: 'black-forest-labs/FLUX.1-schnell',
          displayName: 'FLUX.1 [schnell]',
          route: 'nscale|black-forest-labs/FLUX.1-schnell',
        ),
      ];
    await tester.enterText(find.byKey(const Key('hf-token-value')), 'hf_bueno');
    await tester.pump();
    await tester.tap(find.byKey(const Key('hf-token-save')));
    await tester.pumpAndSettle();

    final saved = (await repository.list()).single;
    expect(await repository.keyOf(saved.id), 'hf_bueno');
    expect(
      harness.container
          .read(illustrationServiceProvider)
          .cachedImageModelsOf(saved.id)
          .single
          .route,
      'nscale|black-forest-labs/FLUX.1-schnell',
    );
    expect(find.text('Hugging Face 1'), findsOneWidget);
  });

  testWidgets('la hoja de claves de Gemini y OpenAI dice lo que pide '
      'dibujar', (tester) async {
    await harness.pump(
      tester,
      Builder(
        builder: (context) => Column(
          children: [
            TextButton(
              key: const Key('open-gemini'),
              onPressed: () =>
                  showAiKeySheet(context, provider: AiProvider.gemini),
              child: const Text('g'),
            ),
            TextButton(
              key: const Key('open-openai'),
              onPressed: () =>
                  showAiKeySheet(context, provider: AiProvider.openAi),
              child: const Text('o'),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-gemini')));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.f43AiKeyGeminiBilling), findsOneWidget);
    expect(find.text(_l10n.f43AiKeyGeminiPrice(r'US$ 0,034')), findsOneWidget);
    Navigator.of(tester.element(find.text(_l10n.f43AiKeyGeminiBilling))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-openai')));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.f43AiKeyOpenAiVerify), findsOneWidget);
    expect(
      find.text(_l10n.f43AiKeyOpenAiPrice('GPT Image 1 Mini', r'US$ 0,0084')),
      findsOneWidget,
    );
  });

  testWidgets('en 360 dp con el texto al doble, en los nueve temas, sin '
      'desbordes', (tester) async {
    final accounts = harness.container.read(aiAccountRepositoryProvider);
    await accounts.add(
      provider: AiProvider.gemini,
      key: 'k',
      label: 'una-cuenta-con-un-nombre-largo@gmail.com',
    );
    await accounts.add(provider: AiProvider.openAi, key: 'k');
    await harness.container
        .read(imageAccountRepositoryProvider)
        .add(provider: IllustrationProvider.huggingFace, key: 'hf');
    for (final theme in kAllAppThemes) {
      await harness.pump(
        tester,
        const IllustrationSettingsSection(),
        width: 360,
        height: 3000,
        textScale: 2,
        theme: theme,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
