import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/clone_voice_screen.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/create_voice_screen.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_library_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_settings_tiles.dart';
import 'package:sinapsis/features/narration/presentation/voices/voices_by_language_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/my_voices_harness.dart';

final _created = MyVoice(
  id: 'creada',
  name: 'Serena',
  origin: VoiceOrigin.created,
  home: MyVoiceHome.phone,
  locale: 'es',
  createdAt: DateTime.utc(2026, 10, 31, 10),
  gender: VoiceGender.female,
  timbre: VoiceTimbre.velvety,
  styles: const {VoiceStyle.calm},
  blend: KokoroBlend(
    locale: 'es',
    timbre: const [BlendPart(28, 0.6), BlendPart(3, 0.4)],
    prosody: const [BlendPart(28, 1)],
  ),
);

final _cloned = MyVoice(
  id: 'clonada',
  name: 'Papá',
  origin: VoiceOrigin.cloned,
  home: MyVoiceHome.elevenLabs,
  locale: 'es-AR',
  createdAt: DateTime.utc(2026, 10, 31, 11),
  cloudVoiceId: 'eleven-1',
  consent: VoiceConsent(
    kind: VoiceConsentKind.permission,
    personName: 'Jorge',
    grantedAt: DateTime.utc(2026, 10, 30, 12),
  ),
  sampleFile: 'muestra.mp3',
);

void main() {
  final es = AppLocalizationsEs();
  late MyVoicesHarness harness;
  late ProviderContainer container;

  Finder byKey(String key) => find.byKey(Key(key));

  /// Baja la lista de Mías hasta [target]: la lista arma lo que se ve.
  Future<void> reveal(WidgetTester tester, Finder target) =>
      tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.descendant(
          of: byKey('voice-library-list-mine'),
          matching: find.byType(Scrollable),
        ),
      );

  Future<void> openMine(
    WidgetTester tester, {
    bool cloud = true,
    bool kokoro = true,
    List<MyVoice> voices = const [],
    double textScale = 1,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    harness = await MyVoicesHarness.create(
      cloudEnabled: cloud,
      cloudKey: cloud ? 'sk' : null,
      kokoro: kokoro,
    );
    addTearDown(harness.dispose);
    for (final voice in voices) {
      await harness.store.save(voice);
    }
    await harness.store.write('clonada', [1, 2, 3], 'muestra.mp3');
    container = await pumpMyVoices(
      tester,
      harness,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showVoiceLibrary(context),
          child: const Text('Voces'),
        ),
      ),
      textScale: textScale,
      themeMode: themeMode,
      extra: [readingLanguageProvider.overrideWith((ref) => 'es')],
    );
    await tester.tap(find.text('Voces'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.f47P3TabMine));
    await tester.pumpAndSettle();
  }

  testWidgets('arriba, clonar y crear; sin voces, qué va a haber', (
    tester,
  ) async {
    await openMine(tester);
    expect(byKey('my-voices-clone'), findsOneWidget);
    expect(byKey('my-voices-create'), findsOneWidget);
    expect(find.text(es.f47P4MineEmpty), findsOneWidget);
    await tapShown(tester, byKey('my-voices-clone'));
    expect(find.byType(CloneVoiceScreen), findsOneWidget);
  });

  testWidgets('«Crear una voz» abre su pantalla', (tester) async {
    await openMine(tester);
    await tapShown(tester, byKey('my-voices-create'));
    expect(find.byType(CreateVoiceScreen), findsOneWidget);
  });

  testWidgets('cada voz dice de dónde es, y la de la nube lo que cuesta', (
    tester,
  ) async {
    await openMine(tester, voices: [_created, _cloned]);
    expect(find.text(es.f47P4MineEmpty), findsNothing);
    final created = find.text('${es.f47P3OriginCreated} · ${es.f47P4OnPhone}');
    await reveal(tester, created);
    expect(created, findsOneWidget);
    final cloned = find.text(
      '${es.f47P3OriginCloned} · ${es.f47P4InCloud} · '
      '${es.f47P4CreditPerCharacter(1)}',
    );
    await reveal(tester, cloned);
    expect(cloned, findsOneWidget);
  });

  testWidgets('sin la nube, la de la nube no lee y lo dice; sin Kokoro, la '
      'creada tampoco', (tester) async {
    await openMine(
      tester,
      cloud: false,
      kokoro: false,
      voices: [_created, _cloned],
    );
    final kokoro = find.textContaining(es.f47P4NeedsKokoro);
    await reveal(tester, kokoro);
    expect(kokoro, findsOneWidget);
    final cloud = find.textContaining(es.f47P4NeedsCloud);
    await reveal(tester, cloud);
    expect(cloud, findsOneWidget);
  });

  testWidgets('elegir una voz propia la deja para su idioma', (tester) async {
    await openMine(tester, voices: [_cloned]);
    await tapShown(tester, find.text('Papá 🇦🇷'));
    expect(
      container.read(narrationSettingsNotifierProvider).voicesByLanguage['es'],
      _cloned.narrationVoice,
    );
  });

  testWidgets('la muestra de una de la nube es la guardada: oírla no gasta', (
    tester,
  ) async {
    await openMine(tester, voices: [_cloned]);
    await tapShown(tester, byKey('voice-sample-mia:clonada'));
    final played = harness.clips.played.single as FileSpeechClip;
    expect(played.path, endsWith('muestra.mp3'));
    expect(harness.cloud.spoken, isEmpty);
  });

  group('su hoja', () {
    testWidgets('muestra el consentimiento, cambia el nombre y la cara', (
      tester,
    ) async {
      await openMine(tester, voices: [_cloned]);
      await tapShown(tester, byKey('voice-mine-actions-mia:clonada'));
      expect(byKey('my-voice-consent'), findsOneWidget);
      expect(find.textContaining('Jorge'), findsWidgets);
      await tester.enterText(byKey('my-voice-rename'), 'Viejo');
      await tapShown(tester, byKey('my-voice-next-face'));
      await tapShown(tester, byKey('my-voice-save'));
      final saved = (await harness.store.list()).single;
      expect(saved.name, 'Viejo');
      expect(saved.faceSeed, 1);
      expect(saved.consent, _cloned.consent);
    });

    testWidgets('borrar pregunta, borra en ElevenLabs y acá, y deja su '
        'idioma sin elegida', (tester) async {
      await openMine(tester, voices: [_cloned]);
      await container
          .read(narrationSettingsNotifierProvider.notifier)
          .selectVoice(_cloned.narrationVoice);
      await tapShown(tester, byKey('voice-mine-actions-mia:clonada'));
      await tapShown(tester, byKey('my-voice-delete'));
      expect(find.text(es.f47P4DeleteVoiceCloud), findsOneWidget);
      await tapShown(tester, byKey('my-voice-delete-yes'));
      expect(harness.cloud.deleted, ['eleven-1']);
      expect(await harness.store.list(), isEmpty);
      expect(
        container.read(narrationSettingsNotifierProvider).voicesByLanguage,
        isEmpty,
      );
      expect(find.text(es.f47P4Deleted('Papá')), findsOneWidget);
    });

    testWidgets('si en ElevenLabs no se pudo, acá queda, y se puede borrar '
        'solo acá', (tester) async {
      await openMine(tester, voices: [_cloned]);
      harness.cloud.failures['deleteVoice'] = const VoiceCloudException(
        VoiceCloudFailure.network,
      );
      await tapShown(tester, byKey('voice-mine-actions-mia:clonada'));
      await tapShown(tester, byKey('my-voice-delete'));
      await tapShown(tester, byKey('my-voice-delete-yes'));
      expect(byKey('my-voice-delete-error'), findsOneWidget);
      expect(await harness.store.list(), hasLength(1));
      await tapShown(tester, byKey('my-voice-delete-here'));
      expect(await harness.store.list(), isEmpty);
      expect(harness.cloud.deleted, isEmpty);
    });
  });

  group('a 360 dp con la letra al doble', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('Mías y la hoja de una voz, sin desbordar, en ${mode.name}', (
        tester,
      ) async {
        await openMine(
          tester,
          voices: [_created, _cloned],
          textScale: 2,
          themeMode: mode,
        );
        expect(tester.takeException(), isNull);
        await reveal(tester, byKey('voice-mine-actions-mia:clonada'));
        expect(tester.takeException(), isNull);
        await tapShown(tester, byKey('voice-mine-actions-mia:clonada'));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el lector de pantalla oye clonar y crear como botones', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openMine(tester);
      expect(
        tester.getSemantics(byKey('my-voices-clone')),
        isSemantics(
          label: '${es.f47P4CloneTitle}. ${es.f47P4CloneEntry}',
          isButton: true,
        ),
      );
      semantics.dispose();
    });
  });

  testWidgets('en Ajustes: clonar, crear y la nube para voces', (tester) async {
    harness = await MyVoicesHarness.create();
    addTearDown(harness.dispose);
    await pumpMyVoices(
      tester,
      harness,
      Consumer(
        builder: (context, ref, _) =>
            ListView(children: voiceSettingsTiles(context, ref)),
      ),
    );
    await tester.pumpAndSettle();
    expect(byKey('settings-clone-voice'), findsOneWidget);
    expect(byKey('settings-create-voice'), findsOneWidget);
    expect(find.text(es.f47P4CloudOff), findsOneWidget);
    await tapShown(tester, byKey('settings-voice-cloud'));
    expect(byKey('voice-cloud-sheet'), findsOneWidget);
  });

  testWidgets('«Voces por idioma» nombra la propia elegida', (tester) async {
    harness = await MyVoicesHarness.create(cloudEnabled: true, cloudKey: 'k');
    addTearDown(harness.dispose);
    await harness.store.save(_cloned);
    final container = await pumpMyVoices(
      tester,
      harness,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showVoicesByLanguage(context),
          child: const Text('Por idioma'),
        ),
      ),
    );
    await container
        .read(narrationSettingsNotifierProvider.notifier)
        .selectVoice(_cloned.narrationVoice);
    await tester.tap(find.text('Por idioma'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: byKey('voices-by-language-es'),
        matching: find.text('Papá 🇦🇷'),
      ),
      findsOneWidget,
    );
  });
}
