import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/voices/downloaded_voices_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_library_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voices_by_language_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo de «Voz y lectura» en Ajustes (F47, paso 3): la biblioteca de voces, la
/// voz elegida para cada idioma y,
/// donde se ofrecen las voces sin conexión, las descargadas para borrarlas;
/// y la Lectura enfocada del reproductor (paso 2). El paso 7 suma el resto
/// de la sección (la velocidad, la tipografía…).
List<Widget> voiceSettingsTiles(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final offline = ref.watch(offlineVoicesAvailableProvider);
  final installed = ref.watch(installedVoicePackagesProvider).valueOrNull;
  final focusedReading = ref.watch(
    narrationSettingsNotifierProvider.select((s) => s.focusedReading),
  );
  return [
    ListTile(
      key: const Key('settings-voice-library'),
      leading: const Icon(Icons.record_voice_over_outlined),
      title: Text(l10n.f47P3LibraryTitle),
      subtitle: Text(l10n.f47P3SettingsLibrarySubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(showVoiceLibrary(context)),
    ),
    ListTile(
      key: const Key('settings-voices-by-language'),
      leading: const Icon(Icons.translate_outlined),
      title: Text(l10n.f47P3SettingsByLanguage),
      subtitle: Text(l10n.f47P3SettingsByLanguageSubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(showVoicesByLanguage(context)),
    ),
    if (offline)
      ListTile(
        key: const Key('settings-downloaded-voices'),
        leading: const Icon(Icons.offline_bolt_outlined),
        title: Text(l10n.f47P3SettingsDownloaded),
        subtitle: installed == null || installed.isNotEmpty
            ? null
            : Text(l10n.f47P3SettingsDownloadedNone),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(showDownloadedVoices(context)),
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
