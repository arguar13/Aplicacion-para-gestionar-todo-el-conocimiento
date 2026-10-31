import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_player_extent.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// **El lugar del reproductor**, abajo del marco de lectura (F47, paso 1).
///
/// El reproductor es uno solo en toda la app: el anclado del paso 2
/// (`ReadAloudAnchoredPlayer`), que `ReadAloudOverlay` pone encima de todo,
/// también del marco. Este lugar no dibuja otro:
///
/// - **sin nada sonando**, «Escuchar», que lee lo que se ve —el mismo
///   documento que ofrecía el botón flotante, que en el marco no va—;
/// - **sonando**, abierto o achicado, deja libre lo que ocupa el reproductor
///   anclado (`readAloudPlayerExtentProvider`, su `resting`: el de la forma
///   elegida, sin el achicarse pasajero de la Lectura enfocada), así no tapa
///   lo último que se lee.
///
/// Respeta el borde seguro de abajo.
class ReadingPlayerSlot extends ConsumerWidget {
  const ReadingPlayerSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(readAloudControllerProvider.select((s) => s.panel));
    if (panel != ReadAloudPanel.hidden) {
      final reserved = ref.watch(
        readAloudPlayerExtentProvider.select((extent) => extent.resting),
      );
      return SizedBox(key: const Key('reading-player-slot'), height: reserved);
    }

    final offered = ref.watch(
      readableRegistryProvider.select(currentReadableOf),
    );
    if (offered == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(readAloudControllerProvider.notifier);
    return SafeArea(
      key: const Key('reading-player-slot'),
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Center(
          child: FilledButton.tonalIcon(
            key: const Key('reading-listen'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(200, 48),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.headphones_rounded),
            label: Text(l10n.f47P1Listen),
            onPressed: () => unawaited(controller.open(offered)),
          ),
        ),
      ),
    );
  }
}
