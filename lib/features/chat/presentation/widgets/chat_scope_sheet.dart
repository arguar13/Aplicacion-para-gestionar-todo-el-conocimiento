import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_selection.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Dónde se pregunta, en una línea (F42, decisión C): «Con tu bóveda · Toda
/// la bóveda», «Con tu bóveda · Tesis» o «Conversación libre». La muestra la
/// barra debajo del modelo, para no olvidar nunca dónde se está preguntando.
///
/// Si el cuaderno elegido se borró mientras tanto, dice «Toda la bóveda»,
/// igual que lo hacía el desplegable de antes.
String watchChatScopeSummary(WidgetRef ref, AppLocalizations l10n) {
  final selection = ref.watch(chatSelectionProvider);
  if (selection.isFree) return l10n.chatModeFree;
  final notebookId = selection.notebookId;
  final notebook = notebookId == null
      ? null
      : ref.watch(notebookByIdProvider(notebookId)).valueOrNull;
  return '${l10n.chatScopeLineVault} · '
      '${notebook?.name ?? l10n.chatNotebookScopeAll}';
}

/// La hoja «Dónde pregunto» (F42): el modo y, con la bóveda, el cuaderno.
/// Se abre tocando la línea debajo del modelo. Elegir la conversación libre
/// o un cuaderno la cierra; elegir la bóveda la deja abierta para acotarla.
Future<void> showChatScopeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
      ),
      child: ChatScopeOptions(onDone: () => Navigator.of(sheetContext).pop()),
    ),
  );
}

/// El contenido de [showChatScopeSheet]: el modo y el alcance, que cambian
/// [chatSelectionProvider]. Se puede poner en otra hoja (el «+» del campo).
class ChatScopeOptions extends ConsumerWidget {
  const ChatScopeOptions({this.onDone, super.key});

  /// Se llama cuando ya no queda nada por elegir.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final selection = ref.watch(chatSelectionProvider);
    final selector = ref.read(chatSelectionProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.chatScopeSheetTitle,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 16),
          _ModeOption(
            key: const Key('chat-scope-vault'),
            icon: Icons.folder_outlined,
            title: l10n.chatModeVault,
            hint: l10n.chatScopeVaultHint,
            selected: !selection.isFree,
            onTap: () => selector.changeMode(ChatConversationMode.vault),
          ),
          const SizedBox(height: 10),
          _ModeOption(
            key: const Key('chat-scope-free'),
            icon: Icons.chat_bubble_outline,
            title: l10n.chatModeFree,
            hint: l10n.chatScopeFreeHint,
            selected: selection.isFree,
            onTap: () {
              selector.changeMode(ChatConversationMode.free);
              onDone?.call();
            },
          ),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: selection.isFree
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: ChatNotebookScopeList(onChosen: onDone),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Toda la bóveda y cada cuaderno, para acotar el modo con la bóveda (F16,
/// D1; F42). La opción elegida lleva el tilde.
class ChatNotebookScopeList extends ConsumerWidget {
  const ChatNotebookScopeList({this.onChosen, super.key});

  /// Después de elegir.
  final VoidCallback? onChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final notebooks = ref.watch(notebooksProvider).valueOrNull ?? const [];
    final chosen = ref.watch(chatSelectionProvider.select((s) => s.notebookId));
    // Un cuaderno que ya no está cuenta como «toda la bóveda».
    final shown = notebooks.any((n) => n.id == chosen) ? chosen : null;
    void choose(String? id) {
      ref.read(chatSelectionProvider.notifier).selectNotebook(id);
      onChosen?.call();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            header: true,
            child: Text(
              l10n.chatScopeNotebookTitle,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _ScopeTile(
                key: const Key('chat-scope-notebook-all'),
                icon: Icons.folder_outlined,
                title: l10n.chatNotebookScopeAll,
                selected: shown == null,
                onTap: () => choose(null),
              ),
              for (final notebook in notebooks) ...[
                const Divider(height: 1),
                _ScopeTile(
                  key: Key('chat-scope-notebook-${notebook.id}'),
                  icon: Icons.auto_stories_outlined,
                  title: notebook.name,
                  selected: shown == notebook.id,
                  onTap: () => choose(notebook.id),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.icon,
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerLow,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: selected
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: selected
                                ? scheme.onSecondaryContainer
                                : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: selected
                                ? scheme.onSecondaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_circle, color: scheme.primary),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScopeTile extends StatelessWidget {
  const _ScopeTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        selected: selected,
        trailing: selected ? Icon(Icons.check, color: scheme.primary) : null,
        onTap: onTap,
      ),
    );
  }
}
