import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_speed_sheet.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_voice_face.dart';
import 'package:sinapsis/features/narration/presentation/voices/downloaded_voices_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/clone_voice_screen.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/create_voice_screen.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/voice_cloud_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_library_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_texts.dart';
import 'package:sinapsis/features/narration/presentation/voices/voices_by_language_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las voces de Ajustes › Voz y lectura (F47, pasos 3, 4 y 7b), en el orden
/// en que se piensan:
///
/// 1. **con qué voz se lee**: la biblioteca, con la cara y el nombre de la
///    voz de ahora; la voz elegida para cada idioma; y, donde hay voces sin
///    conexión, las bajadas, con cuántas son y lo que ocupan;
/// 2. **las voces propias**: clonar, crear y la nube para voces, que solo
///    sirve para eso (decisión C).
///
/// Lo de cómo se escucha y cómo se lee —la velocidad, la Lectura enfocada—
/// va en [readAloudSettingsTiles]; la letra y el resaltado son del marco de
/// lectura, y Ajustes los suma después.
List<Widget> voiceSettingsTiles(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final offline = ref.watch(offlineVoicesAvailableProvider);
  final cloud = ref.watch(voiceCloudSettingsProvider);
  return [
    const _VoiceLibraryTile(),
    ListTile(
      key: const Key('settings-voices-by-language'),
      leading: const Icon(Icons.translate_outlined),
      title: Text(l10n.f47P3SettingsByLanguage),
      subtitle: Text(l10n.f47P3SettingsByLanguageSubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(showVoicesByLanguage(context)),
    ),
    if (offline) const _DownloadedVoicesTile(),
    // Las voces propias (F47, paso 4): clonar, crear y la nube para voces,
    // apagada de entrada.
    ListTile(
      key: const Key('settings-clone-voice'),
      leading: const Icon(Icons.mic_none_rounded),
      title: Text(l10n.f47P4CloneTitle),
      subtitle: Text(l10n.f47P4CloneEntry),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(showCloneVoice(context)),
    ),
    ListTile(
      key: const Key('settings-create-voice'),
      leading: const Icon(Icons.auto_awesome_outlined),
      title: Text(l10n.f47P4CreateTitle),
      subtitle: Text(l10n.f47P4CreateEntry),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(showCreateVoice(context)),
    ),
    ListTile(
      key: const Key('settings-voice-cloud'),
      leading: const Icon(Icons.cloud_outlined),
      title: Text(l10n.f47P4CloudTitle),
      subtitle: Text(
        cloud.ready
            ? l10n.f47P4CloudOn
            : cloud.enabled
            ? l10n.f47P4CloudNoKey
            : l10n.f47P4CloudOff,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(showVoiceCloudSheet(context)),
    ),
  ];
}

/// Cómo se escucha, en Ajustes › Voz y lectura (F47, pasos 2 y 7b): la
/// velocidad con que empieza a leer —la misma regla del reproductor— y la
/// Lectura enfocada.
List<Widget> readAloudSettingsTiles(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final focusedReading = ref.watch(
    narrationSettingsNotifierProvider.select((s) => s.focusedReading),
  );
  final speed = ref.watch(
    narrationSettingsNotifierProvider.select((s) => s.speed),
  );
  return [
    // Una sola velocidad, la guardada: con ella empieza a leer todo, y es la
    // misma que cambia el reproductor. Abre su misma hoja, con la regla y los
    // atajos (paso 2), y no una copia.
    ListTile(
      key: const Key('settings-reading-speed'),
      leading: const Icon(Icons.speed_rounded),
      title: Text(l10n.f47P7bSpeedTile),
      subtitle: Text(
        formatReadAloudSpeed(speed, Localizations.localeOf(context).toString()),
        key: const Key('settings-reading-speed-value'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(
        showReadAloudSheet(
          context,
          ReadAloudSpeedSheet(note: l10n.f47P7bSpeedNote),
        ),
      ),
    ),
    // Lectura enfocada (F47, paso 2): el reproductor se achica solo mientras
    // te desplazás.
    SwitchListTile(
      key: const Key('settings-focused-reading'),
      secondary: const Icon(Icons.chrome_reader_mode_outlined),
      title: Text(l10n.f47P2FocusedReading),
      subtitle: Text(l10n.f47P2FocusedReadingHint),
      value: focusedReading,
      onChanged: (enabled) => unawaited(
        ref
            .read(narrationSettingsNotifierProvider.notifier)
            .setFocusedReading(enabled: enabled),
      ),
    ),
  ];
}

/// «Biblioteca de voces», con la voz de ahora: su cara —la misma del
/// reproductor (`ReadAloudVoiceFace`, con la nube si es de la nube)— y «Lee
/// ahora: …», como arriba de la biblioteca. Tocarla la abre.
class _VoiceLibraryTile extends ConsumerWidget {
  const _VoiceLibraryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(currentVoiceProfileProvider);
    return ListTile(
      key: const Key('settings-voice-library'),
      leading: const ExcludeSemantics(child: ReadAloudVoiceFace()),
      title: Text(l10n.f47P3LibraryTitle),
      subtitle: Text(
        current == null
            ? l10n.f47P3NowReadingSystem
            : l10n.f47P3NowReading(voiceName(current, l10n)),
        key: const Key('settings-voice-library-current'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(showVoiceLibrary(context)),
    );
  }
}

/// «Voces descargadas», con cuántas son y lo que ocupan entre todas; la
/// hoja dice cuánto ocupa cada una y las borra.
class _DownloadedVoicesTile extends ConsumerWidget {
  const _DownloadedVoicesTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final summary = ref.watch(downloadedVoicesSummaryProvider).valueOrNull;
    return ListTile(
      key: const Key('settings-downloaded-voices'),
      leading: const Icon(Icons.offline_bolt_outlined),
      title: Text(l10n.f47P3SettingsDownloaded),
      subtitle: switch (summary) {
        null => null,
        (voices: 0, bytes: _) => Text(l10n.f47P3SettingsDownloadedNone),
        (:final voices, :final bytes) => Text(
          l10n.f47P7bDownloadedSummary(
            voices,
            formatFileSize(bytes, l10n.localeName),
          ),
          key: const Key('settings-downloaded-voices-summary'),
        ),
      },
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(showDownloadedVoices(context)),
    );
  }
}
