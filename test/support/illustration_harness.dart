import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/app_theme_palette.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/image_wire.dart';
import 'package:sinapsis/features/ai_models/data/cloud/on_device_image_engine.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import 'fake_chat_model_manager.dart';

/// Los nueve temas de la app: claro, oscuro y las seis paletas (F43: lo
/// nuevo se ve bien en todos).
final kAllAppThemes = <ThemeData>[
  AppTheme.lightTheme,
  AppTheme.darkTheme,
  for (final palette in AppThemePalette.values) AppTheme.fromPalette(palette),
];

/// Un proveedor de texto de mentira que solo lista modelos.
class FakeTextWire implements CloudWire {
  FakeTextWire(this.provider);

  @override
  final AiProvider provider;

  @override
  Future<List<CloudModelInfo>> listModels(String key) async => const [];

  @override
  String? recommendedModel(List<CloudModelInfo> models) => null;

  @override
  Stream<CloudDelta> stream(
    CloudRequest request, {
    required String key,
    CancelToken? cancel,
  }) => const Stream.empty();
}

/// Un proveedor de imágenes de mentira para las pantallas: lista lo que se
/// le diga, dibuja o falla como se le programe, nunca sale a internet.
class FakeScreenImageWire implements ImageWire {
  FakeScreenImageWire(this.provider);

  @override
  final IllustrationProvider provider;

  List<ImageModelInfo> models = const [
    ImageModelInfo(id: 'gemini-nano-banana-2.1', displayName: 'Nano Banana'),
  ];
  ImageFailure? listFailure;
  ImageFailure? generateFailure;
  final generated = <ImageWireRequest>[];
  final listedKeys = <String?>[];

  @override
  Future<List<ImageModelInfo>> listImageModels(ImageWireAccess access) async {
    listedKeys.add(access.key);
    if (listFailure case final failure?) {
      throw ImageGenerationException(failure);
    }
    return models;
  }

  @override
  String? recommendedImageModel(List<ImageModelInfo> models) =>
      models.firstOrNull?.id;

  @override
  Future<GeneratedImage> generate(
    ImageWireRequest request,
    ImageWireAccess access, {
    CancelToken? cancel,
  }) async {
    generated.add(request);
    if (generateFailure case final failure?) {
      throw ImageGenerationException(failure);
    }
    return GeneratedImage(
      bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 1]),
      mimeType: 'image/jpeg',
      model: request.model,
    );
  }
}

/// Un modelo del teléfono de mentira, listo para dibujar.
class FakeOnDeviceEngine extends FakeScreenImageWire
    implements OnDeviceImageEngine {
  FakeOnDeviceEngine() : super(IllustrationProvider.onDevice);

  @override
  String get displayName => 'SDXS 512';

  @override
  Future<OnDeviceImageReadiness> readiness() async =>
      const OnDeviceImageReadiness.ready();

  @override
  Duration estimatedTimePerImage(IllustrationSize size) =>
      const Duration(seconds: 45);

  @override
  bool get timeMeasured => false;

  @override
  Stream<void> changes() => const Stream.empty();
}

/// Lo de la IA de imágenes armado para una prueba de pantalla: almacén
/// seguro y preferencias de mentira, reloj fijo y proveedores falsos.
class IllustrationHarness {
  IllustrationHarness._(this.container, this.prefs, this.wires);

  static Future<IllustrationHarness> create({
    DateTime? now,
    OnDeviceImageEngine? onDevice,
    AiProvider provider = AiProvider.gemini,
    List<Override> overrides = const [],
    bool realOnDeviceEngine = false,
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'ai_model_settings_v1': '{"provider":"${provider.storageKey}"}',
    });
    final prefs = await SharedPreferences.getInstance();
    final wires = {
      for (final p in [
        IllustrationProvider.gemini,
        IllustrationProvider.openAi,
        IllustrationProvider.huggingFace,
      ])
        p: FakeScreenImageWire(p),
    };
    final at = now ?? DateTime.utc(2026, 10, 28, 15);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => at),
        cloudWiresProvider.overrideWithValue({
          for (final p in [
            AiProvider.gemini,
            AiProvider.openAi,
            AiProvider.anthropic,
          ])
            p: FakeTextWire(p),
        }),
        imageWiresProvider.overrideWithValue(wires),
        // Con [realOnDeviceEngine], el motor de verdad sobre lo de
        // mentira que traiga [overrides] (ver `on_device_harness.dart`).
        if (!realOnDeviceEngine)
          onDeviceImageEngineProvider.overrideWithValue(onDevice),
        chatModelManagerProvider.overrideWithValue(FakeChatModelManager()),
        ...overrides,
      ],
    );
    return IllustrationHarness._(container, prefs, wires);
  }

  final ProviderContainer container;
  final SharedPreferences prefs;
  final Map<IllustrationProvider, FakeScreenImageWire> wires;

  /// Dibuja [child] a [width] de ancho, con [textScale] y [theme].
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 420,
    double height = 1600,
    double textScale = 1,
    ThemeData? theme,
    bool scroll = true,
  }) async {
    tester.view
      ..physicalSize = Size(width, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('es'),
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: Scaffold(
              body: scroll
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: child,
                    )
                  : child,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
