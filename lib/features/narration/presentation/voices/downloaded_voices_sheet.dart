import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre «Voces descargadas» (F47, paso 3): las voces sin conexión que están
/// en el teléfono, con lo que ocupan, para borrarlas.
Future<void> showDownloadedVoices(BuildContext context) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    builder: (_) => const DownloadedVoicesSheet(),
  );
}

/// El nombre de un paquete bajado: el de sus voces —«Sharvard F, Sharvard M»—
/// o, el de Kokoro, con cuántas trae.
String voicePackageName(OfflineVoicePackage package, AppLocalizations l10n) {
  if (package.family == OfflineVoiceFamily.kokoro) {
    return l10n.f47P3KokoroPackage(kokoroVoiceCount);
  }
  return OfflineVoiceCatalog.voices
      .where((voice) => voice.package == package)
      .map((voice) => voice.name)
      .join(', ');
}

/// Las voces sin conexión bajadas, cada una con su tamaño y «Borrar». Borrar
/// pide confirmar —se vuelve a bajar entera—, y lo que se leía con ella sigue
/// con la del teléfono.
class DownloadedVoicesSheet extends ConsumerWidget {
  const DownloadedVoicesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final installed = ref.watch(installedVoicePackagesProvider).valueOrNull;
    final packages = [
      for (final package in OfflineVoiceCatalog.packages)
        if (installed?.contains(package.id) ?? false) package,
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.f47P3SettingsDownloaded,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            if (installed != null && packages.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Text(
                  l10n.f47P3DownloadedEmpty,
                  key: const Key('downloaded-voices-empty'),
                ),
              ),
            for (final package in packages) _PackageTile(package: package),
          ],
        ),
      ),
    );
  }
}

class _PackageTile extends ConsumerWidget {
  const _PackageTile({required this.package});

  final OfflineVoicePackage package;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    String name,
    int? bytes,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final actions = ref.read(offlineVoiceActionsProvider);
    if (actions == null) return;
    final size = formatFileSize(bytes ?? package.bytes, l10n.localeName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.f47P3DeleteTitle(name)),
        content: Text(l10n.f47P3DeleteBody(size)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.f47P3Cancel),
          ),
          FilledButton(
            key: const Key('downloaded-voice-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.f47P3Delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await actions.delete(package);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.f47P3Deleted(name))));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final name = voicePackageName(package, l10n);
    final actions = ref.watch(offlineVoiceActionsProvider);
    return FutureBuilder<int?>(
      future: actions?.installedBytes(package),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return ListTile(
          key: Key('downloaded-voice-${package.id}'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.offline_bolt_outlined),
          title: Text(name),
          subtitle: bytes == null
              ? null
              : Text(formatFileSize(bytes, l10n.localeName)),
          trailing: TextButton(
            key: Key('downloaded-voice-delete-${package.id}'),
            onPressed: () => unawaited(_delete(context, ref, name, bytes)),
            child: Text(l10n.f47P3Delete),
          ),
        );
      },
    );
  }
}
