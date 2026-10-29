import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_badge.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/open_organized_item.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/services/quote_date_locator.dart';
import 'package:sinapsis/features/timeline/presentation/providers/dated_event_providers.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/dated_event_form.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre la ficha de [event], un hecho fechado dentro de un documento (F40):
/// sin salir de la línea de tiempo.
///
/// [context] es el de la pantalla que la abre y no el de la hoja: la hoja deja
/// de existir cuando se cierra, y el formulario de «Editar» o el aviso de
/// «Deshacer» tienen que abrirse después, en un lugar que siga ahí.
Future<void> showDatedEventSheet(BuildContext context, TimelineEvent event) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DatedEventSheet(event: event, screenContext: context),
  );
}

/// La ficha de un hecho fechado: la fecha y el título, la cita con la fecha
/// resaltada, de qué documento sale, y lo que se puede hacer con él —abrir el
/// documento justo en esa cita, editarlo, quitarlo—.
class DatedEventSheet extends ConsumerWidget {
  const DatedEventSheet({
    required this.event,
    required this.screenContext,
    super.key,
  });

  final TimelineEvent event;

  /// Ver [showDatedEventSheet].
  final BuildContext screenContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final excerpt = event.excerpt?.trim();
    final hasQuote = excerpt != null && excerpt.isNotEmpty;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          event.dateLabel,
                          key: const ValueKey('dated-event-date'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (event.isAi) ...[
                        const SizedBox(width: 8),
                        AiBadge(tooltip: l10n.timelineFactMadeByAi),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.title,
                    key: const ValueKey('dated-event-title'),
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (hasQuote) ...[
                    const SizedBox(height: 16),
                    _Quote(event: event, excerpt: excerpt),
                  ],
                  if (hasQuote && !event.hasAnchor) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.timelineFactQuoteLost,
                      key: const ValueKey('dated-event-quote-lost'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _DocumentRow(event: event, screenContext: screenContext),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  key: const ValueKey('dated-event-remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => _remove(context, ref),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.timelineFactRemove),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('dated-event-edit'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l10n.timelineFactEdit),
                ),
                if (event.hasAnchor)
                  FilledButton.icon(
                    key: const ValueKey('dated-event-open'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => _openInDocument(context),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(l10n.timelineFactOpenInDocument),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Lleva al lector justo en la cita, la misma lectura con salto que usan las
  /// tarjetas y las notas extraídas. Sin ancla no se ofrece (ver el botón).
  ///
  /// La cita de un hecho de un documento procesado está en su fuente (F41,
  /// paso 6): se abre el original, en su lugar.
  void _openInDocument(BuildContext context) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    unawaited(
      router.push(
        RoutePaths.reading(
          event.quoteItemId ?? event.itemId,
          start: event.startOffset,
          end: event.endOffset,
        ),
      ),
    );
  }

  /// Cierra la ficha y abre el formulario con el hecho. Guardar lo adopta: un
  /// hecho que puso la IA y la persona corrigió pasa a ser suyo.
  void _edit(BuildContext context) {
    Navigator.of(context).pop();
    if (!screenContext.mounted) return;
    unawaited(showDatedEventForm(screenContext, editing: event));
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    // Lo que hace falta después de cerrar la hoja se toma antes: su `ref` y
    // su contexto dejan de servir cuando se va.
    final repository = ref.read(datedEventRepositoryProvider);
    final messenger = ScaffoldMessenger.of(screenContext);
    final navigator = Navigator.of(context);

    final id = event.datedEventId;
    if (id == null) return;
    final result = await repository.remove(id);
    final failure = result.getLeft().toNullable();
    if (failure != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
      return;
    }
    final removal = result.getRight().toNullable()!;
    // Si la ficha ya se cerró sola (se tocó afuera mientras se quitaba), no hay
    // nada que cerrar: un `pop` sacaría otra pantalla.
    if (context.mounted) navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        AppSnackBar(
          content: Text(l10n.timelineFactRemoved(event.title)),
          action: SnackBarAction(
            label: l10n.timelineFactUndo,
            onPressed: () => unawaited(repository.undoRemove(removal)),
          ),
        ),
      );
  }
}

/// La cita del hecho, con la fecha resaltada: en negrita y con fondo, para que
/// no dependa del color.
class _Quote extends StatelessWidget {
  const _Quote({required this.event, required this.excerpt});

  final TimelineEvent event;
  final String excerpt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final match = locateEventDate(excerpt, date: event.date, end: event.end);
    final base = theme.textTheme.bodyLarge;

    final span = match == null
        ? TextSpan(text: excerpt, style: base)
        : TextSpan(
            style: base,
            children: [
              TextSpan(text: excerpt.substring(0, match.start)),
              TextSpan(
                text: excerpt.substring(match.start, match.end),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              TextSpan(text: excerpt.substring(match.end)),
            ],
          );

    return Container(
      key: const ValueKey('dated-event-quote'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: SelectableText.rich(span),
    );
  }
}

/// De qué documento sale: tocarlo abre su detalle.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.event, required this.screenContext});

  final TimelineEvent event;
  final BuildContext screenContext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: l10n.timelineFactFromDocument(event.documentTitle),
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('dated-event-document'),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.of(context).pop();
          if (screenContext.mounted) {
            unawaited(openOrganizedItem(screenContext, event.itemId));
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(
                event.sourceKind.icon,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  event.documentTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
