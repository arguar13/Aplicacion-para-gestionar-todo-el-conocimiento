import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';
import 'package:sinapsis/features/creations/report/presentation/providers/report_providers.dart';
import 'package:sinapsis/features/creations/report/presentation/report_labels.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La plantilla de un informe en la hoja de personalizar (F43, punto 4 del
/// plan), como las tarjetas de formato de NotebookLM: las cuatro con nombre,
/// cada una con su ícono y lo que trae, y «Crear la tuya ✎». Elegida la
/// propia, abajo, el campo para describirla —lo último que se escribió
/// vuelve solo, con lo último elegido de la hoja— y «Las que ya usaste»,
/// para volver a usar una con un toque.
///
/// Lo elegido va a las opciones de la creación
/// (`CreationOptionValues.template` y `.customTemplate`) por
/// [CreationOptionsContext.set]: lo que lee el generador.
class ReportTemplatePicker extends ConsumerStatefulWidget {
  const ReportTemplatePicker({required this.options, super.key});

  final CreationOptionsContext options;

  @override
  ConsumerState<ReportTemplatePicker> createState() =>
      _ReportTemplatePickerState();
}

class _ReportTemplatePickerState extends ConsumerState<ReportTemplatePicker> {
  late final _custom = TextEditingController(
    text: reportCustomTemplateOf(widget.options.options),
  );
  final _focus = FocusNode();

  @override
  void dispose() {
    _custom.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _choose(ReportTemplate template) {
    widget.options.set(CreationOptionValues.template, template.value);
    if (template == ReportTemplate.custom) {
      // Después de dibujar el campo: recién ahí existe.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _write(String text) =>
      widget.options.set(CreationOptionValues.customTemplate, text);

  void _reuse(String text) {
    _custom.text = text;
    _write(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final chosen = ReportTemplate.of(widget.options.options);
    final custom = chosen == ReportTemplate.custom;
    final used = custom
        ? ref.watch(reportUsedCustomTemplatesProvider).valueOrNull ??
              const <String>[]
        : const <String>[];
    final scaler = MediaQuery.textScalerOf(context);

    return Column(
      key: const Key('report-template-picker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CreationSectionLabel(l10n.f43StudioOptTemplate),
        LayoutBuilder(
          builder: (context, constraints) {
            // De a dos mientras cada una tenga lugar para su nombre; con la
            // letra muy grande o en un teléfono angosto, de a una.
            const gap = 10.0;
            final columns = constraints.maxWidth >= 2 * scaler.scale(150) + gap
                ? 2
                : 1;
            const templates = ReportTemplate.values;
            final rows = <Widget>[];
            for (var i = 0; i < templates.length; i += columns) {
              final row = templates.sublist(
                i,
                math.min(i + columns, templates.length),
              );
              if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
              rows.add(
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (j, template) in row.indexed) ...[
                        if (j > 0) const SizedBox(width: gap),
                        Expanded(
                          child: _TemplateTile(
                            template: template,
                            selected: template == chosen,
                            onTap: () => _choose(template),
                          ),
                        ),
                      ],
                      // La última fila, sola: la tarjeta guarda su ancho.
                      if (row.length < columns) ...[
                        const SizedBox(width: gap),
                        const Expanded(child: SizedBox.shrink()),
                      ],
                    ],
                  ),
                ),
              );
            }
            return Column(mainAxisSize: MainAxisSize.min, children: rows);
          },
        ),
        if (custom) ...[
          CreationSectionLabel(l10n.f43ReportCustomLabel),
          TextField(
            key: const Key('report-custom-template'),
            controller: _custom,
            focusNode: _focus,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: l10n.f43StudioOptOwnTemplateHint,
              helperText: _custom.text.trim().isEmpty
                  ? l10n.f43ReportCustomEmpty
                  : null,
              helperMaxLines: 2,
              prefixIcon: const Icon(Icons.edit_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onChanged: _write,
          ),
          if (used.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              l10n.f43ReportCustomUsed,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            for (final (i, text) in used.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Semantics(
                  button: true,
                  onTap: () => setState(() => _reuse(text)),
                  label: l10n.f43ReportCustomUse(text),
                  excludeSemantics: true,
                  child: Material(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: ValueKey('report-custom-used-$i'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _reuse(text)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.history,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ],
    );
  }
}

/// Una plantilla para elegir: su ícono del color del informe, su nombre y lo
/// que trae; elegida, con su borde y su ✓.
class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final ReportTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = defaultCreationKindSpec(
      StudyCreationKind.report,
    ).accent.of(context);
    final custom = template == ReportTemplate.custom;
    final name = custom
        ? l10n.f43ReportTemplateCustom
        : l10n.reportTemplateName(template);
    return Semantics(
      button: true,
      onTap: onTap,
      selected: selected,
      label: '$name. ${l10n.reportTemplateHint(template)}',
      excludeSemantics: true,
      child: Material(
        key: ValueKey('report-template-${template.value}'),
        color: selected
            ? Color.alphaBlend(
                accent.withValues(alpha: 0.12),
                scheme.surfaceContainerHigh,
              )
            : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? accent : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(reportTemplateIcon(template), color: accent),
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle, size: 20, color: accent),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  custom ? '$name ✎' : name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.reportTemplateHint(template),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
