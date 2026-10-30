import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/voices/downloaded_voices_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_library_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo de «Voz y lectura» en Ajustes (F47, paso 3): la biblioteca de voces y,
/// donde se ofrecen las voces sin conexión, las descargadas para borrarlas.
/// El paso 7 suma el resto de la sección (la velocidad, Lectura enfocada…).
List<Widget> voiceSettingsTiles(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final offline = ref.watch(offlineVoicesAvailableProvider);
  final installed = ref.watch(installedVoicePackagesProvider).valueOrNull;
  return [
    ListTile(
      key: const Key('settings-voice-library'),
      leading: const Icon(Icons.record_voice_over_outlined),
      title: Text(l10n.f47P3LibraryTitle),
      subtitle: Text(l10n.f47P3SettingsLibrarySubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(showVoiceLibrary(context)),
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
  ];
}
