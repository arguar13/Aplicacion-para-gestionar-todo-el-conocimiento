import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/extract/presentation/providers/extract_providers.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/presentation/providers/reader_font_scale_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los botones propios de los visores de extraer en la barra de arriba (F43,
/// paso 7): **Escuchar** y las opciones de **Lectura**.
List<Widget> extractViewerActions(
  BuildContext context,
  StudyCreation creation,
) => [
  ExtractListenButton(creation: creation),
  ExtractReadingButton(creation: creation),
];

/// «Escuchar» (M8): abre el modo escuchar —el reproductor grande de abajo—
/// con lo que muestra el visor, en su orden. Escuchando, lo cierra. Apagado
/// mientras no hay nada que leer, o mientras un libro se parte.
class ExtractListenButton extends ConsumerWidget {
  const ExtractListenButton({required this.creation, super.key});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final id = extractReadableId(creation.id);
    final segments = ref.watch(extractSegmentsProvider(creation.id));
    final listening = ref.watch(
      readAloudControllerProvider.select(
        (s) => s.document?.id == id && s.panel != ReadAloudPanel.hidden,
      ),
    );
    final controller = ref.read(readAloudControllerProvider.notifier);
    final empty = segments == null || segments.isEmpty;
    return IconButton(
      key: const Key('extract-listen'),
      tooltip: listening
          ? l10n.f43TextListenStop
          : empty
          ? l10n.f43TextListenNothing
          : l10n.f43TextListen,
      isSelected: listening,
      selectedIcon: const Icon(Icons.headset_off_outlined),
      icon: const Icon(Icons.headphones_outlined),
      onPressed: listening
          ? () => unawaited(controller.close())
          : empty
          ? null
          : () => unawaited(
              controller.open(
                ReadableDocument(
                  id: id,
                  title: studyCreationTitle(l10n, creation),
                  segments: segments,
                ),
                fromSegment: 0,
              ),
            ),
    );
  }
}

/// «Lectura»: abre la hoja con «Resaltar las palabras clave» y el tamaño de
/// la letra.
class ExtractReadingButton extends StatelessWidget {
  const ExtractReadingButton({required this.creation, super.key});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const Key('extract-reading'),
      tooltip: l10n.f43TextReadingTooltip,
      icon: const Icon(Icons.text_format_rounded),
      onPressed: () => unawaited(showExtractReadingSheet(context, creation)),
    );
  }
}

/// La hoja de «Lectura» de un visor de extraer.
Future<void> showExtractReadingSheet(
  BuildContext context,
  StudyCreation creation,
) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: ExtractReadingSheet(creation: creation),
    ),
  );
}

/// Lo de adentro de la hoja de «Lectura».
///
/// **«Resaltar las palabras clave»** (M8), prendido por defecto, es **la misma
/// preferencia** que el «mostrar por defecto» de las palabras clave del
/// original (M5, `processedKeywordsShownProvider`), guardada por documento:
/// cambiarla acá la cambia allá, y al revés. Con varios documentos se prende
/// o se apaga en todos —está prendida si en todos lo está—; cada apartado del
/// visor sigue mostrando lo de su documento.
class ExtractReadingSheet extends ConsumerWidget {
  const ExtractReadingSheet({required this.creation, super.key});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ids = creation.sourceIds;
    final shown =
        ids.isNotEmpty &&
        ids.every((id) => ref.watch(processedKeywordsShownProvider(id)));
    final scale = ref.watch(readerFontScaleNotifierProvider);
    final fonts = ref.read(readerFontScaleNotifierProvider.notifier);
    final pink = StudyPalette.of(theme.brightness).keyword;

    return Column(
      key: const Key('extract-reading-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.f43TextReadingTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            CreationCloseButton(tooltip: l10n.f43TextClose),
          ],
        ),
        const SizedBox(height: 12),
        Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            key: const Key('extract-keywords-toggle'),
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
            secondary: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: pink, shape: BoxShape.circle),
              child: const Icon(
                Icons.key_outlined,
                size: 20,
                color: StudyPalette.ink,
              ),
            ),
            title: Text(l10n.f43TextKeywordsToggle),
            subtitle: Text(
              ids.length > 1
                  ? l10n.f43TextKeywordsToggleMany(ids.length)
                  : l10n.f43TextKeywordsToggleOne,
            ),
            value: shown,
            onChanged: ids.isEmpty
                ? null
                : (value) async {
                    for (final id in ids) {
                      await ref
                          .read(processedOriginalHiddenProvider(id).notifier)
                          .setHidden(StudyMarkKind.keyword, hidden: !value);
                    }
                  },
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Icon(Icons.format_size_rounded, color: scheme.onSurfaceVariant),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    l10n.f43TextFontSize,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                IconButton(
                  key: const Key('extract-font-smaller'),
                  tooltip: l10n.documentReaderSmallerText,
                  onPressed: scale <= ReaderFontScaleNotifier.min
                      ? null
                      : () => unawaited(fonts.decrease()),
                  icon: const Icon(Icons.text_decrease),
                ),
                IconButton(
                  key: const Key('extract-font-larger'),
                  tooltip: l10n.documentReaderLargerText,
                  onPressed: scale >= ReaderFontScaleNotifier.max
                      ? null
                      : () => unawaited(fonts.increase()),
                  icon: const Icon(Icons.text_increase),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
