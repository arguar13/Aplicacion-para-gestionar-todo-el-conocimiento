import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/audio/media_session_hub.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/narration/data/voices/offline_voice_files.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_face.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_speed_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_face_view.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_library_sheet.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance_sheet.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_media_session.dart';
import '../../../../support/library_harness.dart';
import '../../../../support/on_device_harness.dart';

/// Ajustes › Voz y lectura entera (F47, paso 7b): una sola sección, en orden,
/// con la voz de ahora, las voces propias, la velocidad con que empieza a
/// leer, la Lectura enfocada y la letra con el resaltado —la Apariencia del
/// marco, no una copia—, a 360 dp con la letra al doble, en claro y en
/// oscuro, y con el lector de pantalla.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late Directory root;

  /// La voz de Daniela (Piper, Argentina) y su paquete.
  final daniela = OfflineVoiceCatalog.voices.firstWhere(
    (voice) => voice.name == 'Daniela',
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('voz-y-lectura-');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  /// [offline]: si el dispositivo tiene voces sin conexión (en Android), con
  /// los paquetes de [installed] abiertos en el disco de la prueba.
  Future<void> setUpWith({
    bool offline = false,
    List<OfflineVoicePackage> installed = const [],
  }) async {
    for (final package in installed) {
      final folder = Directory(
        p.join(root.path, 'modelos', 'voces', package.id),
      )..createSync(recursive: true);
      File(
        p.join(folder.path, 'modelo.onnx'),
      ).writeAsBytesSync(List.filled(3 * 1024 * 1024, 7));
      File(p.join(folder.path, '.voz.json')).writeAsStringSync('{}');
    }
    harness = await LibraryHarness.create(
      extraOverrides: [
        mediaSessionPlatformProvider.overrideWithValue(FakeMediaSession()),
        offlineVoicesAvailableProvider.overrideWithValue(offline),
        offlineVoiceFilesProvider.overrideWithValue(
          offline
              ? OfflineVoiceFiles(
                  transfer: FakeModelTransfer(),
                  rootDirectory: () async => root,
                )
              : null,
        ),
        offlineSpeechSynthesizerProvider.overrideWithValue(null),
      ],
    );
  }

  /// Lo que ocupan, juntos, los paquetes de [installed] en el disco.
  int bytesOf(List<OfflineVoicePackage> installed) => [
    for (final package in installed)
      for (final entry in Directory(
        p.join(root.path, 'modelos', 'voces', package.id),
      ).listSync(recursive: true))
        if (entry is File) entry.lengthSync(),
  ].fold(0, (sum, bytes) => sum + bytes);

  /// Ajustes a 360 dp con la letra al doble, en el tema [brightness].
  Future<void> pumpSettings(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double textScale = 2,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          theme: brightness == Brightness.light
              ? AppTheme.lightTheme
              : AppTheme.darkTheme,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: app!,
          ),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Ajustes entero en una ventana alta: una lista perezosa no arma lo que
  /// está lejos.
  Future<void> pumpWholeSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 20000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const SettingsScreen()));
    await tester.pumpAndSettle();
  }

  Finder byKey(String key) => find.byKey(Key(key));

  Finder settingsList() => find
      .descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Que [finder], llevado a la vista, se vea entero en la lista, sin
  /// cortarse.
  Future<void> expectWhole(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      400,
      scrollable: settingsList(),
      maxScrolls: 300,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final list = tester.getRect(settingsList());
    final rect = tester.getRect(finder);
    expect(list.contains(rect.topLeft), isTrue, reason: '$rect en $list');
    expect(
      list.contains(rect.bottomRight - const Offset(0.01, 0.01)),
      isTrue,
      reason: '$rect en $list',
    );
  }

  Future<void> tapShown(WidgetTester tester, Finder finder) async {
    await expectWhole(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Las filas de «Voz y lectura», en el orden en que van.
  const rows = [
    'settings-voice-library',
    'settings-voices-by-language',
    'settings-downloaded-voices',
    'settings-clone-voice',
    'settings-create-voice',
    'settings-voice-cloud',
    'settings-reading-speed',
    'settings-focused-reading',
    'settings-reading-appearance',
  ];

  for (final brightness in Brightness.values) {
    testWidgets('en ${brightness.name}: «Voz y lectura» entera, cada fila '
        'a la vista sin desbordar', (tester) async {
      await setUpWith(offline: true, installed: [daniela.package]);
      await pumpSettings(tester, brightness: brightness);

      await expectWhole(tester, find.text(es.f47P3SettingsSection));
      for (final row in rows) {
        await expectWhole(tester, byKey(row));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('una sola sección, en orden, sin filas repetidas en otra '
      'parte de Ajustes', (tester) async {
    await setUpWith(offline: true);
    await pumpWholeSettings(tester);

    final header = tester.getTopLeft(find.text(es.f47P3SettingsSection)).dy;
    final next = tester.getTopLeft(find.text(es.settingsCitationsSection)).dy;
    var previous = header;
    for (final row in rows) {
      expect(byKey(row), findsOneWidget, reason: row);
      final top = tester.getTopLeft(byKey(row)).dy;
      expect(top, greaterThan(previous), reason: '$row va después');
      expect(top, lessThan(next), reason: '$row va en Voz y lectura');
      previous = top;
    }
    for (final text in [
      es.f47P3LibraryTitle,
      es.f47P3SettingsByLanguage,
      es.f47P3SettingsDownloaded,
      es.f47P4CloneTitle,
      es.f47P4CreateTitle,
      es.f47P4CloudTitle,
      es.f47P7bSpeedTile,
      es.f47P2FocusedReading,
      es.f47P7bAppearanceTile,
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('«Mostrar el título en la pantalla de bloqueo» sigue en '
      'Privacidad, fuera de Voz y lectura', (tester) async {
    await setUpWith();
    await pumpWholeSettings(tester);

    final lockScreen = tester
        .getTopLeft(byKey('settings-lock-screen-title'))
        .dy;
    expect(
      lockScreen,
      greaterThan(tester.getTopLeft(find.text(es.f47P7bisPrivacySection)).dy),
    );
    expect(
      lockScreen,
      greaterThan(tester.getTopLeft(find.text(es.settingsCitationsSection)).dy),
    );
  });

  group('la biblioteca, con la voz de ahora', () {
    testWidgets('sin elegir ninguna, la del teléfono', (tester) async {
      await setUpWith();
      await pumpSettings(tester);

      await expectWhole(tester, byKey('settings-voice-library'));
      expect(
        tester.widget<Text>(byKey('settings-voice-library-current')).data,
        es.f47P3NowReadingSystem,
      );
    });

    testWidgets('con una del teléfono elegida, su nombre; y su cara', (
      tester,
    ) async {
      const monica = NarrationVoice(name: 'Mónica', locale: 'es-ES');
      await setUpWith();
      await harness.container
          .read(narrationSettingsNotifierProvider.notifier)
          .selectVoice(monica);
      await pumpSettings(tester);

      await expectWhole(tester, byKey('settings-voice-library'));
      expect(
        tester.widget<Text>(byKey('settings-voice-library-current')).data,
        es.f47P3NowReading('Mónica'),
      );
      // La cara es la de esa voz, la misma que muestra el reproductor.
      final face = tester.widget<VoiceFaceView>(
        find.descendant(
          of: byKey('settings-voice-library'),
          matching: find.byType(VoiceFaceView),
        ),
      );
      final expected = VoiceFace.of(voiceProfileOf(monica)!.faceKey, 'Mónica');
      expect(face.face.hue, expected.hue);
      expect(face.face.initials, expected.initials);
    });

    testWidgets('con una sin conexión bajada, la nombra', (tester) async {
      await setUpWith(offline: true, installed: [daniela.package]);
      await harness.container
          .read(narrationSettingsNotifierProvider.notifier)
          .selectVoice(narrationVoiceOf(daniela));
      await pumpSettings(tester);

      await expectWhole(tester, byKey('settings-voice-library'));
      expect(
        tester.widget<Text>(byKey('settings-voice-library-current')).data,
        es.f47P3NowReading('Daniela'),
      );
    });

    testWidgets('tocarla abre la biblioteca de voces', (tester) async {
      await setUpWith();
      await pumpSettings(tester, textScale: 1);

      await tapShown(tester, byKey('settings-voice-library'));
      expect(find.byType(VoiceLibrarySheet), findsOneWidget);
    });
  });

  group('la velocidad con que empieza a leer', () {
    Finder speedValue() => byKey('settings-reading-speed-value');

    testWidgets('dice la guardada', (tester) async {
      await setUpWith();
      await harness.container
          .read(narrationSettingsNotifierProvider.notifier)
          .setSpeed(1.2);
      await pumpSettings(tester);

      await expectWhole(tester, speedValue());
      expect(tester.widget<Text>(speedValue()).data, '1,2×');
    });

    testWidgets('abre la misma regla del reproductor, con su aclaración; '
        'un atajo la cambia, la guarda y la usa el lector', (tester) async {
      await setUpWith();
      await pumpSettings(tester);
      await expectWhole(tester, speedValue());
      expect(tester.widget<Text>(speedValue()).data, '1,0×');

      await tapShown(tester, byKey('settings-reading-speed'));
      expect(find.byType(ReadAloudSpeedSheet), findsOneWidget);
      expect(byKey('read-aloud-speed-ruler'), findsOneWidget);
      expect(
        tester.widget<Text>(byKey('read-aloud-speed-note')).data,
        es.f47P7bSpeedNote,
      );

      await tester.ensureVisible(byKey('read-aloud-speed-1.5'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('read-aloud-speed-1.5'));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(narrationSettingsNotifierProvider).speed,
        1.5,
      );
      expect(
        harness.container
            .read(sharedPreferencesProvider)
            .getDouble('narration_speed'),
        1.5,
      );
      expect(harness.container.read(readAloudControllerProvider).speed, 1.5);
      expect(tester.takeException(), isNull);

      Navigator.of(tester.element(find.byType(ReadAloudSpeedSheet))).pop();
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(speedValue()).data, '1,5×');
    });

    testWidgets('es una sola: cambiarla en el reproductor la cambia acá', (
      tester,
    ) async {
      await setUpWith();
      await pumpSettings(tester);

      await harness.container
          .read(readAloudControllerProvider.notifier)
          .setSpeed(2);
      await tester.pumpAndSettle();
      await expectWhole(tester, speedValue());
      expect(tester.widget<Text>(speedValue()).data, '2,0×');
    });

    testWidgets('el reproductor no lleva la aclaración de Ajustes', (
      tester,
    ) async {
      await setUpWith();
      await tester.pumpWidget(
        harness.wrap(const Scaffold(body: ReadAloudSpeedSheet())),
      );
      await tester.pumpAndSettle();
      expect(byKey('read-aloud-speed-note'), findsNothing);
    });
  });

  group('la tipografía y el resaltado', () {
    Finder summary() => byKey('settings-reading-appearance-summary');

    testWidgets('dicen lo elegido y abren la Apariencia del marco, con todo '
        'lo que se guarda y sin el zoom de una página', (tester) async {
      await setUpWith();
      await pumpSettings(tester);

      await expectWhole(tester, summary());
      expect(tester.widget<Text>(summary()).data, 'Lora · 100 % · Amarillo');

      await tapShown(tester, byKey('settings-reading-appearance'));
      expect(find.byType(ReadingAppearanceSheet), findsOneWidget);
      for (final part in [
        'reading-font-nunito',
        'reading-size',
        'reading-appearance-sample',
        'reading-paper-hint',
        'reading-paper-sepia',
        'reading-highlight-lilac',
        'reading-mode-sepia',
      ]) {
        expect(byKey(part), findsOneWidget, reason: part);
      }
      expect(byKey('reading-zoom-in'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lo elegido ahí se guarda para todos los lectores y se ve '
        'en la fila', (tester) async {
      await setUpWith();
      await pumpSettings(tester, textScale: 1);

      await tapShown(tester, byKey('settings-reading-appearance'));
      final sheet = find.byType(Scrollable).last;
      for (final key in ['reading-font-nunito', 'reading-highlight-lilac']) {
        await tester.scrollUntilVisible(byKey(key), 200, scrollable: sheet);
        await tester.tap(byKey(key));
        await tester.pumpAndSettle();
      }

      final appearance = harness.container.read(readingAppearanceProvider);
      expect(appearance.font, ReadingFont.nunito);
      expect(appearance.highlight, ReadingHighlight.lilac);
      final prefs = harness.container.read(sharedPreferencesProvider);
      expect(prefs.getString(ReadingAppearanceNotifier.fontKey), 'nunito');
      expect(prefs.getString(ReadingAppearanceNotifier.highlightKey), 'lilac');

      Navigator.of(tester.element(find.byType(ReadingAppearanceSheet))).pop();
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(summary()).data, 'Nunito · 100 % · Lila');
    });

    for (final brightness in Brightness.values) {
      testWidgets('en ${brightness.name}, la hoja entra a 360 dp con la '
          'letra al doble', (tester) async {
        await setUpWith();
        await pumpSettings(tester, brightness: brightness);

        await tapShown(tester, byKey('settings-reading-appearance'));
        final sheet = find.byType(Scrollable).last;
        await tester.scrollUntilVisible(
          byKey('reading-mode-system'),
          300,
          scrollable: sheet,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('las voces descargadas', () {
    testWidgets('dicen cuántas son y lo que ocupan entre todas', (
      tester,
    ) async {
      const kokoro = OfflineVoiceCatalog.kokoro;
      await setUpWith(offline: true, installed: [daniela.package, kokoro]);
      await pumpSettings(tester);

      final voices = OfflineVoiceCatalog.voices
          .where(
            (voice) =>
                voice.package == daniela.package || voice.package == kokoro,
          )
          .length;
      final finder = byKey('settings-downloaded-voices-summary');
      await expectWhole(tester, finder);
      expect(
        tester.widget<Text>(finder).data,
        es.f47P7bDownloadedSummary(
          voices,
          formatFileSize(bytesOf([daniela.package, kokoro]), es.localeName),
        ),
      );
    });

    testWidgets('sin ninguna, «Ninguna todavía»', (tester) async {
      await setUpWith(offline: true);
      await pumpSettings(tester);

      await expectWhole(tester, byKey('settings-downloaded-voices'));
      expect(
        find.descendant(
          of: byKey('settings-downloaded-voices'),
          matching: find.text(es.f47P3SettingsDownloadedNone),
        ),
        findsOneWidget,
      );
    });

    testWidgets('su hoja vacía lleva a la biblioteca, que es donde se bajan '
        '(F46, paso 5f)', (tester) async {
      await setUpWith(offline: true);
      await pumpSettings(tester);

      await tapShown(tester, byKey('settings-downloaded-voices'));
      expect(byKey('downloaded-voices-empty'), findsOneWidget);
      final open = byKey('downloaded-voices-open-library');
      expect(
        find.descendant(of: open, matching: find.text(es.f47P3LibraryTitle)),
        findsOneWidget,
      );

      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(VoiceLibrarySheet), findsOneWidget);
    });

    testWidgets('donde no hay voces sin conexión, no está', (tester) async {
      await setUpWith();
      await pumpWholeSettings(tester);

      expect(byKey('settings-voice-library'), findsOneWidget);
      expect(byKey('settings-downloaded-voices'), findsNothing);
    });

    testWidgets('borrar la que lee, desde su hoja, vuelve a contar y deja '
        'leyendo a la del teléfono', (tester) async {
      await setUpWith(offline: true, installed: [daniela.package]);
      await harness.container
          .read(narrationSettingsNotifierProvider.notifier)
          .selectVoice(narrationVoiceOf(daniela));
      await pumpSettings(tester, textScale: 1);
      await expectWhole(tester, byKey('settings-voice-library-current'));
      expect(
        tester.widget<Text>(byKey('settings-voice-library-current')).data,
        es.f47P3NowReading('Daniela'),
      );

      await tapShown(tester, byKey('settings-downloaded-voices'));
      await tester.tap(byKey('downloaded-voice-delete-${daniela.package.id}'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('downloaded-voice-delete-confirm'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();

      await expectWhole(tester, byKey('settings-downloaded-voices'));
      expect(
        find.descendant(
          of: byKey('settings-downloaded-voices'),
          matching: find.text(es.f47P3SettingsDownloadedNone),
        ),
        findsOneWidget,
      );
      await expectWhole(tester, byKey('settings-voice-library-current'));
      expect(
        tester.widget<Text>(byKey('settings-voice-library-current')).data,
        es.f47P3NowReadingSystem,
      );
    });
  });

  testWidgets('para el lector de pantalla, cada fila es un botón con su '
      'nombre y lo de ahora', (tester) async {
    final semantics = tester.ensureSemantics();
    await setUpWith();
    await pumpSettings(tester);

    for (final (key, label) in [
      (
        'settings-voice-library',
        '${es.f47P3LibraryTitle}\n${es.f47P3NowReadingSystem}',
      ),
      ('settings-reading-speed', '${es.f47P7bSpeedTile}\n1,0×'),
      (
        'settings-reading-appearance',
        '${es.f47P7bAppearanceTile}\nLora · 100 % · Amarillo',
      ),
    ]) {
      await expectWhole(tester, byKey(key));
      expect(
        tester.getSemantics(byKey(key)),
        isSemantics(label: label, isButton: true, hasTapAction: true),
        reason: key,
      );
    }
    semantics.dispose();
  });
}
