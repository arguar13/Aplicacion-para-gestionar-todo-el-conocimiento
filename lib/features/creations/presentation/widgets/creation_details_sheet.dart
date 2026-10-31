import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_customize_sheet.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_kind_icon.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_source_chips.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Ver petición y fuentes» de una creación (como en NotebookLM): con qué se
/// pidió —las opciones de la hoja con sus nombres, la descripción, el tema,
/// el idioma—, con qué modelo, cuándo, y sus fuentes como fichas tocables
/// (M6).
Future<void> showCreationDetails(
  BuildContext context,
  StudyCreation creation,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (context) => CreationDetailsSheet(creation: creation),
);

/// Lo pedido de [options] con los nombres de la hoja de [spec]: «Duración:
/// Corta», «Tipos de pregunta: Opción única, Respuesta breve»…, y lo de sus
/// opciones dibujadas a mano como lo dice su tipo
/// ([CreationKindSpec.requestLines]). Lo que esta versión no conoce no se
/// muestra.
List<(String, String)> creationRequestLines(
  AppLocalizations l10n,
  CreationKindSpec spec,
  Map<String, Object?> options,
) {
  String? labelOf(List<CreationChoice> choices, Object? value) =>
      choices.where((c) => c.value == value).firstOrNull?.label(l10n);
  final lines = <(String, String)>[];
  for (final option in spec.options) {
    if (!options.containsKey(option.key) || !option.isVisible(options)) {
      continue;
    }
    final value = options[option.key];
    final shown = switch (option) {
      final CreationChoiceOption o => labelOf(o.choices, value),
      final CreationMultiChoiceOption o =>
        value is List
            ? [for (final v in value) ?labelOf(o.choices, v)].join(', ')
            : null,
      CreationToggleOption() =>
        value == true ? l10n.f43StudioYes : l10n.f43StudioNo,
      CreationTextOption() => value is String ? value.trim() : null,
    };
    if (shown == null || shown.isEmpty) continue;
    lines.add((option.label(l10n), shown));
  }
  // Las dibujadas a mano (un carrusel de estilos), como las dice su tipo.
  for (final (label, value)
      in spec.requestLines?.call(l10n, options) ?? const <(String, String)>[]) {
    if (value.trim().isNotEmpty) lines.add((label, value.trim()));
  }
  for (final (key, label) in [
    (CreationOptionKeys.description, l10n.f43StudioDescribe),
    (CreationOptionKeys.topic, spec.topic?.label(l10n) ?? l10n.f43StudioTopic),
  ]) {
    final value = options[key];
    if (value is String && value.trim().isNotEmpty) {
      lines.add((label, value.trim()));
    }
  }
  return lines;
}

class CreationDetailsSheet extends ConsumerWidget {
  const CreationDetailsSheet({required this.creation, super.key});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spec = ref.watch(creationKindRegistryProvider).of(creation.kind);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final request = creationRequestLines(l10n, spec, creation.options);
    final language =
        kCreationLanguages
            .where((l) => l.$1 == creation.languageCode)
            .firstOrNull
            ?.$2 ??
        creation.languageCode;
    final created =
        '${DateFormat.yMMMd(locale).format(creation.createdAt.toLocal())} · '
        '${DateFormat.Hm(locale).format(creation.createdAt.toLocal())}';

    Widget line(String label, String value, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        key: const Key('creation-details-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
            child: Row(
              children: [
                CreationKindIcon(spec: spec, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.f43StudioDetailsTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        studyCreationTitle(l10n, creation),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                CreationCloseButton(tooltip: l10n.f43StudioClose),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CreationSectionLabel(l10n.f43StudioDetailsRequest),
                  line(
                    l10n.f43StudioDetailsLanguage,
                    language,
                    key: const Key('creation-details-language'),
                  ),
                  if (request.isEmpty)
                    line(spec.label(l10n), l10n.f43StudioDetailsDefaults)
                  else
                    for (final (label, value) in request) line(label, value),
                  if (creation.modelName case final model?)
                    line(l10n.f43StudioDetailsModel, model),
                  line(l10n.f43StudioDetailsCreated, created),
                  CreationSectionLabel(l10n.f43StudioSourcesTitle),
                  CreationSourceChips(creation: creation),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
