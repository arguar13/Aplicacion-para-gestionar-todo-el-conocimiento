import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/network/in_app_model_file_transfer.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/ai_models/data/on_device/stable_diffusion_image_engine.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/device_profile.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/on_device_image_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/screens/ai_capabilities_screen.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_capability_card.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/illustration_settings_section.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/on_device_image_models.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../support/illustration_harness.dart';
import '../../../support/on_device_harness.dart';

final _l10n = AppLocalizationsEs();
const _sdxs = OnDeviceImageModel.sdxs;
const _turbo = OnDeviceImageModel.sdTurbo;

String _size(OnDeviceImageModel model) =>
    formatFileSize(model.spec.bytes, 'es');

void main() {
  late Directory root;
  late OnDeviceFakes fakes;
  late IllustrationHarness harness;

  Future<StableDiffusionImageEngine> create({
    DeviceProfile? phone,
    bool canPause = true,
    bool systemDownload = false,
    List<OnDeviceImageModel> downloaded = const [],
    List<OnDeviceImageModel> pausedHalfway = const [],
    AiProvider provider = AiProvider.anthropic,
  }) async {
    fakes = OnDeviceFakes(
      root: root,
      phone: phone,
      canPause: canPause,
      systemDownload: systemDownload,
    );
    downloaded.forEach(fakes.placeDownloaded);
    for (final model in pausedHalfway) {
      InAppModelFileTransfer.partialOf(fakes.fileOf(model))
        ..createSync(recursive: true)
        ..writeAsStringSync('mitad');
    }
    harness = await IllustrationHarness.create(
      provider: provider,
      realOnDeviceEngine: true,
      overrides: fakes.overrides,
    );
    addTearDown(harness.container.dispose);
    final engine = harness.container.read(stableDiffusionImageEngineProvider)!;
    await engine.start();
    return engine;
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    double width = 420,
    double textScale = 1,
    ThemeData? theme,
  }) => harness.pump(
    tester,
    const OnDeviceImageModelsPanel(),
    width: width,
    height: 6000,
    textScale: textScale,
    theme: theme,
  );

  Finder inCard(OnDeviceImageModel model, Finder finder) => find.descendant(
    of: find.byKey(Key('on-device-model-${model.spec.id}')),
    matching: finder,
  );

  setUp(() => root = Directory.systemTemp.createTempSync('panel_imagenes_'));
  tearDown(() => root.deleteSync(recursive: true));

  _testOnDevice('cada modelo con su enlace, licencia, peso, memoria, tiempo '
      'estimado, el veredicto del teléfono y sus pasos', (tester) async {
    await create();
    await pumpPanel(tester);

    expect(find.text(_l10n.f43DeviceNeedsTitle), findsOneWidget);
    expect(find.text(_l10n.f43DeviceNeedRam), findsOneWidget);
    expect(find.text(_l10n.f43DeviceNeedHeat), findsOneWidget);
    expect(find.text(_l10n.f43DeviceNeed512), findsOneWidget);
    expect(find.byKey(const Key('on-device-this-phone')), findsOneWidget);
    expect(find.textContaining(_l10n.f43DevicePhoneRam(12)), findsOneWidget);

    for (final model in OnDeviceImageModel.values) {
      final spec = model.spec;
      expect(inCard(model, find.text(spec.displayName)), findsOneWidget);
      expect(
        inCard(model, find.byKey(Key('on-device-link-${spec.id}'))),
        findsOneWidget,
      );
      expect(
        inCard(model, find.text(_l10n.f43DeviceSize(_size(model)))),
        findsOneWidget,
      );
      expect(
        inCard(
          model,
          find.text(_l10n.f43DeviceRam(spec.minRamGb, spec.recommendedRamGb)),
        ),
        findsOneWidget,
      );
      expect(
        inCard(
          model,
          find.text(
            _l10n.f43DeviceTimeEstimated(
              aiDuration(
                _l10n,
                Duration(seconds: spec.estimatedSecondsPerImage),
              ),
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(
        inCard(model, find.text(_l10n.f43DeviceVerdictCan)),
        findsOneWidget,
      );
      expect(
        inCard(model, find.text(_l10n.f43DeviceStepDownload(_size(model)))),
        findsOneWidget,
      );
      expect(
        inCard(model, find.text(_l10n.f43DeviceStepMeasure)),
        findsOneWidget,
      );
      expect(inCard(model, find.text(_l10n.f43DeviceStepUse)), findsOneWidget);
      expect(
        inCard(model, find.text(_l10n.f43DeviceDownload(_size(model)))),
        findsOneWidget,
      );
    }
    expect(
      inCard(_sdxs, find.text(_l10n.f43DeviceLicenseOpenRail)),
      findsOneWidget,
    );
    expect(
      inCard(_turbo, find.text(_l10n.f43AiLicenseStability)),
      findsOneWidget,
    );
  });

  _testOnDevice(
    'con 6 GB, SD-Turbo no alcanza, dice por qué y no deja bajarlo; '
    'SDXS anda justo',
    (tester) async {
      await create(phone: phoneWith(ramGb: 6));
      await pumpPanel(tester);

      expect(
        inCard(_turbo, find.text(_l10n.f43DeviceVerdictCannot)),
        findsOneWidget,
      );
      expect(
        inCard(_turbo, find.text(_l10n.f43DeviceReasonRamLow(6, 8))),
        findsOneWidget,
      );
      final download = tester.widget<ButtonStyleButton>(
        find.byKey(Key('on-device-download-${_turbo.spec.id}')),
      );
      expect(download.onPressed, isNull);

      expect(
        inCard(_sdxs, find.text(_l10n.f43DeviceVerdictTight)),
        findsOneWidget,
      );
      expect(
        inCard(_sdxs, find.text(_l10n.f43DeviceReasonRamTight(6, 8))),
        findsOneWidget,
      );
    },
  );

  _testOnDevice('bajar dentro de la app: el avance, pausar, seguir desde ahí y '
      'quedar en uso', (tester) async {
    await create();
    await pumpPanel(tester);
    final id = _sdxs.spec.id;
    final name = _sdxs.spec.fileName;
    final bytes = fakeSpecOf(_sdxs).bytes;

    await tester.tap(find.byKey(Key('on-device-download-$id')));
    await tester.pump();
    fakes.transfer.progress(name, bytes ~/ 2);
    await tester.pump();
    final percent = '${(bytes ~/ 2 / bytes * 100).floor()} %';
    expect(find.text(_l10n.f43DeviceDownloading(percent)), findsOneWidget);
    expect(find.text(_l10n.f43DeviceSystemDownload), findsNothing);

    await tester.tap(find.byKey(Key('on-device-pause-$id')));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.f43DevicePaused(percent)), findsOneWidget);
    expect(
      InAppModelFileTransfer.partialOf(fakes.fileOf(_sdxs)).existsSync(),
      isTrue,
      reason: 'pausar no borra lo bajado',
    );

    await tester.tap(find.byKey(Key('on-device-resume-$id')));
    await tester.pump();
    await tester.runAsync(
      () => fakes.transfer.finish(name, fakeModelContent(_sdxs)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(Key('on-device-measure-$id')), findsOneWidget);
    expect(find.byKey(Key('on-device-delete-$id')), findsOneWidget);
    expect(find.byKey(Key('on-device-active-$id')), findsOneWidget);
    expect(fakes.fileOf(_sdxs).existsSync(), isTrue);
  });

  _testOnDevice('con el gestor del sistema no hay «Pausar», y dice que sigue '
      'con la app cerrada', (tester) async {
    await create(canPause: false, systemDownload: true);
    await pumpPanel(tester);
    final id = _turbo.spec.id;

    await tester.tap(find.byKey(Key('on-device-download-$id')));
    await tester.pump();
    fakes.transfer.progress(_turbo.spec.fileName, 1);
    await tester.pump();

    expect(find.byKey(Key('on-device-pause-$id')), findsNothing);
    expect(find.text(_l10n.f43DeviceSystemDownload), findsOneWidget);
    await tester.tap(find.byKey(Key('on-device-cancel-$id')));
    // Cortar la suscripción contesta con un futuro de la zona raíz: con el
    // reloj de mentira, hay que dejar correr de verdad la cola de la raíz
    // para que la cancelación termine.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      InAppModelFileTransfer.partialOf(fakes.fileOf(_turbo)).existsSync(),
      isFalse,
    );
    expect(find.byKey(Key('on-device-download-$id')), findsOneWidget);
  });

  _testOnDevice(
    'sin lugar, la descarga lo dice con cuánto hace falta, y ofrece '
    'reintentar',
    (tester) async {
      await create();
      fakes.transfer.failWith = const InsufficientStorageException(
        requiredBytes: 2 * 1024 * 1024 * 1024,
      );
      await pumpPanel(tester);

      await tester.tap(find.byKey(Key('on-device-download-${_turbo.spec.id}')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          _l10n.f43DeviceDownloadNoSpace(formatFileSize(1 << 31, 'es')),
        ),
        findsOneWidget,
      );
      expect(find.text(_l10n.f43DeviceRetry), findsOneWidget);
    },
  );

  _testOnDevice('una descarga que no pasa la huella lo dice', (tester) async {
    await create();
    await pumpPanel(tester);
    await tester.tap(find.byKey(Key('on-device-download-${_sdxs.spec.id}')));
    await tester.pump();
    await tester.runAsync(
      () => fakes.transfer.finish(
        _sdxs.spec.fileName,
        'y' * fakeSpecOf(_sdxs).bytes,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_l10n.f43DeviceDownloadCorrupt), findsOneWidget);
    expect(fakes.fileOf(_sdxs).existsSync(), isFalse);
  });

  _testOnDevice('«Medir en mi teléfono» dibuja una de prueba, lo dice y queda '
      'el tiempo medido; se puede cancelar', (tester) async {
    await create(downloaded: [_sdxs]);
    await pumpPanel(tester);
    final id = _sdxs.spec.id;

    // Cancelar a mitad no deja nada medido ni muestra un error.
    fakes.runtime.gate = Completer<void>();
    await tester.tap(find.byKey(Key('on-device-measure-$id')));
    await tester.pump();
    expect(find.text(_l10n.f43DeviceMeasuring), findsOneWidget);
    await tester.tap(find.byKey(Key('on-device-measure-cancel-$id')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(Key('on-device-measure-$id')), findsOneWidget);

    fakes.runtime
      ..gate = null
      ..failure = null;
    await tester.tap(find.byKey(Key('on-device-measure-$id')));
    await tester.pumpAndSettle();

    final seventeen = aiDuration(_l10n, const Duration(seconds: 17));
    expect(
      find.text(_l10n.f43DeviceMeasured('SDXS-512', seventeen)),
      findsOneWidget,
    );
    expect(
      find.text(
        _l10n.f43DeviceTimeMeasuredWithLoad(
          seventeen,
          aiDuration(_l10n, const Duration(seconds: 4)),
        ),
      ),
      findsOneWidget,
    );
  });

  _testOnDevice('con los dos bajados, «Usar este» mueve «En uso»', (
    tester,
  ) async {
    await create(downloaded: [_sdxs, _turbo]);
    await pumpPanel(tester);
    expect(
      find.byKey(Key('on-device-active-${_turbo.spec.id}')),
      findsOneWidget,
    );
    expect(find.byKey(Key('on-device-use-${_turbo.spec.id}')), findsNothing);

    await tester.tap(find.byKey(Key('on-device-use-${_sdxs.spec.id}')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('on-device-active-${_sdxs.spec.id}')),
      findsOneWidget,
    );
    expect(find.byKey(Key('on-device-active-${_turbo.spec.id}')), findsNothing);
  });

  _testOnDevice('borrar pide confirmar, dice que no toca nada más y saca solo '
      'el archivo del modelo', (tester) async {
    await create(downloaded: [_sdxs, _turbo]);
    final other = File('${root.path}/boveda.sqlite')..writeAsStringSync('base');
    await pumpPanel(tester);

    await tester.tap(find.byKey(Key('on-device-delete-${_sdxs.spec.id}')));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.f43DeviceDeleteBody(_size(_sdxs))), findsOneWidget);
    await tester.tap(find.byKey(const Key('on-device-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.f43DeviceDeleted('SDXS-512')), findsOneWidget);
    expect(fakes.fileOf(_sdxs).existsSync(), isFalse);
    expect(fakes.fileOf(_turbo).existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
    expect(
      find.byKey(Key('on-device-download-${_sdxs.spec.id}')),
      findsOneWidget,
    );
  });

  _testOnDevice('si se cerró dibujando: no alcanza, dice por qué y «Probar de '
      'nuevo» lo vuelve a medir y encender', (tester) async {
    final engine = await create(downloaded: [_sdxs]);
    await harness.container
        .read(onDeviceImageStoreProvider)
        .markClosed(_sdxs, DateTime.utc(2026, 10, 28));
    expect(engine.isClosed(_sdxs), isTrue);
    await pumpPanel(tester);

    expect(
      inCard(_sdxs, find.text(_l10n.f43DeviceVerdictCannot)),
      findsOneWidget,
    );
    expect(
      inCard(_sdxs, find.text(_l10n.f43DeviceReasonClosed)),
      findsOneWidget,
    );
    await tester.tap(find.text(_l10n.f43DeviceTryAgain));
    await tester.pumpAndSettle();

    expect(engine.isClosed(_sdxs), isFalse);
    expect(inCard(_sdxs, find.text(_l10n.f43DeviceVerdictCan)), findsOneWidget);
  });

  _testOnDevice('Ajustes → IA: «Imágenes en el teléfono (Exigente)» con su '
      'resumen, y abre su pantalla', (tester) async {
    await create();
    await harness.pump(tester, const IllustrationSettingsSection());

    final tile = find.byKey(const Key('illustration-settings-on-device'));
    expect(tile, findsOneWidget);
    expect(find.text(_l10n.f43DeviceSummaryOptional), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(OnDeviceImageScreen), findsOneWidget);
    expect(find.text(_l10n.f43DeviceScreenTitle), findsWidgets);
  });

  _testOnDevice('el resumen de Ajustes dice el modelo listo y su tiempo, '
      'estimado o medido', (tester) async {
    final engine = await create(downloaded: [_sdxs]);
    final estimated = aiDuration(
      _l10n,
      Duration(seconds: _sdxs.spec.estimatedSecondsPerImage),
    );
    expect(
      onDeviceSummaryLine(_l10n, engine),
      _l10n.f43DeviceSummaryReadyEstimated('SDXS-512', estimated),
    );
    await engine.measure(_sdxs);
    expect(
      onDeviceSummaryLine(_l10n, engine),
      _l10n.f43DeviceSummaryReady(
        'SDXS-512',
        aiDuration(_l10n, const Duration(seconds: 17)),
      ),
    );
    fakes.probe.profile = phoneWith(ramGb: 4);
    await engine.profile(refresh: true);
    await engine.releaseNow();
    expect(onDeviceSummaryLine(_l10n, engine), isNotEmpty);
  });

  _testOnDevice('«¿Qué puede cada IA?» trae las tarjetas en «Exigente — en el '
      'teléfono»', (tester) async {
    await create();
    await harness.pump(
      tester,
      const AiCapabilitiesScreen(),
      scroll: false,
      height: 9000,
    );
    expect(find.byKey(const Key('ai-capabilities-on-device')), findsOneWidget);
    expect(find.byKey(const Key('on-device-models')), findsOneWidget);
  });

  _testOnDevice('«Con tu IA actual» ofrece el teléfono con su tiempo: estimado '
      'hasta medirlo', (tester) async {
    await create(downloaded: [_sdxs]);
    const request = CreationEstimateRequest(
      inputTokens: 100,
      expectedOutputTokens: 10,
      images: 3,
    );
    final sub = harness.container.listen(
      creationEstimateProvider(request),
      (_, _) {},
    );
    addTearDown(sub.close);
    await harness.pump(
      tester,
      Consumer(
        builder: (context, ref, _) => AiCapabilityCard(
          estimate: ref.watch(creationEstimateProvider(request)),
        ),
      ),
    );
    final minute = aiDuration(
      _l10n,
      Duration(seconds: _sdxs.spec.estimatedSecondsPerImage * 3),
    );
    expect(find.text(_l10n.f43DeviceAltHintEstimated(minute)), findsOneWidget);

    await harness.container.read(onDeviceImageActionsProvider)!.measure(_sdxs);
    await tester.pumpAndSettle();
    expect(
      find.text(
        _l10n.f43AiAltOnDeviceHint(
          aiDuration(_l10n, const Duration(seconds: 51)),
        ),
      ),
      findsOneWidget,
    );
  });

  _testOnDevice('en 360 dp con el texto al doble, en los nueve temas, sin '
      'desbordes: bajado y medido, pausado, sin alcanzar', (tester) async {
    await create(
      phone: phoneWith(ramGb: 6),
      downloaded: [_sdxs],
      pausedHalfway: [_turbo],
    );
    await harness.container.read(onDeviceImageActionsProvider)!.measure(_sdxs);
    for (final theme in kAllAppThemes) {
      await pumpPanel(tester, width: 360, textScale: 2, theme: theme);
      expect(tester.takeException(), isNull);
    }
    expect(
      find.byKey(Key('on-device-paused-${_turbo.spec.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('on-device-measure-${_sdxs.spec.id}')),
      findsOneWidget,
    );
    expect(
      inCard(_turbo, find.text(_l10n.f43DeviceVerdictCannot)),
      findsOneWidget,
    );

    // La pantalla de Ajustes, también.
    await harness.pump(
      tester,
      const OnDeviceImageScreen(),
      width: 360,
      textScale: 2,
      theme: kAllAppThemes.last,
      scroll: false,
    );
    expect(tester.takeException(), isNull);
  });
}

/// Un `testWidgets` que al final deja correr los temporizadores que quedan
/// —el aviso de la notificación de la descarga (15 s) y soltar el modelo
/// (2 min)—, como pasaría en el teléfono.
@isTest
void _testOnDevice(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pump(const Duration(minutes: 3));
    });
