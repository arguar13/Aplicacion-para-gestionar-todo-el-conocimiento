import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_markdown_blocks.dart';
import 'package:sinapsis/features/help/presentation/providers/help_providers.dart';
import 'package:sinapsis/features/help/presentation/widgets/help_block_view.dart';
import 'package:sinapsis/features/help/presentation/widgets/help_load_error.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo nuevo de cada etapa de la app (F47, paso 7): `NOVEDADES.md`, de la
/// raíz, empaquetado igual que la guía, con la etapa de ahora arriba y la
/// versión que está corriendo antes que nada.
///
/// Se lee de corrido, sin índice ni búsqueda: es una lista que se recorre de
/// arriba abajo, y lo de arriba es lo último.
class WhatsNewScreen extends ConsumerWidget {
  const WhatsNewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.f47P7WhatsNew)),
      body: ref
          .watch(whatsNewProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                HelpLoadError(onRetry: () => ref.invalidate(whatsNewProvider)),
            data: (whatsNew) {
              final blocks = <ChatBlock>[
                ...whatsNew.preface,
                for (final stage in whatsNew.chapters) ...stage.blocks,
              ];
              // Uno por bloque y a medida que se ven: las etapas son muchas.
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kHelpReadingWidth,
                  ),
                  child: SelectionArea(
                    child: ListView.builder(
                      key: const Key('whats-new-list'),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: blocks.length + 1,
                      itemBuilder: (context, index) => index == 0
                          ? const _RunningVersion()
                          : HelpBlockView(
                              raw: whatsNew.raw,
                              block: blocks[index - 1],
                              previous: index < 2 ? null : blocks[index - 2],
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }
}

/// La versión que está corriendo, arriba de todo.
class _RunningVersion extends ConsumerWidget {
  const _RunningVersion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).valueOrNull;
    if (version == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('whats-new-version'),
        margin: EdgeInsets.zero,
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.new_releases_outlined,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.f47P7WhatsNewCurrentVersion(
                    version.version,
                    version.build,
                  ),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
