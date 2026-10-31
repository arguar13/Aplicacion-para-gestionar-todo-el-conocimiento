import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_samples.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/create_voice_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/my_voices_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late MyVoicesHarness harness;

  Future<void> setUpHarness({bool cloud = false, bool kokoro = true}) async {
    harness = await MyVoicesHarness.create(
      cloudEnabled: cloud,
      cloudKey: cloud ? 'sk-prueba' : null,
      kokoro: kokoro,
    );
    addTearDown(harness.dispose);
  }

  Finder byKey(String key) => find.byKey(Key(key));

  Future<void> open(
    WidgetTester tester, {
    double textScale = 1,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    await pumpMyVoices(
      tester,
      harness,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showCreateVoice(context),
          child: const Text('Abrir'),
        ),
      ),
      textScale: textScale,
      themeMode: themeMode,
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> describe(WidgetTester tester, String text) async {
    await tester.enterText(byKey('create-description'), text);
    await tester.pumpAndSettle();
  }

  group('la presentación', () {
    testWidgets('dice qué es, cómo se usa y que se borra; de entrada, en el '
        'teléfono y gratis', (tester) async {
      await setUpHarness();
      await open(tester);
      expect(find.text(es.f47P4CreateWhat), findsOneWidget);
      expect(find.text(es.f47P4CreateHow), findsOneWidget);
      expect(find.text(es.f47P4CreateDelete), findsOneWidget);
      expect(find.text(es.f47P4CreatePhoneHint), findsOneWidget);
      final cloud = tester.widget<RadioListTile<Object>>(
        byKey('create-where-cloud'),
      );
      expect(cloud.enabled, isFalse);
    });

    testWidgets('sin Kokoro, no empieza y ofrece bajarlo, solo si se toca', (
      tester,
    ) async {
      await setUpHarness(kokoro: false);
      await open(tester);
      expect(
        tester.widget<FilledButton>(byKey('create-start')).onPressed,
        isNull,
      );
      expect(byKey('create-download-kokoro'), findsOneWidget);
    });
  });

  group('en el teléfono', () {
    testWidgets('la descripción pone los controles y dice qué entendió', (
      tester,
    ) async {
      await setUpHarness();
      await open(tester);
      await tapShown(tester, byKey('create-start'));
      await describe(tester, 'Hombre joven, rioplatense, cálido y entusiasta');
      await tapShown(tester, byKey('create-interpret'));

      expect(byKey('create-understood'), findsOneWidget);
      ChoiceChip chip(String key) => tester.widget<ChoiceChip>(byKey(key));
      expect(chip('create-gender-male').selected, isTrue);
      expect(chip('create-age-young').selected, isTrue);
      expect(chip('create-style-energetic').selected, isTrue);
      expect(chip('my-voice-locale-es').selected, isTrue);
      // El acento rioplatense no está en el teléfono: lo dice.
      expect(byKey('create-accent-phone'), findsOneWidget);
    });

    testWidgets('si la descripción nombra a alguien, lo dice y no sigue', (
      tester,
    ) async {
      await setUpHarness();
      await open(tester);
      await tapShown(tester, byKey('create-start'));
      await describe(tester, 'Enérgico, como Messi');
      expect(byKey('create-real-person'), findsOneWidget);
      expect(find.text(es.f47P4RealPerson('Messi')), findsOneWidget);
      expect(
        tester.widget<FilledButton>(byKey('create-design-next')).onPressed,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(byKey('create-listen')).onPressed,
        isNull,
      );
      await describe(tester, 'Enérgico, como un relator de fútbol');
      expect(byKey('create-real-person'), findsNothing);
      expect(
        tester.widget<FilledButton>(byKey('create-design-next')).onPressed,
        isNotNull,
      );
    });

    testWidgets('se escucha la mezcla, se cambia la variante, y se guarda '
        'con su nombre, su cara y sus rasgos', (tester) async {
      await setUpHarness();
      await open(tester);
      await tapShown(tester, byKey('create-start'));
      await tapShown(tester, byKey('create-gender-female'));
      await tapShown(tester, byKey('create-style-calm'));
      final mix = tester.widget<Text>(byKey('create-mix')).data;
      expect(mix, contains('Dora'));

      await tapShown(tester, byKey('create-listen'));
      final request = harness.synthesizer.requests.single;
      expect(request.text, voiceSampleText('es'));
      expect(request.speakerId, 0);
      final played = harness.clips.played.single as FileSpeechClip;
      expect(played.path, request.outputPath);
      harness.clips.finish();
      await tester.pumpAndSettle();

      await tapShown(tester, byKey('create-variant'));
      expect(tester.widget<Text>(byKey('create-mix')).data, isNot(mix));

      await tapShown(tester, byKey('create-design-next'));
      await tester.enterText(byKey('create-name'), 'Serena');
      await tapShown(tester, byKey('my-voice-next-face'));
      await tapShown(tester, byKey('create-save'));

      final voice = (await harness.store.list()).single;
      expect(voice.name, 'Serena');
      expect(voice.home, MyVoiceHome.phone);
      expect(voice.origin, VoiceOrigin.created);
      expect(voice.gender, VoiceGender.female);
      expect(voice.styles, {VoiceStyle.calm});
      expect(voice.slot, 0);
      expect(voice.faceSeed, 1);
      expect(
        voice.blend,
        proposeBlend(
          const VoiceDesign(
            locale: 'es',
            gender: VoiceGender.female,
            style: VoiceStyle.calm,
            variant: 1,
          ),
        ),
      );
      expect(find.byType(CreateVoiceScreen), findsNothing);
      expect(find.text(es.f47P4Saved('Serena')), findsOneWidget);
    });
  });

  group('en la nube', () {
    testWidgets('antes de generar dice el costo y lo que sale; trae tres '
        'propuestas, se oyen, se elige una y se guarda', (tester) async {
      await setUpHarness(cloud: true);
      await open(tester);
      await tapShown(tester, byKey('create-where-cloud'));
      await tapShown(tester, byKey('create-start'));
      await describe(tester, 'mujer serena, con voz clara');
      expect(
        tester.widget<FilledButton>(byKey('create-design-next')).onPressed,
        isNull,
      );

      await tapShown(tester, byKey('create-design-cloud'));
      expect(byKey('create-cloud-cost'), findsOneWidget);
      // Cancelar no manda nada.
      await tapShown(tester, find.text(es.f47P4Cancel));
      expect(harness.cloud.designs, isEmpty);

      await tapShown(tester, byKey('create-design-cloud'));
      await tapShown(tester, byKey('create-cloud-approve'));
      final design = harness.cloud.designs.single;
      expect(design.description, 'mujer serena, con voz clara');
      expect(design.text.length, greaterThanOrEqualTo(100));
      expect(byKey('create-proposal-2'), findsOneWidget);

      await tapShown(tester, byKey('create-proposal-play-1'));
      expect(harness.clips.played, hasLength(1));
      harness.clips.finish();
      await tester.pumpAndSettle();

      await tapShown(tester, byKey('create-design-next'));
      await tester.enterText(byKey('create-name'), 'Clara');
      await tapShown(tester, byKey('create-save'));

      expect(harness.cloud.saved.single.generatedVoiceId, 'propuesta-1');
      final voice = (await harness.store.list()).single;
      expect(voice.home, MyVoiceHome.elevenLabs);
      expect(voice.cloudVoiceId, startsWith('diseñada'));
      expect(voice.sampleFile, 'muestra.mp3');
    });
  });

  group('a 360 dp con la letra al doble', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('cada paso sin desbordar, en ${mode.name}', (tester) async {
        await setUpHarness(cloud: true);
        await open(tester, textScale: 2, themeMode: mode);
        expect(tester.takeException(), isNull);
        await tapShown(tester, byKey('create-start'));
        await describe(tester, 'como Messi');
        expect(tester.takeException(), isNull);
        await describe(tester, 'mujer serena');
        await tapShown(tester, byKey('create-design-next'));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el lector de pantalla oye los títulos de cada control', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await setUpHarness();
      await open(tester);
      await tapShown(tester, byKey('create-start'));
      for (final title in [
        es.f47P4LanguageTitle,
        es.f47P3FilterGender,
        es.f47P3FilterAge,
        es.f47P3FilterTimbre,
        es.f47P3FilterStyle,
        es.f47P4MixTitle,
      ]) {
        expect(find.bySemanticsLabel(title), findsOneWidget, reason: title);
      }
      semantics.dispose();
    });
  });
}
