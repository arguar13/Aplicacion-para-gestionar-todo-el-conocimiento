import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/cloud_reading_gate.dart';
import 'package:sinapsis/features/narration/presentation/voices/speech_audio_approval.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/my_voices_harness.dart';

MyVoice _cloud(String id, String name) => MyVoice(
  id: id,
  name: name,
  origin: VoiceOrigin.cloned,
  home: MyVoiceHome.elevenLabs,
  locale: 'es-AR',
  createdAt: DateTime.utc(2026, 10, 31),
  cloudVoiceId: 'eleven-$id',
  consent: VoiceConsent(
    kind: VoiceConsentKind.own,
    personName: name,
    grantedAt: DateTime.utc(2026, 10, 31),
  ),
);

final _papa = _cloud('v1', 'Papá');
final _yo = _cloud('v2', 'Yo');

String _id(MyVoice voice) => voice.narrationVoice.name;

SpeechAudioCost _costOf(Map<String, int> byVoice) => SpeechAudioCost(
  amount: byVoice.values.fold(0, (a, b) => a + b).toDouble(),
  currency: 'credits',
  characters: byVoice.values.fold(0, (a, b) => a + b),
  charactersByVoice: byVoice,
);

/// F47, paso 4, con el paso 6b: antes de generar un audio con voces propias
/// de la nube, cada una se aprueba con la puerta de la nube —su nombre, sus
/// caracteres, lo que queda del mes—. Nunca sale a ElevenLabs.
void main() {
  final es = AppLocalizationsEs();

  Future<BuildContext> contextIn(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('cada voz propia que cobra se aprueba con la puerta, con lo que '
      'lee ella; un «no» basta y no se pregunta por las demás', (tester) async {
    final context = await contextIn(tester);
    final asked = <(String, int)>[];
    var answers = [true, true];
    final gate = CloudReadingGate()
      ..attach((voice, characters) async {
        asked.add((voice.name, characters));
        return answers[asked.length - 1];
      });
    final cost = _costOf({_id(_papa): 120, _id(_yo): 80});

    expect(
      await approveSpeechAudioCost(
        context,
        cost,
        gate: gate,
        mine: () async => [_papa, _yo],
      ),
      isTrue,
    );
    expect(asked, [(_id(_papa), 120), (_id(_yo), 80)]);
    // Sin el aviso genérico: el de la nube ya dice el costo.
    expect(find.byKey(const Key('speech-audio-cost')), findsNothing);

    asked.clear();
    answers = [false, true];
    expect(
      await approveSpeechAudioCost(
        context,
        cost,
        gate: gate,
        mine: () async => [_papa, _yo],
      ),
      isFalse,
    );
    expect(asked, [(_id(_papa), 120)]);
  });

  testWidgets('sin nadie que pregunte, no se genera', (tester) async {
    final context = await contextIn(tester);
    expect(
      await approveSpeechAudioCost(
        context,
        _costOf({_id(_papa): 10}),
        gate: CloudReadingGate(),
        mine: () async => [_papa],
      ),
      isFalse,
    );
  });

  testWidgets('una que ya no está se pregunta por su id, sin dejar de '
      'preguntar', (tester) async {
    final context = await contextIn(tester);
    NarrationVoice? asked;
    final gate = CloudReadingGate()
      ..attach((voice, _) async {
        asked = voice;
        return true;
      });
    expect(
      await approveSpeechAudioCost(
        context,
        _costOf({'mia:borrada': 5}),
        gate: gate,
        mine: () async => const [],
      ),
      isTrue,
    );
    expect(asked?.name, 'mia:borrada');
    expect(asked?.engine, NarrationEngine.cloud);
  });

  testWidgets('otra voz que cobra pasa por el aviso del costo, y sin aceptar '
      'no se llega a la puerta', (tester) async {
    final context = await contextIn(tester);
    var gateAsked = false;
    final gate = CloudReadingGate()..attach((_, _) async => gateAsked = true);
    bool? answer;
    unawaited(
      approveSpeechAudioCost(
        context,
        _costOf({'otra:x': 10, _id(_papa): 20}),
        gate: gate,
        mine: () async => [_papa],
      ).then((value) => answer = value),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('speech-audio-cost')), findsOneWidget);
    await tester.tap(find.byKey(const Key('speech-audio-cost-cancel')));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
    expect(gateAsked, isFalse);
  });

  testWidgets('lo de fábrica (speechAudioApprovalProvider) muestra el aviso '
      'de la nube con el nombre de la voz y sus caracteres', (tester) async {
    final harness = await MyVoicesHarness.create(
      cloudEnabled: true,
      cloudKey: 'k',
    );
    addTearDown(harness.dispose);
    await harness.store.save(_papa);
    final navigator = GlobalKey<NavigatorState>();
    final container = ProviderContainer(overrides: harness.overrides);
    addTearDown(container.dispose);
    late BuildContext context;
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
          builder: (_, child) =>
              CloudReadingGateHost(navigatorKey: navigator, child: child!),
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    bool? answer;
    unawaited(
      container
          .read(speechAudioApprovalProvider)(
            context,
            _costOf({_id(_papa): 1234}),
          )
          .then((value) => answer = value),
    );
    await tester.pumpAndSettle();
    expect(find.text(es.f47P4ReadCloudTitle('Papá')), findsOneWidget);
    expect(find.text(es.f47P4ReadCloudCost('1.234', '1.234')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cloud-reading-approve')));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });
}
