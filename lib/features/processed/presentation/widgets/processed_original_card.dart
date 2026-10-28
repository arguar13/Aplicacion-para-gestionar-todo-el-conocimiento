import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La copia del original en el documento procesado (F41, decisión H): qué es,
/// cuánto ocupa, cuándo se copió y «Ver el original», que la abre en su visor
/// con lo elegido marcado encima (`ProcessedOriginalScreen`). Sin copia, no se
/// ve.
///
/// Es también el lugar de lo que se haga con la copia misma —borrarla, por
/// ejemplo (decisión K)—, al lado de «Ver el original».
class ProcessedOriginalCard extends ConsumerWidget {
  const ProcessedOriginalCard({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final original = ref
        .watch(processedOriginalProvider(documentId))
        .valueOrNull;
    if (original == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final date = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(original.copiedAt.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: const Key('processed-original-card'),
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.file_copy_outlined, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.processedOriginalCardTitle,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          l10n.processedOriginalCardDetails(
                            originalKindLabel(l10n, original),
                            formatFileSize(original.sizeBytes, l10n.localeName),
                            date,
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                key: const Key('processed-open-original'),
                onPressed: () =>
                    context.push(RoutePaths.processedOriginal(documentId)),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(l10n.processedOriginalOpen),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.processedOriginalMarked,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Qué es la copia, para quien la mira: un PDF, una página web archivada o un
/// documento —un Word, un EPUB, un texto—.
String originalKindLabel(AppLocalizations l10n, ProcessedOriginal original) =>
    switch (original.kind) {
      RenditionKind.pdf => l10n.processedOriginalKindPdf,
      RenditionKind.html => l10n.processedOriginalKindPage,
      _ => l10n.processedOriginalKindDocument,
    };
