import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/narration/data/voices/eleven_labs_voice_cloud.dart';
import 'package:sinapsis/features/narration/data/voices/kokoro_style_bank.dart';
import 'package:sinapsis/features/narration/data/voices/my_voices_service.dart';
import 'package:sinapsis/features/narration/data/voices/my_voices_store.dart';
import 'package:sinapsis/features/narration/data/voices/offline_voice_files.dart';
import 'package:sinapsis/features/narration/data/voices/voice_sample_tools.dart';
import 'package:sinapsis/features/narration/domain/services/voice_recorder.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/recording_check.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/features/transform/data/services/audio_wav_converter.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import 'fake_file_chooser.dart';
import 'fake_id_generator.dart';
import 'fake_offline_speech.dart';
import 'fake_text_to_speech_service.dart';
import 'fake_voice_cloud.dart';
import 'on_device_harness.dart';

/// Un micrófono de mentira (F47, paso 4): «graba» escribiendo un archivo y
/// avisa el nivel; termina cuando la prueba lo dice ([stop]) o falla con
/// [failWith].
class FakeVoiceRecorder implements VoiceRecorder {
  bool granted = true;
  String? failWith;
  final recorded = <String>[];
  StreamController<RecordingProgress>? _current;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Stream<RecordingProgress> record({
    required String outputPath,
    required Duration limit,
  }) {
    recorded.add(outputPath);
    final controller = _current = StreamController<RecordingProgress>();
    scheduleMicrotask(() {
      if (failWith case final code?) {
        controller
          ..addError(VoiceRecorderException(code))
          ..close();
        return;
      }
      File(outputPath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('grabado');
      controller.add(
        const RecordingProgress(level: 0.5, elapsed: Duration(seconds: 65)),
      );
    });
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    final current = _current;
    _current = null;
    await current?.close();
  }
}

/// Medir la muestra sin isolates ni conversor: devuelve [report].
class FakeVoiceSampleTools implements VoiceSampleTools {
  FakeVoiceSampleTools(this.folder);

  final Directory folder;
  RecordingReport report = const RecordingReport(
    total: Duration(seconds: 90),
    voiced: Duration(seconds: 75),
    noiseDb: -70,
    voiceDb: -18,
    clippedRatio: 0,
  );
  bool failUpload = false;
  final analyzed = <String>[];

  @override
  Future<RecordingReport> analyze(File wav) async {
    analyzed.add(wav.path);
    return report;
  }

  @override
  Future<File> newRecording() async =>
      File(p.join(folder.path, 'grabar', 'grabacion.wav'));

  @override
  Future<(File, RecordingReport)> importUpload(CapturedFile file) async {
    if (failUpload) throw const AudioConversionException('no es audio');
    final copy = File(p.join(folder.path, 'subir', file.name))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(await file.readAll());
    return (copy, report);
  }
}

/// Un banco de estilos de mentira: deja un archivo y anota qué se escribió.
class FakeStyleBank implements KokoroStyleBank {
  final writes = <Map<int, KokoroBlend>>[];

  @override
  Future<void> write({
    required String source,
    required String target,
    required Map<int, KokoroBlend> blends,
  }) async {
    writes.add(blends);
    File(target)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('estilos');
  }
}

/// El almacén seguro de mentira, en memoria.
class FakeSecureStorage implements FlutterSecureStorage {
  final values = <String, String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final named = invocation.namedArguments;
    final key = named[#key] as String?;
    switch (invocation.memberName) {
      case #read:
        return Future<String?>.value(values[key]);
      case #write:
        final value = named[#value] as String?;
        if (value == null) {
          values.remove(key);
        } else {
          values[key!] = value;
        }
        return Future<void>.value();
      case #delete:
        values.remove(key);
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// Lo de Mías con dobles, sobre una carpeta temporal: el almacén, la nube, el
/// micrófono, el banco de estilos y el motor sin conexión.
class MyVoicesHarness {
  MyVoicesHarness._(this.root, this.prefs);

  static Future<MyVoicesHarness> create({
    bool cloudEnabled = false,
    String? cloudKey,
    bool kokoro = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      VoiceCloudSettingsNotifier.enabledKey: cloudEnabled,
    });
    final prefs = await SharedPreferences.getInstance();
    final harness = MyVoicesHarness._(
      Directory.systemTemp.createTempSync('mias-pantalla-'),
      prefs,
    );
    if (cloudKey != null) {
      harness.secure.values['voice_cloud_elevenlabs_key_v1'] = cloudKey;
    }
    if (kokoro) harness.installKokoro();
    return harness;
  }

  final Directory root;
  final SharedPreferences prefs;
  final secure = FakeSecureStorage();
  final cloud = FakeVoiceCloud();
  final recorder = FakeVoiceRecorder();
  final synthesizer = FakeOfflineSpeechSynthesizer();
  final bank = FakeStyleBank();
  final clips = FakeSpeechClipPlayer();
  final tts = FakeTextToSpeechService();

  /// Lo que devuelve el selector de archivos: se cambia antes de armar la
  /// pantalla.
  FakeFileChooser chooser = FakeFileChooser();
  late final tools = FakeVoiceSampleTools(root);
  late final store = MyVoicesStore(rootDirectory: () async => root);
  late final files = OfflineVoiceFiles(
    transfer: FakeModelTransfer(),
    rootDirectory: () async => root,
  );
  final installed = <String>{};

  /// Pone Kokoro «bajado».
  void installKokoro() {
    final folder = Directory(
      p.join(root.path, 'modelos', 'voces', OfflineVoiceCatalog.kokoro.id),
    );
    final base = Directory(p.join(folder.path, 'kokoro'))
      ..createSync(recursive: true);
    File(p.join(base.path, 'voices.bin')).writeAsStringSync('estilos');
    File(p.join(folder.path, '.voz.json')).writeAsStringSync(
      const OfflineVoiceManifest(base: 'kokoro', model: 'model.onnx').encode(),
    );
    installed.add(OfflineVoiceCatalog.kokoro.id);
  }

  MyVoicesService get service => MyVoicesService(
    store: store,
    ids: FakeIdGenerator(prefix: 'voz'),
    clock: () => DateTime.utc(2026, 10, 31, 15),
    files: files,
    synthesizer: synthesizer,
    cloud: cloud,
    bank: bank,
  );

  List<Override> get overrides => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    elevenLabsKeyStoreProvider.overrideWithValue(
      ElevenLabsKeyStore(storage: secure),
    ),
    myVoicesAvailableProvider.overrideWithValue(true),
    offlineVoicesAvailableProvider.overrideWithValue(true),
    myVoicesStoreProvider.overrideWithValue(store),
    offlineVoiceFilesProvider.overrideWithValue(files),
    offlineSpeechSynthesizerProvider.overrideWithValue(synthesizer),
    installedVoicePackagesProvider.overrideWith(
      (ref) => Stream.value({...installed}),
    ),
    voiceCloudProvider.overrideWithValue(cloud),
    myVoicesServiceProvider.overrideWith((ref) => service),
    voiceRecorderProvider.overrideWithValue(recorder),
    voiceSampleToolsProvider.overrideWithValue(tools),
    voicePreviewDirectoryProvider.overrideWithValue(
      () async =>
          Directory(p.join(root.path, 'propuestas'))
            ..createSync(recursive: true),
    ),
    voiceSampleClipPlayerProvider.overrideWithValue(clips),
    textToSpeechServiceProvider.overrideWithValue(tts),
    fileChooserProvider.overrideWithValue(chooser),
    clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 31, 15)),
  ];

  Future<void> dispose() async {
    await store.dispose();
    await files.dispose();
    root.deleteSync(recursive: true);
  }
}

/// Lleva [target] a la vista y lo toca.
Future<void> tapShown(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

/// [child] en una app, a 360 dp, con la letra a [textScale] y el tema
/// [themeMode].
Future<ProviderContainer> pumpMyVoices(
  WidgetTester tester,
  MyVoicesHarness harness,
  Widget child, {
  double textScale = 1,
  ThemeMode themeMode = ThemeMode.light,
  List<Override> extra = const [],
}) async {
  tester.view
    ..physicalSize = const Size(360, 760)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [...harness.overrides, ...extra],
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
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
  return container;
}
