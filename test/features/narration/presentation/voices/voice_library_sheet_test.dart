import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/library/presentation/widgets/list_controls.dart';
import 'package:sinapsis/features/narration/data/voices/offline_voice_files.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_card.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_library_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_offline_speech.dart';
import '../../../../support/fake_text_to_speech_service.dart';
import '../../../../support/on_device_harness.dart';

const _argentina = NarrationVoice(name: 'es-ar-x-local', locale: 'es-AR');
const _monica = NarrationVoice(name: 'Mónica', locale: 'es-ES');
const _unitedStates = NarrationVoice(
  name: 'en-us-x-sfg-local',
  locale: 'en-US',
);

const _daniela = 'vits-piper-es_AR-daniela-high#0';

void main() {
  final es = AppLocalizationsEs();
  late SharedPreferences prefs;
  late FakeTextToSpeechService tts;
  late FakeSpeechClipPlayer samples;
  late FakeModelTransfer transfer;
  late Directory root;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tts = FakeTextToSpeechService(
      voices: const [_unitedStates, _argentina, _monica],
    );
    samples = FakeSpeechClipPlayer();
    transfer = FakeModelTransfer();
    root = Directory.systemTemp.createTempSync('biblioteca-');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  /// La biblioteca abierta sobre una pantalla, a 360 dp y con la letra al
  /// doble si se pide. [installed]: los paquetes que están en el teléfono.
  Future<void> open(
    WidgetTester tester, {
    String? reading,
    Set<String> installed = const {},
    double textScale = 1,
    ThemeMode themeMode = ThemeMode.light,
    bool offline = true,
  }) async {
    tester.view
      ..physicalSize = const Size(360, 760)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final files = OfflineVoiceFiles(
      transfer: transfer,
      rootDirectory: () async => root,
    );
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(tts),
        offlineVoicesAvailableProvider.overrideWithValue(offline),
        offlineVoiceFilesProvider.overrideWithValue(offline ? files : null),
        offlineSpeechSynthesizerProvider.overrideWithValue(null),
        installedVoicePackagesProvider.overrideWith(
          (ref) => Stream.value(installed),
        ),
        voiceSampleClipPlayerProvider.overrideWithValue(samples),
        readingLanguageProvider.overrideWith((ref) => reading),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
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
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showVoiceLibrary(context),
                  child: const Text('Voces'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tapVisible(tester, find.text('Voces'));
    await tester.pumpAndSettle();
  }

  Finder card(String id) => find.byKey(Key('voice-card-$id'));

  Future<void> scrollTo(WidgetTester tester, Finder target) =>
      tester.scrollUntilVisible(
        target,
        300,
        scrollable: find.byType(Scrollable).last,
      );

  group('la biblioteca de voces (F47, paso 3)', () {
    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('a 360 dp con la letra al doble, en '
          '${themeMode.name}: las pestañas, la voz que lee y las tarjetas, '
          'sin desbordar', (tester) async {
        final semantics = tester.ensureSemantics();
        await open(tester, reading: 'es', textScale: 2, themeMode: themeMode);

        expect(tester.takeException(), isNull);
        expect(find.text(es.f47P3LibraryTitle), findsOneWidget);
        expect(find.text(es.f47P3TabAll), findsOneWidget);
        expect(find.text(es.f47P3TabFavorites), findsOneWidget);
        expect(find.text(es.f47P3TabMine), findsOneWidget);
        expect(find.text(es.f47P3NowReadingSystem), findsOneWidget);
        expect(find.text(es.f47P3Recommended), findsOneWidget);
        // Cada tarjeta, un solo nodo con su nombre, sus rasgos y de dónde es.
        final claudeCard = find.byKey(
          const Key('voice-recommended-vits-piper-es_MX-claude-high#0'),
        );
        await tester.scrollUntilVisible(
          claudeCard,
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        final claude = find.descendant(
          of: claudeCard,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label?.startsWith('Voz Claude') ?? false),
          ),
        );
        expect(claude, findsOneWidget);
        expect(
          tester.getSemantics(claude).label,
          allOf(
            contains('ES · México · Calidad alta'),
            contains(es.f47P3OriginOffline),
          ),
        );
        semantics.dispose();
      });
    }

    testWidgets('«Te puede interesar»: las del idioma de lo que se lee, con '
        'buena calidad, y si no hay ninguna bajada, lo dice', (tester) async {
      await open(tester, reading: 'es');

      expect(
        find.byKey(const Key('voice-library-missing-language')),
        findsOneWidget,
      );
      // Las tres, en orden: las de calidad alta primero.
      var above = double.negativeInfinity;
      for (final id in [
        'vits-piper-es_MX-claude-high#0',
        _daniela,
        'vits-piper-es_MX-ald-medium#0',
      ]) {
        final recommended = find.byKey(Key('voice-recommended-$id'));
        await tester.scrollUntilVisible(
          recommended,
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        final top =
            tester.getTopLeft(recommended).dy +
            (tester
                .state<ScrollableState>(find.byType(Scrollable).last)
                .position
                .pixels);
        expect(top, greaterThan(above), reason: id);
        above = top;
      }
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'voice-recommended-vits-piper-es_ES',
              ),
        ),
        findsNothing,
      );
    });

    testWidgets('con una voz del idioma bajada, no dice que falta, y sube '
        'primero', (tester) async {
      await open(
        tester,
        reading: 'es',
        installed: {'vits-piper-es_AR-daniela-high'},
      );

      expect(
        find.byKey(const Key('voice-library-missing-language')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('voice-recommended-$_daniela')),
        findsOneWidget,
      );
    });

    testWidgets('sin idioma conocido no recomienda', (tester) async {
      await open(tester);
      expect(find.text(es.f47P3Recommended), findsNothing);
    });

    testWidgets('Mías, vacía y lista para las clonadas y las creadas', (
      tester,
    ) async {
      await open(tester, textScale: 2);
      await tapVisible(tester, find.text(es.f47P3TabMine));
      await tester.pumpAndSettle();

      expect(find.text(es.f47P3MineEmpty), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una favorita se guarda y aparece en Favoritas', (
      tester,
    ) async {
      await open(tester, reading: 'es');
      await tapVisible(tester, find.text(es.f47P3TabFavorites));
      await tester.pumpAndSettle();
      expect(find.text(es.f47P3FavoritesEmpty), findsOneWidget);

      await tapVisible(tester, find.text(es.f47P3TabAll));
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find
            .descendant(
              of: find.byKey(const Key('voice-recommended-$_daniela')),
              matching: find.byKey(const Key('voice-favorite-$_daniela')),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(prefs.getStringList(VoiceFavoritesNotifier.storageKey), [
        _daniela,
      ]);
      await tapVisible(tester, find.text(es.f47P3TabFavorites));
      await tester.pumpAndSettle();
      expect(card(_daniela), findsOneWidget);
    });

    testWidgets('tocar una voz sin bajar no baja nada; «Bajar» la baja, y '
        'solo esa', (tester) async {
      await open(tester, reading: 'es');
      final recommended = find.byKey(const Key('voice-recommended-$_daniela'));

      await tapVisible(
        tester,
        find.descendant(of: recommended, matching: find.text('Daniela 🇦🇷')),
      );
      await tester.pumpAndSettle();
      expect(transfer.urls, isEmpty);
      expect(container.read(readAloudControllerProvider).voice, isNull);

      await tapVisible(
        tester,
        find.descendant(
          of: recommended,
          matching: find.byKey(const Key('voice-download-$_daniela')),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(transfer.urls, [OfflineVoiceCatalog.byId(_daniela)!.package.url]);
      expect(
        find.descendant(
          of: recommended,
          matching: find.text(es.f47P3Downloading(0)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('elegir una voz que ya puede leer la usa para leer', (
      tester,
    ) async {
      await open(
        tester,
        reading: 'es',
        installed: {'vits-piper-es_AR-daniela-high'},
      );
      await tapVisible(
        tester,
        find.descendant(
          of: find.byKey(const Key('voice-recommended-$_daniela')),
          matching: find.text('Daniela 🇦🇷'),
        ),
      );
      await tester.pumpAndSettle();

      final chosen = container.read(readAloudControllerProvider).voice;
      expect(chosen?.name, _daniela);
      expect(chosen?.engine, NarrationEngine.offline);
      expect(find.text(es.f47P3NowReading('Daniela')), findsOneWidget);
    });

    testWidgets('una voz del teléfono se elige, y la del sistema vuelve a la '
        'del teléfono', (tester) async {
      await open(tester, reading: 'es');
      final monica = card(deviceVoiceId(_monica));
      await scrollTo(tester, monica);
      await tapVisible(
        tester,
        find.descendant(of: monica, matching: find.textContaining('Mónica')),
      );
      await tester.pumpAndSettle();
      expect(container.read(readAloudControllerProvider).voice, _monica);

      final system = find.byKey(const Key('read-aloud-system-voice'));
      await tester.scrollUntilVisible(
        system,
        -300,
        scrollable: find.byType(Scrollable).last,
      );
      await tapVisible(tester, system);
      await tester.pumpAndSettle();
      expect(container.read(readAloudControllerProvider).voice, isNull);
    });

    testWidgets('la muestra de una voz del teléfono la dice ella, en su '
        'idioma; la de una sin bajar suena la publicada', (tester) async {
      await open(tester, reading: 'es');

      await tapVisible(
        tester,
        find.descendant(
          of: find.byKey(const Key('voice-recommended-$_daniela')),
          matching: find.byKey(const Key('voice-sample-$_daniela')),
        ),
      );
      await tester.pump();
      expect(samples.played, [
        UrlSpeechClip(OfflineVoiceCatalog.byId(_daniela)!.sampleUrl!),
      ]);
      samples.finish();
      await tester.pumpAndSettle();

      final english = card(deviceVoiceId(_unitedStates));
      await scrollTo(tester, english);
      await tapVisible(
        tester,
        find.descendant(
          of: english,
          matching: find.byKey(
            Key('voice-sample-${deviceVoiceId(_unitedStates)}'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tts.lastVoice, _unitedStates);
      expect(tts.spoken.last, startsWith('Hello.'));
    });

    testWidgets('una de Kokoro sin bajar no ofrece muestra: las publicadas no '
        'están en su idioma', (tester) async {
      await open(tester, reading: 'es');
      const dora = 'kokoro-int8-multi-lang-v1_0#28';
      await scrollTo(tester, card(dora));
      expect(
        find.descendant(
          of: card(dora),
          matching: find.byKey(const Key('voice-sample-$dora')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: card(dora),
          matching: find.textContaining('Kokoro'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('donde no hay voces sin conexión, solo las del teléfono', (
      tester,
    ) async {
      await open(tester, reading: 'es', offline: false);
      expect(find.byKey(const Key('voice-card-$_daniela')), findsNothing);
      expect(find.text(es.f47P3Recommended), findsNothing);
      expect(card(deviceVoiceId(_argentina)), findsOneWidget);
    });
  });

  group('una voz por idioma (F47, paso 3, decisión L)', () {
    testWidgets('elegir una de otro idioma la deja para el suyo, lo avisa y '
        'no cambia la de lo que se lee', (tester) async {
      await open(tester, reading: 'es');
      final english = card(deviceVoiceId(_unitedStates));
      await scrollTo(tester, english);
      await tapVisible(
        tester,
        find.descendant(of: english, matching: find.textContaining('Voz 1')),
      );
      await tester.pumpAndSettle();

      final settings = container.read(narrationSettingsNotifierProvider);
      expect(settings.voicesByLanguage['en'], _unitedStates);
      expect(
        find.text(es.f47P3ChosenForLanguage('Voz 1', 'inglés')),
        findsOneWidget,
      );
      // Marcada como la elegida de su idioma.
      expect(
        tester
            .widget<VoiceCard>(
              find
                  .ancestor(of: english, matching: find.byType(VoiceCard))
                  .first,
            )
            .selected,
        isTrue,
      );
    });

    testWidgets('la del idioma que se lee, marcada; y sin elegida, la del '
        'sistema', (tester) async {
      await open(tester, reading: 'es');
      final system = find.byKey(const Key('read-aloud-system-voice'));
      await scrollTo(tester, system);
      expect(tester.widget<ListTile>(system).selected, isTrue);

      final argentina = card(deviceVoiceId(_argentina));
      await scrollTo(tester, argentina);
      await tapVisible(
        tester,
        find.descendant(of: argentina, matching: find.textContaining('Voz 1')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(es.f47P3ChosenForLanguage('Voz 1', 'español')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        system,
        -300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.widget<ListTile>(system).selected, isFalse);
    });
  });

  group('Filtrar (F47, paso 3)', () {
    testWidgets('el pie cuenta las voces con lo elegido, y lo cierra con '
        'la lista filtrada', (tester) async {
      await open(tester, reading: 'es', textScale: 2);
      final all = container.read(voiceLibraryProvider).requireValue.length;

      await tapVisible(tester, find.byKey(const Key('voice-library-filter')));
      await tester.pumpAndSettle();
      expect(find.text(es.f47P3ShowAllVoices(all)), findsOneWidget);
      // Sin voces creadas, ni timbre ni edad: lo dice.
      expect(find.text(es.f47P3FilterTimbre.toUpperCase()), findsNothing);
      await scrollToChip(tester, 'voice-filter-pt');

      await tapVisible(tester, find.byKey(const Key('voice-filter-pt')));
      await tester.pumpAndSettle();
      // Portugués: cuatro de Piper y tres de Kokoro.
      expect(find.text(es.f47P3ShowVoices(7)), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tapVisible(tester, find.byKey(ListFiltersSheet.showResultsKey));
      await tester.pumpAndSettle();

      final shown = tester
          .widgetList(
            find.byWidgetPredicate(
              (widget) => '${widget.key}'.startsWith("[<'voice-card-"),
            ),
          )
          .length;
      expect(shown, greaterThan(0));
      expect(find.text(es.f47P3Recommended), findsNothing);
      expect(find.byKey(const Key('read-aloud-system-voice')), findsNothing);
      expect(card(_daniela), findsNothing);
    });

    testWidgets('con nada que pase, «Ninguna voz», apagado', (tester) async {
      await open(tester);
      await tapVisible(tester, find.text(es.f47P3TabFavorites));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('voice-library-filter')));
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.byKey(Key('voice-filter-${VoiceGender.female}')),
      );
      await tester.pumpAndSettle();

      expect(find.text(es.f47P3NoVoicesMatch), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(ListFiltersSheet.showResultsKey),
      );
      expect(button.onPressed, isNull);
    });
  });
}

/// Trae [target] a la vista —la hoja se desplaza— y lo toca.
Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
}

/// Baja el panel de filtros hasta el chip [key].
Future<void> scrollToChip(WidgetTester tester, String key) =>
    tester.scrollUntilVisible(
      find.byKey(Key(key)),
      100,
      scrollable: find.byType(Scrollable).last,
    );
