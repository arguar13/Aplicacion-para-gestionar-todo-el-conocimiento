/// Descargar, escuchar, exportar y borrar el audio de lo que se lee, desde
/// ⋮ del marco de lectura (F47, paso 5, punto 6 del plan), y la barra que
/// dice cómo va la descarga.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/creations/data/services/system_creation_sharer.dart';
import 'package:sinapsis/features/narration/domain/audio/document_audio.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/reading_timeline.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/presentation/providers/document_audio_downloads.dart';
import 'package:sinapsis/features/narration/presentation/providers/document_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/speech_audio_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_anchored_player.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_voice_face.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/narration/presentation/voices/speech_audio_approval.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_card.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_more_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Quien pasa un archivo del teléfono a otra app con la hoja de compartir
/// del sistema, sin traerlo a memoria. [origin] es de dónde sale la hoja en
/// un iPad o una Mac.
typedef AudioFileSharer =
    Future<void> Function({
      required String path,
      required String fileName,
      required String mimeType,
      required String title,
      Rect? origin,
    });

/// La hoja de compartir de siempre (`share_plus`, la de «Compartir» de lo
/// creado), o `null` donde no acepta archivos: ahí «Exportar audio» no se
/// ofrece. Las pruebas la cambian.
final audioFileSharerProvider = Provider<AudioFileSharer?>(
  (ref) =>
      systemShareSupportsFiles() ? SystemCreationSharer().shareFileAt : null,
);

/// Lo que el marco tiene que tener a mano para que ⋮ diga en qué está el
/// audio de [documentId] apenas se abre: su ficha y si quedó algo a medias.
/// Se mira desde la construcción del marco.
void watchReadingAudio(WidgetRef ref, String? documentId) {
  if (documentId == null || !ref.watch(documentAudioSupportedProvider)) return;
  ref
    ..watch(documentAudioProvider(documentId))
    ..watch(documentAudioResumableProvider(documentId));
}

/// El grupo del audio de ⋮ para lo que ofrece el cuerpo del marco: **Descargar
/// audio** —o cómo va, o por qué falló, o «Audio descargado», o «Generar de
/// nuevo el audio» si quedó viejo—, **Exportar audio** y, en rojo, **Borrar
/// el audio descargado**. Lo que se borra es solo el audio: el documento, y
/// menos la fuente de la Biblioteca, no se tocan.
///
/// `null` —no está— donde no se descargan audios (la web, Windows), si el
/// cuerpo no ofrece nada para leer, si lo que ofrece ya suena en su propio
/// audio (un audio, un video, un podcast) o si no tiene nada que decir.
ReadingMenuGroup? readingAudioGroup(BuildContext host, WidgetRef ref) {
  if (!ref.read(documentAudioSupportedProvider)) return null;
  final offered = currentReadableOf(ref.read(readableRegistryProvider));
  if (offered == null || offered.ownAudio || offered.recording != null) {
    return null;
  }
  final downloads = ref.read(documentAudioDownloadsProvider.notifier);
  final plan = downloads.planOf(offered);
  if (plan.isEmpty) return null;
  final l10n = AppLocalizations.of(host)!;
  final id = offered.id;
  final job = ref.read(documentAudioDownloadsProvider)[id];
  final audio = ref.read(documentAudioProvider(id)).valueOrNull;
  final status = documentAudioStatusOf(audio, plan, offered.segments);
  final mine = ref.read(myVoicesProvider).valueOrNull ?? const <MyVoice>[];
  final voices = documentAudioVoicesLabel(l10n, plan.voices, mine);
  final sharer = ref.read(audioFileSharerProvider);

  final ReadingMenuEntry download;
  if (job != null && job.phase != DocumentAudioJobPhase.failed) {
    download = ReadingMenuEntry(
      key: const Key('reading-more-audio-download'),
      icon: Icons.downloading_rounded,
      label: job.phase == DocumentAudioJobPhase.waiting
          ? l10n.f47P5Waiting
          : l10n.f47P5Downloading(job.percent),
      detail: l10n.f47P5CancelDetail,
      onSelected: () => cancelDocumentAudio(host, ref, id),
    );
  } else if (job != null) {
    download = ReadingMenuEntry(
      key: const Key('reading-more-audio-download'),
      icon: Icons.error_outline_rounded,
      label: l10n.f47P5Failed,
      detail: documentAudioFailureText(l10n, job.failure, mine),
      onSelected: () => unawaited(downloadDocumentAudio(host, ref, offered)),
    );
  } else {
    final length = estimatedAudioLength(l10n, offered.segments);
    final resumable =
        ref.read(documentAudioResumableProvider(id)).valueOrNull ?? false;
    download = switch (status) {
      DocumentAudioStatus.ready => ReadingMenuEntry(
        key: const Key('reading-more-audio-download'),
        icon: Icons.offline_pin_rounded,
        label: l10n.f47P5Ready(formatReadAloudTime(audio!.duration)),
        detail: l10n.f47P5ReadyDetail(voices),
        onSelected: () => unawaited(
          ref.read(readAloudControllerProvider.notifier).open(offered),
        ),
      ),
      DocumentAudioStatus.stale => ReadingMenuEntry(
        key: const Key('reading-more-audio-download'),
        icon: Icons.sync_problem_rounded,
        label: l10n.f47P5Stale,
        detail: l10n.f47P5StaleDetail,
        onSelected: () => unawaited(downloadDocumentAudio(host, ref, offered)),
      ),
      DocumentAudioStatus.none => ReadingMenuEntry(
        key: const Key('reading-more-audio-download'),
        icon: Icons.download_for_offline_outlined,
        label: resumable ? l10n.f47P5DownloadResume : l10n.f47P5Download,
        detail: resumable
            ? l10n.f47P5DownloadResumeDetail(voices, length)
            : l10n.f47P5DownloadDetail(voices, length),
        onSelected: () => unawaited(downloadDocumentAudio(host, ref, offered)),
      ),
    };
  }

  return ReadingMenuGroup([
    download,
    if (sharer != null)
      ReadingMenuEntry(
        key: const Key('reading-more-audio-export'),
        icon: Icons.ios_share_rounded,
        label: l10n.f47P5Export,
        detail: switch (status) {
          DocumentAudioStatus.ready => l10n.f47P5ExportDetail(
            audio!.extension.toUpperCase(),
          ),
          DocumentAudioStatus.stale => l10n.f47P5ExportStale,
          DocumentAudioStatus.none => l10n.f47P5ExportNone,
        },
        onSelected: status == DocumentAudioStatus.ready
            ? () => unawaited(exportDocumentAudio(host, ref, audio!))
            : null,
      ),
    if (audio != null)
      ReadingMenuEntry(
        key: const Key('reading-more-audio-delete'),
        icon: Icons.delete_outline_rounded,
        label: l10n.f47P5Delete,
        detail: l10n.f47P5DeleteDetail,
        destructive: true,
        onSelected: () => unawaited(deleteDocumentAudio(host, ref, audio)),
      ),
  ]);
}

/// Lo que va a durar, estimado, el audio de [segments] a 1×: por las
/// palabras, como el tiempo del reproductor con la voz.
String estimatedAudioLength(
  AppLocalizations l10n,
  List<ReadableSegment> segments,
) {
  final total = ReadingTimeline.of(segments).durationAt(1);
  final minutes = (total.inSeconds / 60).ceil().clamp(1, 1 << 30);
  if (minutes < 60) return l10n.f47P5AboutMinutes(minutes);
  return l10n.f47P5AboutHours(minutes ~/ 60, minutes % 60);
}

/// Con qué voces se genera: la de cada idioma, sin repetir, en el orden en
/// que aparecen, nombradas como en el reproductor ([readAloudVoiceName]); la
/// del teléfono si no hay una elegida.
String documentAudioVoicesLabel(
  AppLocalizations l10n,
  List<NarrationVoice?> voices,
  List<MyVoice> mine,
) {
  final names = <String>[];
  for (final voice in voices) {
    final name = voice == null
        ? l10n.f47P5PhoneVoice
        : readAloudVoiceName(voice, l10n, mine: mine);
    if (!names.contains(name)) names.add(name);
  }
  return switch (names.length) {
    0 => l10n.f47P5PhoneVoice,
    1 => names.single,
    2 => l10n.f47P5VoicesTwo(names[0], names[1]),
    _ => l10n.f47P5VoicesMore(names.first, names.length - 1),
  };
}

/// Por qué no se pudo descargar el audio, en una línea.
String documentAudioFailureText(
  AppLocalizations l10n,
  SpeechAudioException? failure,
  List<MyVoice> mine,
) {
  switch (failure?.failure) {
    case SpeechAudioFailure.voiceMissing:
      final name = _speechVoiceName(l10n, failure?.voiceId, mine);
      return name == null ? l10n.f47P5FailVoiceAny : l10n.f47P5FailVoice(name);
    case SpeechAudioFailure.file:
      return l10n.f47P5FailFile;
    case SpeechAudioFailure.engine || null:
      return l10n.f47P5FailEngine;
  }
}

/// El nombre de la voz de la pieza común [voiceId], si se sabe.
String? _speechVoiceName(
  AppLocalizations l10n,
  String? voiceId,
  List<MyVoice> mine,
) {
  if (voiceId == null) return null;
  final offline = SpeechVoiceIds.offlineIdOf(voiceId);
  if (offline != null) return OfflineVoiceCatalog.byId(offline)?.name;
  if (voiceId.startsWith(myVoicePrefix)) {
    return mine
        .where((voice) => voice.narrationVoice.name == voiceId)
        .firstOrNull
        ?.name;
  }
  final device = SpeechVoiceIds.deviceOf(voiceId);
  if (device == null || device.name.isEmpty) return null;
  return readAloudVoiceName(
    NarrationVoice(name: device.name, locale: device.locale),
    l10n,
    mine: mine,
  );
}

/// La voz sin conexión que faltó en [failure], para ofrecer bajarla.
OfflineVoice? missingOfflineVoiceOf(SpeechAudioException? failure) {
  if (failure?.failure != SpeechAudioFailure.voiceMissing) return null;
  final id = failure?.voiceId;
  final offline = id == null ? null : SpeechVoiceIds.offlineIdOf(id);
  return offline == null ? null : OfflineVoiceCatalog.byId(offline);
}

/// **Descargar el audio** de [document]: con el costo dicho antes si alguna
/// voz es de la nube (`speechAudioApprovalProvider`, decisión F), lo pide a
/// las descargas de toda la app —sigue aunque se cierre el marco— y dice
/// cuándo quedó, con «Escuchar», o por qué no, con «Bajar la voz» si faltó
/// una sin conexión.
Future<void> downloadDocumentAudio(
  BuildContext context,
  WidgetRef ref,
  ReadableDocument document,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final downloads = ref.read(documentAudioDownloadsProvider.notifier);
  final plan = downloads.planOf(document);
  if (plan.isEmpty) return;
  final cost = ref.read(speechAudioRendererProvider).costOf(plan.pieces);
  if (cost != null &&
      !await ref.read(speechAudioApprovalProvider)(context, cost)) {
    return;
  }
  // Lo que se usa al terminar, ya en la mano: el marco puede haberse ido.
  final controller = ref.read(readAloudControllerProvider.notifier);
  final voiceActions = ref.read(offlineVoiceActionsProvider);
  final mine = ref.read(myVoicesProvider).valueOrNull ?? const <MyVoice>[];
  downloads.dismiss(document.id);
  _say(messenger, l10n.f47P5Started(document.title));
  try {
    final audio = await downloads.download(document, plan);
    if (audio == null || !messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showAppSnackBar(
        AppSnackBar(
          content: Text(l10n.f47P5Done(document.title)),
          action: SnackBarAction(
            label: l10n.f47P5Listen,
            onPressed: () => unawaited(controller.open(document)),
          ),
        ),
      );
  } on SpeechAudioException catch (e) {
    if (!messenger.mounted) return;
    final voice = missingOfflineVoiceOf(e);
    messenger
      ..hideCurrentSnackBar()
      ..showAppSnackBar(
        AppSnackBar(
          content: Text(documentAudioFailureText(l10n, e, mine)),
          action: voice == null || voiceActions == null
              ? null
              : SnackBarAction(
                  label: l10n.f47P5GetVoice,
                  onPressed: () => voiceActions.download(voice.package),
                ),
        ),
      );
  }
}

/// Corta la descarga del audio de [documentId]: lo ya generado queda para
/// seguir después.
void cancelDocumentAudio(
  BuildContext context,
  WidgetRef ref,
  String documentId,
) {
  ref.read(documentAudioDownloadsProvider.notifier).cancel(documentId);
  _say(
    ScaffoldMessenger.of(context),
    AppLocalizations.of(context)!.f47P5Cancelled,
  );
}

/// **Exportar audio**: el archivo descargado, con la hoja de compartir del
/// sistema, con el título del documento como nombre.
Future<void> exportDocumentAudio(
  BuildContext context,
  WidgetRef ref,
  DocumentAudio audio,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final sharer = ref.read(audioFileSharerProvider);
  if (sharer == null) return;
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final path = await ref.read(documentAudioStoreProvider).localPathOf(audio);
  if (path == null) return _say(messenger, l10n.f47P5ExportFailed);
  try {
    await sharer(
      path: path,
      fileName: '${sanitizeFileName(audio.title)}.${audio.extension}',
      mimeType: audio.mimeType,
      title: audio.title,
      origin: origin,
    );
    // Lo que falla al compartir se dice, nunca se cae; cerrar la hoja sin
    // elegir no llega acá.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    _say(messenger, l10n.f47P5ExportFailed);
  }
}

/// **Borrar el audio descargado**, después de confirmarlo: solo el audio —su
/// archivo y su ficha—. Si es lo que está sonando, antes se deja de leer.
Future<void> deleteDocumentAudio(
  BuildContext context,
  WidgetRef ref,
  DocumentAudio audio,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final store = ref.read(documentAudioStoreProvider);
  final size = await store.sizeOf(audio);
  if (!context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('document-audio-delete'),
      title: Text(l10n.f47P5DeleteTitle),
      content: Text(
        l10n.f47P5DeleteBody(formatFileSize(size ?? 0, l10n.localeName)),
      ),
      actions: [
        TextButton(
          key: const Key('document-audio-delete-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('document-audio-delete-go'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.f47P5DeleteGo),
        ),
      ],
    ),
  );
  if (!(go ?? false)) return;
  final reading = ref.read(readAloudControllerProvider);
  if (reading.document?.id == audio.documentId &&
      reading.document?.recording != null) {
    await ref.read(readAloudControllerProvider.notifier).close();
  }
  await store.delete(audio.documentId);
  ref.invalidate(documentAudioProvider(audio.documentId));
  _say(messenger, l10n.f47P5Deleted);
}

void _say(ScaffoldMessengerState messenger, String text) {
  if (!messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showAppSnackBar(AppSnackBar(content: Text(text)));
}

/// **La barra de la descarga del audio**, abajo del marco, encima del lugar
/// del reproductor: mientras se genera el audio de lo que se lee, cuánto
/// va con «Cancelar»; si espera a otro, que espera; si falló, por qué, con
/// «Reintentar», «Bajar» la voz que faltó y ✕. Sin descarga de esto, no
/// está.
class ReadingAudioDownloadBar extends ConsumerWidget {
  const ReadingAudioDownloadBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offered = ref.watch(
      readableRegistryProvider.select(currentReadableOf),
    );
    if (offered == null) return const SizedBox.shrink();
    final job = ref.watch(
      documentAudioDownloadsProvider.select((jobs) => jobs[offered.id]),
    );
    if (job == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = job.phase == DocumentAudioJobPhase.failed;
    final mine = ref.watch(myVoicesProvider).valueOrNull ?? const <MyVoice>[];
    final missing = failed ? missingOfflineVoiceOf(job.failure) : null;
    final text = switch (job.phase) {
      DocumentAudioJobPhase.waiting => l10n.f47P5Waiting,
      DocumentAudioJobPhase.running => l10n.f47P5Downloading(job.percent),
      DocumentAudioJobPhase.failed => documentAudioFailureText(
        l10n,
        job.failure,
        mine,
      ),
    };

    return Material(
      key: const Key('reading-audio-bar'),
      color: failed ? scheme.errorContainer : scheme.surfaceContainerHigh,
      // Con la letra al doble, un porqué largo no le quita al texto que se
      // lee más de un tercio de la pantalla: lo demás se desplaza.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height / 3,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    failed
                        ? Icons.error_outline_rounded
                        : Icons.downloading_rounded,
                    size: 20,
                    color: failed ? scheme.onErrorContainer : scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      key: const Key('reading-audio-bar-text'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: failed ? scheme.onErrorContainer : null,
                      ),
                    ),
                  ),
                  if (failed)
                    IconButton(
                      key: const Key('reading-audio-bar-dismiss'),
                      tooltip: l10n.f47P5Dismiss,
                      icon: const Icon(Icons.close_rounded),
                      color: scheme.onErrorContainer,
                      onPressed: () => ref
                          .read(documentAudioDownloadsProvider.notifier)
                          .dismiss(offered.id),
                    ),
                ],
              ),
              if (job.phase == DocumentAudioJobPhase.waiting)
                Padding(
                  padding: const EdgeInsets.only(left: 32, top: 2),
                  child: Text(
                    l10n.f47P5WaitingDetail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (job.phase == DocumentAudioJobPhase.running)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 8, 8, 0),
                  child: LinearProgressIndicator(
                    key: const Key('reading-audio-bar-progress'),
                    value: job.fraction,
                    semanticsLabel: l10n.f47P5Download,
                  ),
                ),
              if (missing != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: VoiceDownloadControls(
                    key: const Key('reading-audio-bar-voice'),
                    voice: offlineVoiceProfiles([missing]).single,
                  ),
                ),
              ],
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: failed
                    ? TextButton(
                        key: const Key('reading-audio-bar-retry'),
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onErrorContainer,
                        ),
                        onPressed: () => unawaited(
                          downloadDocumentAudio(context, ref, offered),
                        ),
                        child: Text(l10n.f47P5Retry),
                      )
                    : TextButton(
                        key: const Key('reading-audio-bar-cancel'),
                        onPressed: () =>
                            cancelDocumentAudio(context, ref, offered.id),
                        child: Text(l10n.f47P5Cancel),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
