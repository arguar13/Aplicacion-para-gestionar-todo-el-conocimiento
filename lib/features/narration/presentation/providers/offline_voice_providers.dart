import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/core/network/model_download_providers.dart';
import 'package:sinapsis/features/narration/data/voices/offline_text_to_speech_service.dart';
import 'package:sinapsis/features/narration/data/voices/offline_voice_files.dart';
import 'package:sinapsis/features/narration/data/voices/sherpa_onnx_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/data/voices/video_player_speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// Si este dispositivo lee con voces sin conexión (F47, paso 3): en Android,
/// donde la app trae `sherpa_onnx` y el reproductor de audio. En la web y en
/// el escritorio no se ofrecen —el escritorio no tiene con qué hacerlas
/// sonar—, y queda la voz del sistema.
///
/// `Platform.isAndroid` y no `defaultTargetPlatform`: en las pruebas, la
/// plataforma de mentira es Android, y nada tiene que armar el motor de
/// verdad sin que la prueba lo pida.
final offlineVoicesAvailableProvider = Provider<bool>(
  (ref) => !kIsWeb && Platform.isAndroid,
);

/// Los paquetes de las voces sin conexión, donde viven los demás modelos y
/// con la misma transferencia (el gestor del sistema en Android, F29).
/// `null` donde no se ofrecen.
final offlineVoiceFilesProvider = Provider<OfflineVoiceFiles?>((ref) {
  if (!ref.watch(offlineVoicesAvailableProvider)) return null;
  final files = OfflineVoiceFiles(
    transfer: ref.watch(modelFileTransferProvider),
    rootDirectory: ref.watch(modelStorageProvider).root,
  );
  ref.onDispose(() => unawaited(files.dispose()));
  return files;
});

/// El motor de las voces sin conexión; `null` donde no se ofrecen. Las
/// pruebas lo cambian por uno de mentira.
final offlineSpeechSynthesizerProvider = Provider<OfflineSpeechSynthesizer?>((
  ref,
) {
  if (!ref.watch(offlineVoicesAvailableProvider)) return null;
  final synthesizer = createOfflineSpeechSynthesizer();
  ref.onDispose(() => unawaited(synthesizer?.dispose()));
  return synthesizer;
});

/// El lector con las voces sin conexión, para el motor del lector
/// (`textToSpeechServiceProvider`); `null` donde no se ofrecen.
final offlineTextToSpeechServiceProvider = Provider<TextToSpeechService?>((
  ref,
) {
  final files = ref.watch(offlineVoiceFilesProvider);
  final synthesizer = ref.watch(offlineSpeechSynthesizerProvider);
  if (files == null || synthesizer == null) return null;
  final player = VideoPlayerSpeechClipPlayer();
  final service = OfflineTextToSpeechService(
    synthesizer: synthesizer,
    player: player,
    engineOf: files.engineConfigOf,
    clipsDirectory: () async => Directory(
      p.join((await getTemporaryDirectory()).path, 'voz-sin-conexion'),
    ),
  );
  ref.onDispose(() {
    unawaited(service.dispose());
    unawaited(player.dispose());
  });
  return service;
});

/// Qué paquetes de voces están en el teléfono, al día con cada voz que se
/// baja o se borra.
final installedVoicePackagesProvider = StreamProvider<Set<String>>((
  ref,
) async* {
  final files = ref.watch(offlineVoiceFilesProvider);
  if (files == null) {
    yield const {};
    return;
  }
  yield await files.installedPackageIds();
  await for (final _ in files.changes()) {
    yield await files.installedPackageIds();
  }
});

/// La descarga de cada paquete de voz, viva aparte de su tarjeta (ver
/// [ModelDownloadNotifier]): una por paquete, por su id. NO autoDispose:
/// sigue aunque nadie la mire.
final offlineVoiceDownloadProvider =
    StateNotifierProvider.family<
      ModelDownloadNotifier,
      ModelDownloadState,
      String
    >(
      (ref, packageId) => ModelDownloadNotifier(
        keeper: modelDownloadKeeper(ref),
        detail: LongWorkDetail.voiceModel,
      ),
    );

/// Bajar, pausar, cancelar y borrar las voces sin conexión; `null` donde no
/// se ofrecen.
final offlineVoiceActionsProvider = Provider<OfflineVoiceActions?>((ref) {
  final files = ref.watch(offlineVoiceFilesProvider);
  if (files == null) return null;
  return OfflineVoiceActions(
    files: files,
    synthesizer: ref.watch(offlineSpeechSynthesizerProvider),
    download: (package) =>
        ref.read(offlineVoiceDownloadProvider(package.id).notifier),
  );
});

class OfflineVoiceActions {
  OfflineVoiceActions({
    required OfflineVoiceFiles files,
    required OfflineSpeechSynthesizer? synthesizer,
    required ModelDownloadNotifier Function(OfflineVoicePackage package)
    download,
  }) : _files = files,
       _synthesizer = synthesizer,
       _download = download;

  final OfflineVoiceFiles _files;
  final OfflineSpeechSynthesizer? _synthesizer;
  final ModelDownloadNotifier Function(OfflineVoicePackage package) _download;

  /// Si se puede pausar una descarga (ver `ModelFileTransfer.canPause`).
  bool get canPause => _files.canPause;

  /// «Bajar» (o «Seguir», si estaba pausada). Es lo único que baja una voz:
  /// nada la baja sin que se toque. Devuelve si empezó.
  bool download(OfflineVoicePackage package) =>
      _download(package).start(() => _files.download(package));

  Future<void> pause(OfflineVoicePackage package) =>
      _download(package).pause(() => _files.pause(package));

  /// Corta la descarga y borra lo bajado: la que corre o la pausada.
  Future<void> cancel(OfflineVoicePackage package) async {
    final notifier = _download(package);
    await notifier.cancel(() => _files.cancel(package));
    await _files.cancel(package);
    notifier.clearError();
  }

  /// «Borrar», desde Ajustes: suelta el motor —que puede tener la voz
  /// cargada— y borra el paquete. Lo que se leía con ella sigue con la del
  /// teléfono.
  Future<void> delete(OfflineVoicePackage package) async {
    await _synthesizer?.release();
    await _files.delete(package);
  }

  /// Cuánto ocupa [package] en el teléfono, o `null` si no está.
  Future<int?> installedBytes(OfflineVoicePackage package) =>
      _files.installedBytes(package);
}
