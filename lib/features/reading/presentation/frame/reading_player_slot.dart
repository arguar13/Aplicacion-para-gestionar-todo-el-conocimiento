import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_player.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_speed_sheet.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_library_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// **El lugar del reproductor**, abajo del marco de lectura (F47, paso 1).
///
/// El reproductor anclado de toda la app es del paso 2; hasta que llegue, acá
/// va el de hoy, el mismo motor (`readAloudControllerProvider`), sin el botón
/// flotante:
///
/// - **sin nada sonando**, «Escuchar», que lee lo que se ve —el mismo
///   documento que ofrecía el botón flotante, desde lo que se mira—;
/// - **sonando**, el mini reproductor de hoy (`ReadAloudPlayer`), con su
///   velocidad, su voz y «Leer: Todo · Resumen · Síntesis · Palabras clave»,
///   sea de este documento o de otro que venía sonando;
/// - **achicado**, una línea con el botón de hoy —su anillo de avance— y el
///   título, que lo vuelve a abrir;
/// - con [ownPlayer], el reproductor propio de [ownReadableId] —el de los
///   visores de extraer, con su avance que se arrastra— cuando suena eso.
///
/// Respeta el borde seguro de abajo.
class ReadingPlayerSlot extends ConsumerStatefulWidget {
  const ReadingPlayerSlot({this.ownPlayer, this.ownReadableId, super.key});

  final WidgetBuilder? ownPlayer;
  final String? ownReadableId;

  @override
  ConsumerState<ReadingPlayerSlot> createState() => _ReadingPlayerSlotState();
}

class _ReadingPlayerSlotState extends ConsumerState<ReadingPlayerSlot> {
  /// El título de lo último que sonó: mientras se cierra, el estado ya no lo
  /// tiene.
  String _title = '';

  void _openSheet(Widget sheet) {
    final still = MediaQuery.disableAnimationsOf(context);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
        builder: (_) => sheet,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (panel, playing, title, reading) = ref.watch(
      readAloudControllerProvider.select(
        (s) => (s.panel, s.playing, s.document?.title, s.document?.id),
      ),
    );
    if (title != null) _title = title;
    final controller = ref.read(readAloudControllerProvider.notifier);

    final Widget child;
    switch (panel) {
      case ReadAloudPanel.hidden:
        final offered = ref.watch(
          readableRegistryProvider.select(currentReadableOf),
        );
        if (offered == null) return const SizedBox.shrink();
        child = Center(
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
        );
      case ReadAloudPanel.minimized:
        child = _MinimizedLine(
          title: _title,
          playing: playing,
          onExpand: controller.expand,
        );
      case ReadAloudPanel.expanded:
        final own = widget.ownPlayer;
        if (own != null && reading == widget.ownReadableId) {
          // El propio va de borde a borde, con su borde seguro.
          return KeyedSubtree(
            key: const Key('reading-player-slot'),
            child: own(context),
          );
        }
        child = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ReadAloudPlayer(
            title: _title,
            onSpeed: () => _openSheet(const ReadAloudSpeedSheet()),
            // La biblioteca de voces (F47, paso 3), como en el lector flotante.
            onVoice: () => unawaited(showVoiceLibrary(context)),
          ),
        );
    }

    return SafeArea(
      key: const Key('reading-player-slot'),
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Center(child: child),
      ),
    );
  }
}

/// El reproductor achicado: el botón de hoy, con su anillo de cuánto leyó,
/// y el título; tocarlo lo vuelve a abrir.
class _MinimizedLine extends StatelessWidget {
  const _MinimizedLine({
    required this.title,
    required this.playing,
    required this.onExpand,
  });

  final String title;
  final bool playing;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Material(
        key: const Key('reading-player-minimized'),
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(32),
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: onExpand,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                ReadAloudButton(
                  reading: true,
                  playing: playing,
                  onPressed: onExpand,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.keyboard_arrow_up_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
