import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/recording_check.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/clone_voice_screen.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/create_voice_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/fake_file_chooser.dart';
import '../../../../../support/my_voices_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late MyVoicesHarness harness;

  Future<void> setUpHarness({bool cloud = true}) async {
    harness = await MyVoicesHarness.create(
      cloudEnabled: cloud,
      cloudKey: cloud ? 'sk-prueba' : null,
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
          onPressed: () => showCloneVoice(context),
          child: const Text('Abrir'),
        ),
      ),
      textScale: textScale,
      themeMode: themeMode,
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  /// Llega a la muestra, con «es mi voz» y su nombre.
  Future<void> toSample(WidgetTester tester) async {
    await tapShown(tester, byKey('clone-start'));
    await tapShown(tester, byKey('clone-owner-own'));
    await tester.enterText(byKey('clone-person'), 'Ana');
    await tester.pumpAndSettle();
    await tapShown(tester, byKey('clone-confirm'));
    await tapShown(tester, byKey('clone-consent-next'));
  }

  Future<void> record(WidgetTester tester) async {
    await tapShown(tester, byKey('clone-record'));
    await tester.pump();
    await tapShown(tester, byKey('clone-stop'));
  }

  group('la presentación', () {
    testWidgets('dice qué es, cómo se usa, que se borra, y por qué no se clona '
        'en el teléfono', (tester) async {
      await setUpHarness();
      await open(tester);
      expect(find.text(es.f47P4CloneWhat), findsOneWidget);
      expect(find.text(es.f47P4CloneHow), findsOneWidget);
      expect(find.text(es.f47P4CloneDelete), findsOneWidget);
      expect(find.text(es.f47P4ClonePhoneUnavailable), findsOneWidget);
      final phone = tester.widget<ListTile>(byKey('clone-where-phone'));
      expect(phone.enabled, isFalse);
    });

    testWidgets('con la nube apagada no empieza, y ofrece prenderla', (
      tester,
    ) async {
      await setUpHarness(cloud: false);
      await open(tester);
      expect(
        tester.widget<FilledButton>(byKey('clone-start')).onPressed,
        isNull,
      );
      expect(find.text(es.f47P4CloudNeeded), findsOneWidget);
      await tapShown(tester, byKey('clone-open-cloud'));
      expect(byKey('voice-cloud-sheet'), findsOneWidget);
    });
  });

  group('el consentimiento', () {
    testWidgets('antes de grabar: de quién es, su nombre y la confirmación', (
      tester,
    ) async {
      await setUpHarness();
      await open(tester);
      await tapShown(tester, byKey('clone-start'));
      FilledButton next() =>
          tester.widget<FilledButton>(byKey('clone-consent-next'));
      expect(next().onPressed, isNull);

      await tapShown(tester, byKey('clone-owner-permission'));
      expect(next().onPressed, isNull);
      await tester.enterText(byKey('clone-person'), 'Jorge');
      await tester.pumpAndSettle();
      expect(next().onPressed, isNull);
      expect(find.text(es.f47P4ConsentOther('Jorge')), findsOneWidget);
      await tapShown(tester, byKey('clone-confirm'));
      expect(next().onPressed, isNotNull);
      // Cambiar de quién es pide confirmar de nuevo.
      await tapShown(tester, byKey('clone-owner-own'));
      expect(next().onPressed, isNull);
    });

    testWidgets('la voz de un famoso o sin permiso no se clona: lo dice y '
        'lleva a crear una voz', (tester) async {
      await setUpHarness();
      await open(tester);
      await tapShown(tester, byKey('clone-start'));
      await tapShown(tester, byKey('clone-owner-not-allowed'));
      expect(find.text(es.f47P4CloneNotAllowed), findsOneWidget);
      expect(byKey('clone-person'), findsNothing);
      expect(
        tester.widget<FilledButton>(byKey('clone-consent-next')).onPressed,
        isNull,
      );
      await tapShown(tester, byKey('clone-go-create'));
      expect(find.byType(CreateVoiceScreen), findsOneWidget);
      expect(find.byType(CloneVoiceScreen), findsNothing);
    });
  });

  group('la muestra', () {
    testWidgets('propone un texto en el idioma de la voz, graba, mide y deja '
        'seguir', (tester) async {
      await setUpHarness();
      await open(tester);
      await toSample(tester);
      expect(byKey('clone-script'), findsOneWidget);
      expect(
        tester.widget<Text>(byKey('clone-script')).data,
        startsWith('Hoy quiero contarte'),
      );
      await record(tester);
      expect(harness.recorder.recorded, hasLength(1));
      expect(harness.tools.analyzed, hasLength(1));
      expect(find.text(es.f47P4SampleGood), findsOneWidget);
      expect(find.text(es.f47P4UseSample), findsOneWidget);
      await tapShown(tester, byKey('clone-use-sample'));
      expect(byKey('clone-name'), findsOneWidget);
    });

    testWidgets('con ruido, avisa que conviene repetir pero deja seguir; sin '
        'voz suficiente, no', (tester) async {
      await setUpHarness();
      harness.tools.report = const RecordingReport(
        total: Duration(seconds: 70),
        voiced: Duration(seconds: 60),
        noiseDb: -30,
        voiceDb: -18,
        clippedRatio: 0,
      );
      await open(tester);
      await toSample(tester);
      await record(tester);
      expect(find.text(es.f47P4SampleRepeat), findsOneWidget);
      expect(byKey('recording-issue-noisy'), findsOneWidget);
      expect(find.text(es.f47P4UseAnyway), findsOneWidget);
      expect(
        tester.widget<FilledButton>(byKey('clone-use-sample')).onPressed,
        isNotNull,
      );

      harness.tools.report = const RecordingReport(
        total: Duration(seconds: 30),
        voiced: Duration(seconds: 10),
        noiseDb: -70,
        voiceDb: -18,
        clippedRatio: 0,
      );
      await record(tester);
      expect(byKey('recording-issue-tooLittleVoice'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(byKey('clone-use-sample')).onPressed,
        isNull,
      );
    });

    testWidgets('sin permiso del micrófono, lo dice y ofrece subir un audio', (
      tester,
    ) async {
      await setUpHarness();
      harness.recorder.granted = false;
      await open(tester);
      await toSample(tester);
      await tapShown(tester, byKey('clone-record'));
      expect(find.text(es.f47P4MicPermission), findsOneWidget);
      expect(harness.recorder.recorded, isEmpty);
    });

    testWidgets('subir un audio', (tester) async {
      await setUpHarness();
      harness.chooser = FakeFileChooser(
        file: CapturedFile(
          name: 'papa.m4a',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      await open(tester);
      await toSample(tester);
      await tapShown(tester, byKey('clone-upload'));
      expect(find.text(es.f47P4SampleGood), findsOneWidget);
      await tapShown(tester, byKey('clone-use-sample'));
      await tapShown(tester, byKey('clone-confirm-cloud'));
      final voice = (await harness.store.list()).single;
      expect(voice.recording!.uploaded, isTrue);
      expect(voice.recording!.file, 'grabacion.m4a');
    });

    testWidgets('un audio que no se puede leer, lo dice', (tester) async {
      await setUpHarness();
      harness
        ..chooser = FakeFileChooser(
          file: CapturedFile(name: 'x.bin', bytes: Uint8List(1)),
        )
        ..tools.failUpload = true;
      await open(tester);
      await toSample(tester);
      await tapShown(tester, byKey('clone-upload'));
      expect(find.text(es.f47P4Unreadable), findsOneWidget);
    });
  });

  group('clonar', () {
    testWidgets('dice lo que cuesta y lo que sale, y guarda la voz con el '
        'consentimiento, el nombre de la persona y la fecha', (tester) async {
      await setUpHarness();
      await open(tester);
      await toSample(tester);
      await record(tester);
      await tapShown(tester, byKey('clone-use-sample'));

      expect(
        tester.widget<Text>(byKey('clone-cost')).data,
        es.f47P4CloneCost('Starter', 6, '54'),
      );
      expect(find.text(es.f47P4CloneLeaves), findsOneWidget);
      expect(find.text(es.f47P4CreditsLeft('29.000')), findsOneWidget);
      expect(
        tester.widget<TextField>(byKey('clone-name')).controller!.text,
        'Ana',
      );
      await tester.enterText(byKey('clone-name'), 'Mi voz');
      await tapShown(tester, byKey('clone-confirm-cloud'));

      expect(harness.cloud.clones.single.name, 'Mi voz');
      final voice = (await harness.store.list()).single;
      expect(voice.name, 'Mi voz');
      expect(voice.origin, VoiceOrigin.cloned);
      expect(voice.home, MyVoiceHome.elevenLabs);
      expect(voice.locale, 'es-AR');
      expect(voice.consent!.kind, VoiceConsentKind.own);
      expect(voice.consent!.personName, 'Ana');
      expect(voice.consent!.grantedAt, DateTime.utc(2026, 10, 31, 15));
      expect(find.byType(CloneVoiceScreen), findsNothing);
      expect(find.text(es.f47P4Saved('Mi voz')), findsOneWidget);
    });

    testWidgets('si el plan no clona, no deja y lo dice', (tester) async {
      await setUpHarness();
      harness.cloud.accountInfo = const VoiceCloudAccount(
        tier: 'free',
        creditsUsed: 0,
        creditLimit: 10000,
        canClone: false,
      );
      await open(tester);
      await toSample(tester);
      await record(tester);
      await tapShown(tester, byKey('clone-use-sample'));
      expect(find.text(es.f47P4CloudCannotClone), findsOneWidget);
      expect(
        tester.widget<FilledButton>(byKey('clone-confirm-cloud')).onPressed,
        isNull,
      );
    });

    testWidgets('si ElevenLabs falla, lo dice y no guarda nada', (
      tester,
    ) async {
      await setUpHarness();
      harness.cloud.failures['cloneVoice'] = const VoiceCloudException(
        VoiceCloudFailure.invalidKey,
      );
      await open(tester);
      await toSample(tester);
      await record(tester);
      await tapShown(tester, byKey('clone-use-sample'));
      await tapShown(tester, byKey('clone-confirm-cloud'));
      expect(find.text(es.f47P4FailInvalidKey), findsOneWidget);
      expect(await harness.store.list(), isEmpty);
      expect(find.byType(CloneVoiceScreen), findsOneWidget);
    });
  });

  group('a 360 dp con la letra al doble', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('cada paso sin desbordar, en ${mode.name}', (tester) async {
        await setUpHarness();
        await open(tester, textScale: 2, themeMode: mode);
        expect(tester.takeException(), isNull);
        await toSample(tester);
        expect(tester.takeException(), isNull);
        await record(tester);
        expect(tester.takeException(), isNull);
        await tapShown(tester, byKey('clone-use-sample'));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el lector de pantalla oye los títulos y cada opción', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await setUpHarness();
      await open(tester);
      expect(find.bySemanticsLabel(es.f47P4WhereTitle), findsOneWidget);
      await tapShown(tester, byKey('clone-start'));
      expect(find.bySemanticsLabel(es.f47P4WhoseTitle), findsOneWidget);
      expect(find.bySemanticsLabel(es.f47P4OwnerNotAllowed), findsOneWidget);
      semantics.dispose();
    });
  });
}
