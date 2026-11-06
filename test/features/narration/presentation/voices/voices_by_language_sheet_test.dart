import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/voices/voices_by_language_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

const _english = NarrationVoice(name: 'en-us-x-sfg-local', locale: 'en-US');
const _daniela = NarrationVoice(
  name: 'vits-piper-es_AR-daniela-high#0',
  locale: 'es-AR',
  engine: NarrationEngine.offline,
);

void main() {
  final es = AppLocalizationsEs();

  Future<ProviderContainer> open(
    WidgetTester tester, {
    required ThemeMode themeMode,
    List<NarrationVoice> chosen = const [],
    List<NarrationVoice> device = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(360, 760)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        narrationVoicesProvider.overrideWith((ref) async => device),
      ],
    );
    addTearDown(container.dispose);
    for (final voice in chosen) {
      await container
          .read(narrationSettingsNotifierProvider.notifier)
          .selectVoice(voice);
    }
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
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showVoicesByLanguage(context),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    return container;
  }

  group('«Voces por idioma» (F47, paso 3)', () {
    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('en ${themeMode.name}, a 360 dp con la letra al doble: la '
          'de cada idioma, y volver uno a la del teléfono', (tester) async {
        final semantics = tester.ensureSemantics();
        final container = await open(
          tester,
          themeMode: themeMode,
          chosen: [_english, _daniela],
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Español'), findsOneWidget);
        expect(find.textContaining('Daniela'), findsOneWidget);
        expect(find.byTooltip(es.f47P3ByLanguageReset), findsWidgets);
        await tester.scrollUntilVisible(
          find.text('Inglés'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Inglés'), findsOneWidget);

        final reset = find.byKey(const Key('voices-by-language-reset-es'));
        await tester.scrollUntilVisible(
          reset,
          -200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(reset);
        await tester.pumpAndSettle();

        expect(
          container
              .read(narrationSettingsNotifierProvider)
              .voicesByLanguage
              .keys,
          ['en'],
        );
        expect(find.text('Español'), findsNothing);
        semantics.dispose();
      });
    }

    testWidgets('una del teléfono con código se nombra como su tarjeta de la '
        'biblioteca: con su número entre las de su acento (F46, paso 5f)', (
      tester,
    ) async {
      // En la lista, la de «sfg» es la segunda de Estados Unidos.
      const other = NarrationVoice(name: 'en-us-x-iob-local', locale: 'en-US');
      await open(
        tester,
        themeMode: ThemeMode.light,
        chosen: [_english],
        device: const [_english, other],
      );

      final tile = find.byKey(const Key('voices-by-language-en'));
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining(es.readAloudVoiceNumber(2)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining(es.readAloudVoiceNumber(1)),
        ),
        findsNothing,
      );
    });

    testWidgets('sin ninguna elegida, lo dice', (tester) async {
      await open(tester, themeMode: ThemeMode.light);
      expect(find.text(es.f47P3ByLanguageEmpty), findsOneWidget);
    });
  });
}
