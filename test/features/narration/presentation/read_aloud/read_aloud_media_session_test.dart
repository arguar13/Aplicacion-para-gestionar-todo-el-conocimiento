import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/audio/media_session.dart';
import 'package:sinapsis/core/audio/media_session_hub.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_face.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_media_session.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_overlay.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_media_session.dart';
import '../../../../support/fake_text_to_speech_service.dart';

/// El lector en voz alta en la tarjeta de lo que suena (F47, paso 2b): el
/// lector de verdad, con un motor de voz de mentira, y la sesión de medios del
/// sistema, de mentira.
void main() {
  final es = AppLocalizationsEs();

  /// Diez oraciones de diez palabras: 40 s a 1×.
  final document = ReadableDocument(
    id: 'doc',
    title: 'Un documento',
    segments: buildReadableSegments(
      [
        for (var s = 0; s < 10; s++)
          '${[for (var w = 0; w < 10; w++) 'p$s$w'].join(' ')}.',
      ].join('\n'),
      sourceKey: 'doc',
    ),
  );

  late FakeTextToSpeechService tts;
  late FakeMediaSession platform;
  late ProviderContainer container;

  /// Las caras que se dibujaron como portada, en orden.
  late List<VoiceFace> drawn;

  ReadAloudController controller() =>
      container.read(readAloudControllerProvider.notifier);
  ReadAloudState state() => container.read(readAloudControllerProvider);

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tts = FakeTextToSpeechService();
    platform = FakeMediaSession();
    drawn = [];
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(tts),
        narrationClockProvider.overrideWithValue(() => Duration.zero),
        mediaSessionPlatformProvider.overrideWithValue(platform),
        mediaSessionClockProvider.overrideWithValue(() => Duration.zero),
        voiceArtworkProvider.overrideWithValue((face) async {
          drawn.add(face);
          return Uint8List.fromList([drawn.length]);
        }),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Pantalla')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              ReadAloudOverlay(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('leer muestra la tarjeta: el título, con qué voz y a qué '
      'velocidad, y el tiempo', (tester) async {
    await pump(tester);
    expect(platform.card, isNull);

    await controller().open(document, fromSegment: 5);
    await tester.pumpAndSettle();

    final card = platform.card!;
    expect(card.title, 'Un documento');
    expect(card.subtitle, es.f47P2ReadingWith(es.f47P2PhoneVoice, '1,0×'));
    expect(card.position, const Duration(seconds: 20));
    expect(card.duration, const Duration(seconds: 40));
    expect(card.playing, isTrue);
    expect(card.hasNext, isFalse);
    expect(card.requestsAudioFocus, isTrue);
  });

  testWidgets('la portada es la cara de la voz que lee, dibujada una vez: '
      'la misma imagen mientras lea esa voz', (tester) async {
    await pump(tester);
    await controller().open(document);
    await tester.pumpAndSettle();

    final cover = platform.card!.artwork;
    expect(cover, isNotNull);
    expect(drawn, [VoiceFace.of('system', es.readAloudSystemVoice)]);

    await controller().pause();
    await tester.pumpAndSettle();
    expect(platform.card!.playing, isFalse);
    expect(identical(platform.card!.artwork, cover), isTrue);
    expect(drawn, hasLength(1));
  });

  testWidgets('en pausa lo dice, y con algo en la cola ofrece «siguiente»', (
    tester,
  ) async {
    await pump(tester);
    await controller().open(document);
    await controller().pause();
    await controller().enqueue(
      ReadableDocument(
        id: 'otro',
        title: 'Otro',
        segments: buildReadableSegments('Otro.', sourceKey: 'otro'),
      ),
    );
    await tester.pumpAndSettle();

    expect(platform.card?.playing, isFalse);
    expect(
      platform.card?.subtitle,
      es.f47P2PausedWith(es.f47P2PhoneVoice, '1,0×'),
    );
    expect(platform.card?.hasNext, isTrue);
  });

  testWidgets('lo que se toca en la tarjeta le llega al lector', (
    tester,
  ) async {
    await pump(tester);
    await controller().open(document);
    await tester.pumpAndSettle();

    platform.tap(const MediaPause());
    await tester.pumpAndSettle();
    expect(state().playing, isFalse);

    platform.tap(const MediaPlay());
    await tester.pumpAndSettle();
    expect(state().playing, isTrue);

    platform.tap(const MediaSkip(Duration(seconds: 10)));
    await tester.pumpAndSettle();
    expect(state().segmentIndex, 2);

    platform.tap(const MediaSeek(Duration(seconds: 36)));
    await tester.pumpAndSettle();
    expect(state().segmentIndex, 9);

    controller().minimize();
    platform.tap(const MediaOpen());
    await tester.pumpAndSettle();
    expect(state().panel, ReadAloudPanel.expanded);

    platform.tap(const MediaStop());
    await tester.pumpAndSettle();
    expect(state().document, isNull);
    expect(platform.card, isNull);
  });

  testWidgets('«siguiente» en la tarjeta pasa a lo de la cola', (tester) async {
    await pump(tester);
    await controller().open(document);
    await controller().enqueue(
      ReadableDocument(
        id: 'otro',
        title: 'Otro',
        segments: buildReadableSegments('Otro.', sourceKey: 'otro'),
      ),
    );
    await tester.pumpAndSettle();

    platform.tap(const MediaNext());
    await tester.pumpAndSettle();

    expect(state().document?.id, 'otro');
    expect(platform.card?.title, 'Otro');
  });

  testWidgets('una llamada pausa, al cortar sigue; desconectar los '
      'auriculares pausa', (tester) async {
    await pump(tester);
    await controller().open(document);
    await tester.pumpAndSettle();

    platform.interrupt(const MediaInterruptionBegan(resumable: true));
    await tester.pumpAndSettle();
    expect(state().playing, isFalse);

    platform.interrupt(const MediaInterruptionEnded());
    await tester.pumpAndSettle();
    expect(state().playing, isTrue);

    platform.interrupt(const MediaBecameNoisy());
    await tester.pumpAndSettle();
    expect(state().playing, isFalse);
  });

  testWidgets('al terminar, la tarjeta se va; y el reproductor queda para '
      'volver a empezar', (tester) async {
    await pump(tester);
    await controller().open(document, fromSegment: 9);
    await tester.pumpAndSettle();
    expect(platform.card, isNotNull);

    tts.completeCurrent();
    await tester.pumpAndSettle();

    expect(state().finished, isTrue);
    expect(platform.card, isNull);
    expect(find.byKey(const Key('read-aloud-player')), findsOneWidget);
  });
}
