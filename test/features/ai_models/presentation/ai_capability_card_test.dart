import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/ai_models/domain/entities/account_usage.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/presentation/screens/ai_capabilities_screen.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_capability_card.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_usage_bar.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/illustration_harness.dart';

final _at = DateTime.utc(2026, 10, 28);
final _l10n = AppLocalizationsEs();

/// Como los escribe la app en español.
String _pct(int n) => NumberFormat.percentPattern('es').format(n / 100);
String _tokens(int n) => NumberFormat.compact(locale: 'es').format(n);

ImageSide _side(
  String id,
  IllustrationProvider provider, {
  ImageCapabilityState state = ImageCapabilityState.can,
  ImageFailure? reason,
}) => ImageSide(
  account: IllustrationAccount(
    id: id,
    provider: provider,
    label: id == 'g' ? 'Personal' : 'Trabajo',
    addedAt: _at,
  ),
  capability: ImageCapability(state: state, reason: reason),
  model: provider == IllustrationProvider.gemini
      ? 'gemini-nano-banana-2.1'
      : 'gpt-image-1-mini',
  modelLabel: provider == IllustrationProvider.gemini
      ? 'Nano Banana 2.1'
      : 'GPT Image 1 Mini',
);

CreationEstimate _gemini({
  ImageCapabilityState state = ImageCapabilityState.can,
  ImageFailure? reason,
  List<ImageSide> others = const [],
}) => const CreationCostEstimator().estimate(
  text: TextSide(
    provider: AiProvider.gemini,
    model: 'gemini-3.8-flash',
    modelLabel: 'Gemini 3.8 Flash',
    accountId: 'g',
    accountLabel: 'Personal',
    usage: const AccountUsage(accountId: 'g', day: 'd', requests: 105),
    quota: defaultDailyQuota(AiProvider.gemini),
  ),
  inputTokens: 12000,
  expectedOutputTokens: 3000,
  images: 6,
  imageAccounts: [
    _side('g', IllustrationProvider.gemini, state: state, reason: reason),
    ...others,
  ],
);

void main() {
  late IllustrationHarness harness;

  setUp(() async {
    harness = await IllustrationHarness.create();
    addTearDown(harness.container.dispose);
  });

  testWidgets('con Gemini que puede: ✓ escribir y dibujar, lo que consume y '
      'el porcentaje de la cuota (estimado)', (tester) async {
    await harness.pump(tester, AiCapabilityCard(estimate: _gemini()));

    expect(find.text(_l10n.f43AiCardTitle), findsOneWidget);
    expect(find.text(_l10n.f43AiWriteWith('Gemini 3.8 Flash')), findsOneWidget);
    expect(
      find.text(_l10n.f43AiIllustrateWith(6, 'Nano Banana 2.1 · Personal')),
      findsOneWidget,
    );
    expect(find.text(_l10n.f43AiTokensRead(_tokens(12000))), findsOneWidget);
    expect(find.text(_l10n.f43AiTokensWrite(_tokens(3000))), findsOneWidget);
    expect(find.text(_l10n.f43AiTextFree), findsOneWidget);
    expect(find.textContaining(r'6 imágenes 1K · ≈ US$ 0,2'), findsOneWidget);
    // 1 pedido de texto + 6 de imagen de 250 → 3 %; 105 usados → 42 %.
    expect(
      find.text(
        '${_l10n.f43AiQuotaShare(_pct(3), _pct(42))} '
        '(${_l10n.f43AiEstimated})',
      ),
      findsOneWidget,
    );
    expect(find.text(_l10n.f43AiAltTitle), findsNothing);
  });

  testWidgets('sin facturación: ✗ con el nombre de la cuenta y las opciones '
      'en orden, que se eligen con un toque', (tester) async {
    final chosen = <IllustrationAlternative>[];
    await harness.pump(
      tester,
      AiCapabilityCard(
        estimate: _gemini(
          state: ImageCapabilityState.cannot,
          reason: ImageFailure.noBilling,
          others: [_side('o', IllustrationProvider.openAi)],
        ),
        onAlternative: chosen.add,
      ),
    );

    expect(
      find.text(
        _l10n.f43AiIllustrateBlocked(_l10n.f43AiReasonNoBilling('Personal')),
      ),
      findsOneWidget,
    );
    expect(find.text(_l10n.f43AiAltTitle), findsOneWidget);
    expect(find.text('1. ${_l10n.f43AiAltWithout}'), findsOneWidget);
    expect(
      find.text('2. ${_l10n.f43AiAltUseAccount('OpenAI', 'Trabajo')}'),
      findsOneWidget,
    );
    expect(find.text('3. ${_l10n.f43AiAltAddGemini}'), findsOneWidget);
    expect(find.text('4. ${_l10n.f43AiAltHuggingFace}'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-alternative-1')));
    await tester.tap(find.byKey(const Key('ai-alternative-2')));
    expect(chosen.first, const ContinueWithoutIllustrations());
    expect((chosen.last as UseOtherImageAccount).account.id, 'o');
  });

  testWidgets('con Claude: «Claude no genera imágenes»', (tester) async {
    final estimate = const CreationCostEstimator().estimate(
      text: const TextSide(
        provider: AiProvider.anthropic,
        model: 'claude-sonnet-5-5',
        modelLabel: 'Claude Sonnet 5.5',
        accountId: 'c',
        accountLabel: 'Claude',
      ),
      inputTokens: 100000,
      expectedOutputTokens: 10000,
      images: 2,
    );
    await harness.pump(tester, AiCapabilityCard(estimate: estimate));

    expect(
      find.text(
        _l10n.f43AiIllustrateBlocked(_l10n.f43AiReasonProviderCannot('Claude')),
      ),
      findsOneWidget,
    );
    expect(find.text(_l10n.f43AiTextCost(r'US$ 0,3')), findsOneWidget);
    expect(find.byKey(const Key('ai-capability-quota-c')), findsOneWidget);
    expect(find.text(_l10n.f43AiQuotaNone), findsOneWidget);
  });

  testWidgets('con Gemma: el tiempo en el teléfono, sin cuota', (tester) async {
    final estimate = const CreationCostEstimator().estimate(
      text: const TextSide(provider: AiProvider.gemma),
      inputTokens: 1000,
      expectedOutputTokens: 400,
    );
    await harness.pump(tester, AiCapabilityCard(estimate: estimate));

    expect(find.byKey(const Key('ai-capability-local')), findsOneWidget);
    expect(
      find.textContaining(_l10n.f43AiLocalTime('1 minuto (estimado)')),
      findsOneWidget,
    );
  });

  testWidgets('ⓘ abre «¿Qué puede cada IA?»', (tester) async {
    await harness.pump(tester, AiCapabilityCard(estimate: _gemini()));
    await tester.tap(find.byKey(const Key('ai-capability-info')));
    await tester.pumpAndSettle();
    expect(find.byType(AiCapabilitiesScreen), findsOneWidget);
  });

  testWidgets('en 360 dp con el texto al doble, en los nueve temas, sin '
      'desbordes', (tester) async {
    for (final theme in kAllAppThemes) {
      await harness.pump(
        tester,
        Column(
          children: [
            AiCapabilityCard(
              estimate: _gemini(
                state: ImageCapabilityState.cannot,
                reason: ImageFailure.noBilling,
                others: [_side('o', IllustrationProvider.openAi)],
              ),
            ),
            const SizedBox(height: 12),
            AiUsageBar(estimate: _gemini()),
          ],
        ),
        width: 360,
        height: 4000,
        textScale: 2,
        theme: theme,
      );
      expect(tester.takeException(), isNull);
    }
  });

  group('«Uso de IA»', () {
    testWidgets('lo usado y lo de esta creación, en dos tonos', (tester) async {
      await harness.pump(
        tester,
        SizedBox(width: 300, child: AiUsageBar(estimate: _gemini())),
      );
      expect(
        find.text(
          '${_l10n.f43AiUsageLegendToday(_pct(42))} · '
          '${_l10n.f43AiUsageLegendThis(_pct(3))} (${_l10n.f43AiEstimated})',
        ),
        findsOneWidget,
      );
      final used = tester.getSize(find.byKey(const Key('ai-usage-used')));
      final mine = tester.getSize(find.byKey(const Key('ai-usage-estimate')));
      expect(used.width, closeTo(300 * 0.42, 0.5));
      expect(mine.width, closeTo(300 * 0.028, 0.5));
    });

    testWidgets('con Gemma: sin cuota, cuánto tarda', (tester) async {
      final estimate = const CreationCostEstimator().estimate(
        text: const TextSide(provider: AiProvider.gemma),
        inputTokens: 100,
        expectedOutputTokens: 80,
      );
      await harness.pump(tester, AiUsageBar(estimate: estimate));
      expect(find.text(_l10n.f43AiLocalTime('11 segundos')), findsOneWidget);
      expect(find.byKey(const Key('ai-usage-used')), findsNothing);
    });

    testWidgets('sin cuota fijada, lo dice', (tester) async {
      final estimate = const CreationCostEstimator().estimate(
        text: const TextSide(
          provider: AiProvider.openAi,
          accountId: 'o',
          accountLabel: 'O',
        ),
        inputTokens: 100,
        expectedOutputTokens: 80,
      );
      await harness.pump(tester, AiUsageBar(estimate: estimate));
      expect(find.text(_l10n.f43AiUsageNoQuota), findsOneWidget);
    });
  });
}
