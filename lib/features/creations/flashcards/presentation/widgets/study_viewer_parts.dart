/// Las piezas que comparten los visores del mazo y del cuestionario (F43,
/// paso 8): el dibujo de cada tarjeta o pregunta, el aviso de por qué no hubo
/// ilustraciones con IA, el botón de descargar y los colores de acertar y
/// errar.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/app_semantic_colors.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/creations/design/creation_art.dart';
import 'package:sinapsis/features/creations/design/creation_icons.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/creation_actions.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_illustration_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las opciones de fábrica de [options] con «Incluir imágenes» como lo que
/// es acá: ilustraciones con IA (decisión H), así la hoja muestra «Con tu IA
/// actual» con lo que costarían y [hint] dice qué pasa si no se puede.
List<CreationOptionSpec> withIllustratedImages(
  List<CreationOptionSpec> options, {
  required CreationText hint,
}) => [
  for (final option in options)
    if (option is CreationToggleOption &&
        option.key == CreationOptionValues.images)
      CreationToggleOption(
        key: option.key,
        label: option.label,
        hint: hint,
        initial: option.initial,
        illustrations: true,
        visibleWhen: option.visibleWhen,
      )
    else
      option,
];

/// Si al crear [creation] se pidió «Incluir imágenes».
bool studyCreationWantsImages(StudyCreation creation) =>
    creation.options[CreationOptionValues.images] == true;

/// Los colores de los dibujos de la app sobre el tema de ahora, con el color
/// de su tipo.
CreationPalette studyArtPalette(BuildContext context, Color accent) {
  final scheme = Theme.of(context).colorScheme;
  return CreationPalette(
    background: scheme.surfaceContainerHighest,
    surface: scheme.surfaceContainerHigh,
    primary: accent,
    secondary: scheme.tertiary,
    accent: scheme.primary,
    text: scheme.onSurface,
    muted: scheme.onSurfaceVariant,
  );
}

/// El dibujo de una tarjeta o una pregunta: su ilustración con IA si salió
/// (leída del almacén por su [reference]); si se pidieron y esta no tiene, o
/// el archivo ya no está, el dibujo de la app con su ícono —siempre el mismo
/// para el mismo [seed]—.
class StudyItemPicture extends ConsumerWidget {
  const StudyItemPicture({
    required this.reference,
    required this.icon,
    required this.seed,
    required this.accent,
    required this.semanticLabel,
    this.style = CreationArtStyle.geometric,
    this.maxHeight = 150,
    super.key,
  });

  final String? reference;
  final String? icon;
  final int seed;
  final Color accent;
  final String semanticLabel;
  final CreationArtStyle style;
  final double maxHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = reference;
    final bytes = path == null
        ? null
        : ref.watch(creationIllustrationBytesProvider(path)).valueOrNull;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 320),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: bytes != null
                ? Image.memory(
                    bytes,
                    key: const Key('study-item-image'),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  )
                : CreationArt(
                    key: const Key('study-item-art'),
                    style: style,
                    palette: studyArtPalette(context, accent),
                    seed: seed,
                    icon: CreationIcons.resolve(icon),
                  ),
          ),
        ),
      ),
    );
  }
}

/// «Sin ilustraciones con IA: …» con el porqué preciso, arriba del visor.
class StudyIllustrationNotice extends StatelessWidget {
  const StudyIllustrationNotice({
    required this.failure,
    required this.account,
    required this.message,
    super.key,
  });

  final ImageFailure failure;
  final String? account;

  /// El texto con el motivo puesto («Sin ilustraciones con IA: {reason}…»).
  final String Function(String reason) message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const Key('study-illustration-notice'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.image_not_supported_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message(illustrationReason(l10n, failure, account: account)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Descargar» en la barra del visor: lo mismo que en el menú de la fila, con
/// el archivo que arma el tipo.
class StudyDownloadButton extends ConsumerWidget {
  const StudyDownloadButton({required this.creation, super.key});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const Key('study-download'),
      tooltip: l10n.f43CardsDownload,
      icon: const Icon(Icons.file_download_outlined),
      onPressed: () => unawaited(
        runCreationAction(context, ref, creation, CreationAction.download),
      ),
    );
  }
}

/// El verde de acertar y el rojo de errar de este tema, con lo que se escribe
/// encima: el verde es el de «éxito» de la app (`AppSemanticColors`), que no
/// depende del color principal del tema —en un tema verde, el principal no
/// diría «bien»—.
({Color good, Color onGood, Color bad, Color onBad}) studyVerdictColors(
  BuildContext context,
) {
  final theme = Theme.of(context);
  final semantic =
      theme.extension<AppSemanticColors>() ??
      (theme.brightness == Brightness.dark
          ? AppSemanticColors.dark
          : AppSemanticColors.light);
  final scheme = theme.colorScheme;
  return (
    good: CreationContrast.ensure(semantic.success, scheme.surface, minimum: 3),
    onGood: semantic.onSuccess,
    bad: scheme.error,
    onBad: scheme.onError,
  );
}

/// Una opción de descarga en la hoja de elegir formato.
@immutable
class StudyExportChoice<T> {
  const StudyExportChoice({
    required this.value,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final T value;
  final IconData icon;
  final String title;
  final String subtitle;
}

/// La hoja de «Descargar» con los formatos: devuelve el elegido, o `null` si
/// se cerró.
Future<T?> showStudyExportChoices<T>(
  BuildContext context, {
  required String title,
  required List<StudyExportChoice<T>> choices,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            for (final choice in choices)
              ListTile(
                key: Key('study-export-${choice.value}'),
                leading: Icon(choice.icon),
                title: Text(choice.title),
                subtitle: Text(choice.subtitle),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onTap: () => Navigator.of(context).pop(choice.value),
              ),
          ],
        ),
      ),
    );
  },
);
