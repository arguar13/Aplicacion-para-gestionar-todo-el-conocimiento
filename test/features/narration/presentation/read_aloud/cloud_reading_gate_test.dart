import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/cloud_reading_gate.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_kind_badges.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/my_voices_harness.dart';

final _cloned = MyVoice(
  id: 'v1',
  name: 'Papá',
  origin: VoiceOrigin.cloned,
  home: MyVoiceHome.elevenLabs,
  locale: 'es-AR',
  createdAt: DateTime.utc(2026, 10, 31),
  cloudVoiceId: 'eleven-1',
  consent: VoiceConsent(
    kind: VoiceConsentKind.permission,
    personName: 'Jorge',
    grantedAt: DateTime.utc(2026, 10, 31),
  ),
);

final _created = MyVoice(
  id: 'v2',
  name: 'Serena',
  origin: VoiceOrigin.created,
  home: MyVoiceHome.phone,
  locale: 'es',
  createdAt: DateTime.utc(2026, 10, 31),
  blend: KokoroBlend(
    locale: 'es',
    timbre: const [BlendPart(28, 0.5), BlendPart(3, 0.5)],
    prosody: const [BlendPart(28, 1)],
  ),
  slot: 0,
);

void main() {
  final es = AppLocalizationsEs();

  group('el aviso de costo al leer en la nube', () {
    late MyVoicesHarness harness;
    late ProviderContainer container;

    Future<void> mount(
      WidgetTester tester, {
      double textScale = 1,
      ThemeMode themeMode = ThemeMode.light,
    }) async {
      harness = await MyVoicesHarness.create(cloudEnabled: true, cloudKey: 'k');
      addTearDown(harness.dispose);
      await harness.store.save(_cloned);
      tester.view
        ..physicalSize = const Size(360, 760)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final navigator = GlobalKey<NavigatorState>();
      container = ProviderContainer(overrides: harness.overrides);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigator,
            locale: const Locale('es'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: themeMode,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: CloudReadingGateHost(
                navigatorKey: navigator,
                child: child!,
              ),
            ),
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<bool?> ask(WidgetTester tester) async {
      bool? answer;
      final pending = container
          .read(cloudReadingGateProvider)
          .approve(voice: _cloned.narrationVoice, characters: 4321);
      unawaited(pending.then((value) => answer = value));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('dice el nombre, los caracteres, los créditos, lo que sale y '
        'lo que queda; aprobar contesta que sí', (tester) async {
      await mount(tester);
      bool? answer;
      unawaited(
        container
            .read(cloudReadingGateProvider)
            .approve(voice: _cloned.narrationVoice, characters: 4321)
            .then((value) => answer = value),
      );
      await tester.pumpAndSettle();
      expect(find.text(es.f47P4ReadCloudTitle('Papá')), findsOneWidget);
      expect(
        find.text(es.f47P4ReadCloudCost('4.321', '4.321')),
        findsOneWidget,
      );
      expect(find.text(es.f47P4ReadCloudLeaves), findsOneWidget);
      expect(find.text(es.f47P4CreditsLeft('29.000')), findsOneWidget);
      expect(answer, isNull);
      await tester.tap(find.byKey(const Key('cloud-reading-approve')));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });

    testWidgets('cancelar contesta que no', (tester) async {
      await mount(tester);
      bool? answer;
      unawaited(
        container
            .read(cloudReadingGateProvider)
            .approve(voice: _cloned.narrationVoice, characters: 2000)
            .then((value) => answer = value),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-reading-cancel')));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('a 360 dp con la letra al doble, en ${mode.name}', (
        tester,
      ) async {
        await mount(tester, textScale: 2, themeMode: mode);
        await ask(tester);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('cloud-reading-cost')), findsOneWidget);
      });
    }

    test('sin pantalla que pregunte, contesta que no; soltar una vieja no '
        'suelta la nueva', () async {
      final gate = CloudReadingGate();
      expect(
        await gate.approve(voice: _cloned.narrationVoice, characters: 1),
        isFalse,
      );
      final first = gate.attach((_, _) async => true);
      gate.attach((_, _) async => true);
      first();
      expect(
        await gate.approve(voice: _cloned.narrationVoice, characters: 1),
        isTrue,
      );
    });
  });

  group('lo que el reproductor dice de la voz', () {
    test('clonada en la nube, creada en el teléfono, y del teléfono nada', () {
      final [cloned, created] = myVoiceProfiles([_cloned, _created]);
      expect(voiceKindBadges(cloned, es), [
        es.f47P4BadgeCloned,
        es.f47P4BadgeCloud,
      ]);
      expect(voiceKindBadges(created, es), [es.f47P4BadgeCreated]);
      final device = voiceProfileOf(
        const NarrationVoice(name: 'es-ar-x-local', locale: 'es-AR'),
      )!;
      expect(voiceKindBadges(device, es), isEmpty);
    });

    testWidgets('el lector de pantalla las oye juntas', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VoiceKindBadgeRow(voice: myVoiceProfiles([_cloned]).single),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('${es.f47P4BadgeCloned}, ${es.f47P4BadgeCloud}'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });
}
