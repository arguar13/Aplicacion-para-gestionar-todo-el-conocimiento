import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_design_sheet.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_style_gallery.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_content.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_options.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/infographic_export.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/infographic_kind_providers.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los botones de la infografía en la barra del visor: «Cambiar el estilo» y
/// «Guardar como imagen». El PDF va por «Descargar» del ⋮, que pregunta.
List<Widget> infographicViewerActions(
  BuildContext context,
  StudyCreation creation,
) => [
  InfographicStyleButton(creation: creation),
  InfographicSaveImageButton(creation: creation),
];

/// «Cambiar el estilo»: la hoja de diseño de la infografía —estilo,
/// composición, paleta, letra, orientación, detalle, íconos y fondo— con la
/// galería entera de estilos a un toque. Cada cambio se ve enseguida en la
/// lámina de atrás, y al cerrar se guarda en las opciones de la creación: el
/// contenido no se toca y la IA no se vuelve a llamar (decisión G).
class InfographicStyleButton extends ConsumerWidget {
  const InfographicStyleButton({required this.creation, super.key});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const Key('infographic-change-style-action'),
      tooltip: l10n.f43IgChangeStyle,
      icon: const Icon(Icons.palette_outlined),
      onPressed: () => unawaited(openInfographicDesign(context, ref, creation)),
    );
  }
}

/// Abre la hoja de diseño de [creation] y, al cerrarla, guarda lo elegido.
Future<void> openInfographicDesign(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final content = InfographicContent.decode(creation.content);
  final saved = infographicDesignOf(creation.options);
  final live = infographicLiveDesignProvider(creation.id);
  final notifier = ref.read(live.notifier)..state ??= saved;
  final before = notifier.state!;
  final illustrations = InfographicIllustrations.of(content.sheet);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final design = ref.watch(live) ?? saved;
        final images =
            ref.watch(infographicImagesProvider(illustrations)).valueOrNull ??
            const <String, ImageProvider>{};
        final resolver = infographicResolver(images);
        void choose(InfographicDesign chosen) =>
            ref.read(live.notifier).state = chosen;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: InfographicDesignSheet(
            sheet: content.sheet,
            design: design,
            illustrations: resolver,
            onChanged: choose,
            onChangeStyle: () => unawaited(
              _openGallery(
                context,
                ref,
                creationId: creation.id,
                content: content,
              ),
            ),
          ),
        );
      },
    ),
  );

  // El visor pudo cerrarse mientras tanto (la creación se volvió a generar
  // desde otro lado): entonces no hay nada que guardar sobre ella.
  if (!context.mounted) return;
  final chosen = ref.read(live);
  if (chosen == null || chosen == before) return;
  await ref
      .read(studyCreationRepositoryProvider)
      .amend(
        creation.id,
        options: withInfographicDesign(creation.options, chosen),
      );
}

/// La galería de los dieciocho estilos, en sus dos familias, con la lámina
/// de verdad en cada muestra: elegir uno la cierra y vuelve a la hoja.
Future<void> _openGallery(
  BuildContext context,
  WidgetRef ref, {
  required String creationId,
  required InfographicContent content,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => Consumer(
    builder: (context, ref, _) {
      final l10n = AppLocalizations.of(context)!;
      final theme = Theme.of(context);
      final live = infographicLiveDesignProvider(creationId);
      final design = ref.watch(live) ?? const InfographicDesign();
      final images =
          ref
              .watch(
                infographicImagesProvider(
                  InfographicIllustrations.of(content.sheet),
                ),
              )
              .valueOrNull ??
          const <String, ImageProvider>{};
      return Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: Column(
            key: const Key('infographic-style-gallery-sheet'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.f43InfoDesignStyle,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: l10n.f43InfoDesignClose,
                      style: IconButton.styleFrom(
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        foregroundColor: theme.colorScheme.onSurface,
                        shape: const CircleBorder(),
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InfographicStyleGallery(
                  sheet: content.sheet,
                  design: design,
                  illustrations: infographicResolver(images),
                  onChanged: (chosen) {
                    ref.read(live.notifier).state = chosen;
                    Navigator.of(context).maybePop();
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  ),
);

/// «Guardar como imagen»: la lámina en PNG, al doble de su tamaño, con el
/// diseño que se ve, donde la persona elija.
class InfographicSaveImageButton extends ConsumerStatefulWidget {
  const InfographicSaveImageButton({required this.creation, super.key});

  final StudyCreation creation;

  @override
  ConsumerState<InfographicSaveImageButton> createState() =>
      _InfographicSaveImageButtonState();
}

class _InfographicSaveImageButtonState
    extends ConsumerState<InfographicSaveImageButton> {
  var _busy = false;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final creation = widget.creation;
    setState(() => _busy = true);
    try {
      final file = await exportInfographic(
        ref,
        creation,
        format: InfographicFileFormat.png,
        title: studyCreationTitle(l10n, creation),
        design: ref.read(infographicLiveDesignProvider(creation.id)),
      );
      final path = await ref
          .read(fileSaverProvider)
          .saveFile(fileName: file.fileName, bytes: file.bytes);
      // Cerrar el diálogo sin elegir no es un error: no se dice nada.
      if (path != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(l10n.f43StudioDownloaded(file.fileName))),
          );
      }
      // Lo que falla al dibujar o al guardar se dice en una línea, como en
      // las demás exportaciones.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.f43StudioActionFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const Key('infographic-save-image'),
      tooltip: l10n.f43IgSaveImage,
      onPressed: _busy ? null : () => unawaited(_save()),
      icon: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.image_outlined),
    );
  }
}
