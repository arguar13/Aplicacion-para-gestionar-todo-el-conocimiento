import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/data/voices/eleven_labs_voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/voice_cloud_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/my_voices_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late MyVoicesHarness harness;

  Finder byKey(String key) => find.byKey(Key(key));

  Future<void> open(
    WidgetTester tester, {
    bool enabled = false,
    String? key,
    double textScale = 1,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    harness = await MyVoicesHarness.create(
      cloudEnabled: enabled,
      cloudKey: key,
    );
    addTearDown(harness.dispose);
    await pumpMyVoices(
      tester,
      harness,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showVoiceCloudSheet(context),
          child: const Text('Abrir'),
        ),
      ),
      textScale: textScale,
      themeMode: themeMode,
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('apagada de entrada: dice qué sale, lo que cuesta, y nada se '
      'pide', (tester) async {
    await open(tester);
    expect(find.text(es.f47P4CloudIntro), findsOneWidget);
    expect(find.text(es.f47P4CloudLeaves), findsOneWidget);
    expect(find.text(es.f47P4CloudCosts), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(byKey('voice-cloud-switch')).value,
      isFalse,
    );
    expect(byKey('voice-cloud-key-field'), findsNothing);
    expect(harness.cloud.accountChecks, 0);
  });

  testWidgets('al prenderla se carga la clave, va al almacén seguro y se ve '
      'lo gastado', (tester) async {
    await open(tester);
    await tapShown(tester, byKey('voice-cloud-switch'));
    expect(
      harness.prefs.getBool(VoiceCloudSettingsNotifier.enabledKey),
      isTrue,
    );
    await tester.enterText(byKey('voice-cloud-key-field'), '  sk-nueva  ');
    await tapShown(tester, byKey('voice-cloud-key-save'));

    expect(harness.secure.values.values, ['sk-nueva']);
    expect(byKey('voice-cloud-key-saved'), findsOneWidget);
    // La clave nunca se muestra.
    expect(find.textContaining('sk-nueva'), findsNothing);
    expect(byKey('voice-cloud-usage'), findsOneWidget);
    expect(find.text(es.f47P4CloudPlan('starter')), findsOneWidget);
    expect(find.text(es.f47P4CloudCredits('1.000', '30.000')), findsOneWidget);
    expect(find.text(es.f47P4CloudCanClone), findsOneWidget);
    expect(find.text(es.f47P4CloudSlots(1, 10)), findsOneWidget);
  });

  testWidgets('una clave que no sirve, lo dice', (tester) async {
    await open(tester, enabled: true, key: 'sk-vieja');
    harness.cloud.failures['account'] = const VoiceCloudException(
      VoiceCloudFailure.invalidKey,
    );
    await tapShown(tester, byKey('voice-cloud-refresh'));
    expect(find.text(es.f47P4FailInvalidKey), findsOneWidget);
  });

  testWidgets('borrar la clave', (tester) async {
    await open(tester, enabled: true, key: 'sk-vieja');
    await tapShown(tester, byKey('voice-cloud-key-delete'));
    expect(harness.secure.values, isEmpty);
    expect(byKey('voice-cloud-key-field'), findsOneWidget);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('a 360 dp con la letra al doble, sin desbordar, en '
        '${mode.name}', (tester) async {
      await open(
        tester,
        enabled: true,
        key: 'sk',
        textScale: 2,
        themeMode: mode,
      );
      expect(tester.takeException(), isNull);
      expect(byKey('voice-cloud-key-change'), findsOneWidget);
    });
  }

  testWidgets('el lector de pantalla oye el título y el interruptor', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    expect(find.bySemanticsLabel(es.f47P4CloudTitle), findsOneWidget);
    expect(
      tester.getSemantics(byKey('voice-cloud-switch')),
      isSemantics(
        label: '${es.f47P4CloudSwitch}\n${es.f47P4CloudOff}',
        hasToggledState: true,
        isToggled: false,
      ),
    );
    semantics.dispose();
  });

  group('apagada, nada sale aunque haya clave', () {
    Future<(ProviderContainer, _Counting)> container({
      required bool enabled,
    }) async {
      SharedPreferences.setMockInitialValues({
        VoiceCloudSettingsNotifier.enabledKey: enabled,
      });
      final storage = FakeSecureStorage()
        ..values['voice_cloud_elevenlabs_key_v1'] = 'sk-guardada';
      final adapter = _Counting();
      final created = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          elevenLabsKeyStoreProvider.overrideWithValue(
            ElevenLabsKeyStore(storage: storage),
          ),
          voiceCloudDioProvider.overrideWithValue(
            Dio()..httpClientAdapter = adapter,
          ),
        ],
      );
      addTearDown(created.dispose);
      return (created, adapter);
    }

    test('la clave guardada no se manda con la nube apagada', () async {
      final (off, adapter) = await container(enabled: false);
      await expectLater(
        off.read(voiceCloudProvider).account(),
        throwsA(
          isA<VoiceCloudException>().having(
            (e) => e.failure,
            'failure',
            VoiceCloudFailure.noKey,
          ),
        ),
      );
      expect(adapter.requests, 0);
    });

    test('prendida, se manda', () async {
      final (on, adapter) = await container(enabled: true);
      await on.read(voiceCloudProvider).account();
      expect(adapter.requests, 1);
      expect(adapter.lastKey, 'sk-guardada');
    });

    test('se puede usar solo prendida y con clave', () {
      expect(const VoiceCloudSettings(hasKey: true).ready, isFalse);
      expect(const VoiceCloudSettings(enabled: true).ready, isFalse);
      expect(
        const VoiceCloudSettings(enabled: true, hasKey: true).ready,
        isTrue,
      );
    });
  });
}

/// Cuenta los pedidos y contesta un plan; nunca sale a internet.
class _Counting implements HttpClientAdapter {
  int requests = 0;
  String? lastKey;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    lastKey = options.headers['xi-api-key'] as String?;
    return ResponseBody.fromString(
      '{"tier": "starter", "character_count": 0, "character_limit": 1}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
