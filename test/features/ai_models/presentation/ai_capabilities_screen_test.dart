import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/screens/ai_capabilities_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/illustration_harness.dart';

final _l10n = AppLocalizationsEs();

void main() {
  late IllustrationHarness harness;

  Future<void> seedAccounts() async {
    final accounts = harness.container.read(aiAccountRepositoryProvider);
    final gemini = await accounts.add(
      provider: AiProvider.gemini,
      key: 'AIza1',
      label: 'Personal',
    );
    final openAi = await accounts.add(
      provider: AiProvider.openAi,
      key: 'sk-1',
      label: 'Empresa',
    );
    await accounts.add(
      provider: AiProvider.anthropic,
      key: 'sk-ant',
      label: 'Escritura',
    );
    final store = harness.container.read(illustrationStoreProvider);
    await store.setCapability(
      gemini.id,
      ImageCapability.succeeded('gemini-nano-banana-2.1', DateTime.utc(2026)),
    );
    await store.setCapability(
      openAi.id,
      const ImageCapability(
        state: ImageCapabilityState.cannot,
        reason: ImageFailure.orgUnverified,
      ),
    );
    await harness.container
        .read(imageAccountRepositoryProvider)
        .add(provider: IllustrationProvider.huggingFace, key: 'hf_1');
  }

  testWidgets('la tabla por proveedor, cada cuenta con su estado, la fecha de '
      'los precios y los modelos abiertos; sin motor, sin la sección del '
      'teléfono', (tester) async {
    harness = await IllustrationHarness.create();
    addTearDown(harness.container.dispose);
    await seedAccounts();
    await harness.pump(
      tester,
      const AiCapabilitiesScreen(),
      height: 9000,
      scroll: false,
    );

    expect(find.text(_l10n.f43AiPricesAsOf('28/10/2026')), findsOneWidget);
    for (final row in [
      AiCapabilityRow.gemma,
      AiCapabilityRow.claude,
      AiCapabilityRow.gemini,
      AiCapabilityRow.openAi,
      AiCapabilityRow.huggingFace,
    ]) {
      expect(find.byKey(Key('ai-capability-row-${row.name}')), findsOneWidget);
    }
    expect(find.text(_l10n.f43AiRowClaudeImages), findsOneWidget);
    expect(find.text(_l10n.f43AiRowGeminiImages), findsOneWidget);

    // Las cuentas: Claude solo texto, Gemini puede, OpenAI no puede (con su
    // porqué y «Probar ahora»), Hugging Face sin probar.
    expect(find.text(_l10n.f43AiTextOnly), findsOneWidget);
    expect(find.text(_l10n.f43AiStateCan), findsOneWidget);
    expect(find.text(_l10n.f43AiStateCannot), findsOneWidget);
    expect(
      find.text('La organización de OpenAI de «Empresa» no está verificada'),
      findsOneWidget,
    );
    expect(find.text(_l10n.f43AiStateUntested), findsOneWidget);
    expect(find.text(_l10n.f43AiProbe), findsNWidgets(2));

    for (final model in kOpenImageModels) {
      expect(find.text(model.name), findsOneWidget);
    }
    expect(find.text('Qwen-Image'), findsNothing);
    expect(find.text(_l10n.f43AiOpenViaHf), findsNWidgets(4));
    expect(find.text(_l10n.f43AiLicenseStability), findsOneWidget);
    expect(find.text(_l10n.f43AiLicenseApache), findsNWidgets(3));
    expect(find.byKey(const Key('ai-capabilities-on-device')), findsNothing);
  });

  testWidgets('con un motor del teléfono aparece «Exigente — en el '
      'teléfono»', (tester) async {
    harness = await IllustrationHarness.create(onDevice: FakeOnDeviceEngine());
    addTearDown(harness.container.dispose);
    await harness.pump(tester, const AiCapabilitiesScreen(), scroll: false);

    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-capabilities-on-device')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(_l10n.f43AiOnDeviceIntro), findsOneWidget);
    expect(find.text(_l10n.f43AiRowDeviceImages), findsOneWidget);
    expect(find.text('SDXS 512'), findsOneWidget);
  });

  testWidgets('«Probar ahora» hace un solo pedido de una imagen chica y dice '
      'lo que supo', (tester) async {
    harness = await IllustrationHarness.create();
    addTearDown(harness.container.dispose);
    await seedAccounts();
    await harness.pump(tester, const AiCapabilitiesScreen(), scroll: false);

    final openAi =
        (await harness.container.read(aiAccountRepositoryProvider).list())
            .firstWhere((a) => a.provider == AiProvider.openAi);
    final probe = find.byKey(Key('ai-probe-${openAi.id}'));
    await tester.ensureVisible(probe);
    await tester.pumpAndSettle();
    await tester.tap(probe);
    await tester.pumpAndSettle();

    final wire = harness.wires[IllustrationProvider.openAi]!;
    expect(wire.generated.single.size, IllustrationSize.small);
    expect(find.text(_l10n.f43AiProbeOk('Empresa')), findsOneWidget);
    expect(
      harness.container
          .read(illustrationStoreProvider)
          .capabilityOf(openAi.id)
          .can,
      isTrue,
    );
  });

  testWidgets('en 360 dp con el texto al doble, claro y oscuro, sin '
      'desbordes', (tester) async {
    harness = await IllustrationHarness.create(onDevice: FakeOnDeviceEngine());
    addTearDown(harness.container.dispose);
    await seedAccounts();
    for (final theme in [kAllAppThemes.first, kAllAppThemes[1]]) {
      await harness.pump(
        tester,
        const AiCapabilitiesScreen(),
        width: 360,
        height: 760,
        textScale: 2,
        theme: theme,
        scroll: false,
      );
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 40; i++) {
        await tester.drag(list, const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    }
  });
}
