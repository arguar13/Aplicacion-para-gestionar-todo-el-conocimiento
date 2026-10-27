import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/chat/domain/repositories/chat_conversation_repository.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_history.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_selection.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/settings/presentation/providers/owner_name.dart';
import 'package:sinapsis/features/settings/presentation/widgets/owner_name_tile.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuánto queda a la vista el «Deshacer» de una conversación borrada antes
/// de borrarla de verdad.
const kChatDeleteUndoWindow = Duration(seconds: 6);

/// Lo más largo de un nombre puesto a mano.
const _kTitleMaxLength = 80;

/// Abre el panel de conversaciones (F42) desde la izquierda, encima de todo
/// —también de la barra de la app—, con un deslizamiento suave; con «sin
/// animaciones» aparece de una. Se cierra tocando afuera, con «atrás» o
/// deslizándolo hacia la izquierda.
///
/// Es una ruta y no el `Drawer` del `Scaffold`: así cubre la pantalla entera
/// y su transición respeta «sin animaciones», cosa que el `Drawer` de
/// Flutter no hace. Una ruta emergente ([PopupRoute]), como un diálogo, y no
/// una página: deja ver lo de abajo y no dispara las animaciones `Hero` de
/// la pantalla que tapa.
Future<void> showChatConversationsPanel(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    _ChatPanelRoute(
      barrierLabel: AppLocalizations.of(context)!.chatPanelClose,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4),
      still: MediaQuery.disableAnimationsOf(context),
    ),
  );
}

class _ChatPanelRoute extends PopupRoute<void> {
  _ChatPanelRoute({
    required this.barrierLabel,
    required this.barrierColor,
    required this.still,
  });

  @override
  final String barrierLabel;

  @override
  final Color barrierColor;

  /// «Sin animaciones»: aparece y se va de una.
  final bool still;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      still ? Duration.zero : const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration =>
      still ? Duration.zero : const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const Align(
    alignment: AlignmentDirectional.centerStart,
    child: ChatConversationsPanel(),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SlideTransition(
      position: Tween(
        begin: Offset(rtl ? 1 : -1, 0),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.6, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

/// El panel de conversaciones (F42): atajos a la Biblioteca y a los
/// Cuadernos, un buscador, las conversaciones de los dos modos agrupadas por
/// día —las fijadas arriba—, cada una con su menú, y al pie el nombre de la
/// persona y «Nueva».
///
/// Reemplaza al historial que se abría desde la derecha: lo mismo —abrir,
/// empezar otra, borrar—, más renombrar, fijar, buscar y deshacer un borrado.
class ChatConversationsPanel extends ConsumerStatefulWidget {
  const ChatConversationsPanel({super.key});

  @override
  ConsumerState<ChatConversationsPanel> createState() =>
      _ChatConversationsPanelState();
}

/// Una conversación borrada que todavía se puede recuperar.
typedef _PendingDelete = ({
  ChatConversation conversation,
  Timer timer,
  bool wasOpen,
});

class _ChatConversationsPanelState
    extends ConsumerState<ChatConversationsPanel> {
  final _search = TextEditingController();
  var _query = '';

  /// Las borradas con su «Deshacer» a la vista, por id. Se borran de verdad
  /// al pasar [kChatDeleteUndoWindow] o al cerrarse el panel, lo primero que
  /// ocurra: el «Deshacer» vive lo que el panel.
  final _pending = <String, _PendingDelete>{};

  late final ChatConversationRepository _repository;
  late final ChatPinsNotifier _pins;

  @override
  void initState() {
    super.initState();
    // Se toman ya: un borrado puede confirmarse al cerrarse el panel, cuando
    // `ref` ya no se puede usar.
    _repository = ref.read(chatConversationRepositoryProvider);
    _pins = ref.read(chatPinsProvider.notifier);
  }

  @override
  void dispose() {
    for (final pending in _pending.values) {
      pending.timer.cancel();
      unawaited(_erase(pending.conversation.id));
    }
    _pending.clear();
    _search.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _open(ChatConversation conversation) {
    ref.read(chatSelectionProvider.notifier).open(conversation);
    _close();
  }

  void _startNew() {
    ref.read(chatSelectionProvider.notifier).startNew();
    _close();
  }

  /// Cierra el panel y va a [location], otra sección de la app.
  void _goTo(String location) {
    final router = GoRouter.of(context);
    _close();
    router.go(location);
  }

  Future<void> _rename(ChatConversation conversation) async {
    final l10n = AppLocalizations.of(context)!;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(
        initial: conversation.title ?? '',
        hint: l10n.chatHistoryUntitled,
      ),
    );
    final clean = title?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    if (clean.isEmpty || clean == conversation.title) return;
    final capped = clean.length > _kTitleMaxLength
        ? clean.substring(0, _kTitleMaxLength).trimRight()
        : clean;
    await _repository.renameConversation(conversation.id, capped);
  }

  void _delete(ChatConversation conversation) {
    final selector = ref.read(chatSelectionProvider.notifier);
    final wasOpen = ref.read(chatSelectionProvider).holds(conversation.id);
    // La de la pantalla se cierra en el acto; la fila espera el «Deshacer».
    if (wasOpen) selector.forget(conversation.id);
    setState(() {
      _pending[conversation.id] = (
        conversation: conversation,
        timer: Timer(
          kChatDeleteUndoWindow,
          () => unawaited(_commitDelete(conversation.id)),
        ),
        wasOpen: wasOpen,
      );
    });
  }

  void _undoDelete(String id) {
    final pending = _pending.remove(id);
    if (pending == null) return;
    pending.timer.cancel();
    if (pending.wasOpen) {
      ref.read(chatSelectionProvider.notifier).open(pending.conversation);
    }
    setState(() {});
  }

  /// Pasó el tiempo del «Deshacer»: se borra de verdad.
  Future<void> _commitDelete(String id) async {
    if (_pending.remove(id) == null) return;
    setState(() {});
    await _erase(id);
  }

  /// Borra la conversación con sus mensajes, y la desfija.
  Future<void> _erase(String id) async {
    await _repository.deleteConversation(id);
    await _pins.unpin(id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final width = math.min<double>(size.width * 0.86, 360);
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.chatPanelLabel,
      child: GestureDetector(
        // Deslizarlo hacia afuera lo cierra, como un cajón.
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (rtl ? velocity > 300 : velocity < -300) _close();
        },
        child: Material(
          key: const Key('chat-panel'),
          color: scheme.surfaceContainerLow,
          elevation: 2,
          shadowColor: scheme.shadow,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadiusDirectional.horizontal(
              end: Radius.circular(28),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: SafeArea(
              right: rtl,
              left: !rtl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  _Shortcut(
                    key: const Key('chat-panel-library'),
                    icon: Icons.folder_outlined,
                    label: l10n.navLibrary,
                    onTap: () => _goTo(RoutePaths.library),
                  ),
                  _Shortcut(
                    key: const Key('chat-panel-notebooks'),
                    icon: Icons.auto_stories_outlined,
                    label: l10n.navNotebooks,
                    onTap: () => _goTo(RoutePaths.notebooks),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: _SearchField(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  Expanded(child: _buildList(context)),
                  Divider(height: 1, color: scheme.outlineVariant),
                  _Footer(onNew: _startNew),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final history = ref.watch(chatHistoryProvider);
    final pinned = ref.watch(chatPinsProvider);
    final activeId = ref.watch(
      chatSelectionProvider.select((s) => s.conversationId),
    );
    final now = ref.watch(clockProvider)();

    return history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          _PanelMessage(text: l10n.globalErrorUnexpected),
      data: (conversations) {
        if (conversations.isEmpty) {
          return _PanelMessage(
            icon: Icons.forum_outlined,
            text: l10n.chatPanelEmpty,
          );
        }
        final sections = groupChatHistory(
          conversations,
          pinned: pinned,
          now: now,
          query: _query,
        );
        if (sections.isEmpty) {
          return _PanelMessage(
            icon: Icons.search_off,
            text: l10n.chatPanelNoMatches,
          );
        }
        final locale = Localizations.localeOf(context).toLanguageTag();
        return ListView(
          key: const Key('chat-panel-list'),
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            for (final section in sections) ...[
              _SectionHeader(text: _sectionTitle(l10n, section, now, locale)),
              for (final conversation in section.conversations)
                if (_pending[conversation.id] case final pending?)
                  _DeletedRow(
                    title:
                        pending.conversation.title ?? l10n.chatHistoryUntitled,
                    onUndo: () => _undoDelete(conversation.id),
                  )
                else
                  _ConversationRow(
                    conversation: conversation,
                    selected: conversation.id == activeId,
                    pinned: pinned.contains(conversation.id),
                    time: section.kind == ChatHistorySectionKind.pinned
                        ? DateFormat.MMMd(
                            locale,
                          ).add_Hm().format(conversation.updatedAt.toLocal())
                        : DateFormat.Hm(
                            locale,
                          ).format(conversation.updatedAt.toLocal()),
                    onTap: () => _open(conversation),
                    onRename: () => unawaited(_rename(conversation)),
                    onTogglePin: () => unawaited(_pins.toggle(conversation.id)),
                    onDelete: () => _delete(conversation),
                  ),
            ],
          ],
        );
      },
    );
  }

  static String _sectionTitle(
    AppLocalizations l10n,
    ChatHistorySection section,
    DateTime now,
    String locale,
  ) => switch (section.kind) {
    ChatHistorySectionKind.pinned => l10n.chatPanelPinned,
    ChatHistorySectionKind.today => l10n.chatPanelToday,
    ChatHistorySectionKind.yesterday => l10n.chatPanelYesterday,
    ChatHistorySectionKind.day =>
      section.day!.year == now.toLocal().year
          ? DateFormat.MMMMEEEEd(locale).format(section.day!)
          : DateFormat.yMMMMEEEEd(locale).format(section.day!),
  };
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        shape: const StadiumBorder(),
        leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        title: Text(label, style: theme.textTheme.titleSmall),
        onTap: onTap,
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        key: const Key('chat-panel-search'),
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: l10n.chatPanelSearchHint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: l10n.chatPanelSearchClear,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: scheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

enum _RowAction { rename, togglePin, delete }

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({
    required this.conversation,
    required this.selected,
    required this.pinned,
    required this.time,
    required this.onTap,
    required this.onRename,
    required this.onTogglePin,
    required this.onDelete,
  });

  final ChatConversation conversation;
  final bool selected;
  final bool pinned;
  final String time;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = conversation.title ?? l10n.chatHistoryUntitled;
    final isVault = conversation.mode == ChatConversationMode.vault;
    final notebookId = conversation.notebookId;
    final notebook = notebookId == null
        ? null
        : ref.watch(notebookByIdProvider(notebookId)).valueOrNull;
    final subtitle = [
      if (isVault) l10n.chatScopeLineVault else l10n.chatModeFree,
      ?notebook?.name,
      time,
    ].join(' · ');

    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;

    // Una fila hecha a mano y no un `ListTile`: el `ListTile` junta todo lo
    // de adentro en un solo nodo para el lector de pantalla, y el ⋮ quedaba
    // escondido dentro de la fila. Así son dos: abrir la conversación y sus
    // opciones.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                container: true,
                selected: selected,
                button: true,
                child: InkWell(
                  key: Key('chat-panel-row-${conversation.id}'),
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 60),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        8,
                        4,
                        8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isVault
                                ? Icons.folder_outlined
                                : Icons.chat_bubble_outline,
                            size: 20,
                            color: foreground,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: selected
                                        ? scheme.onSecondaryContainer
                                        : scheme.onSurface,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: foreground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (pinned) ...[
                            const SizedBox(width: 8),
                            Semantics(
                              label: l10n.chatPanelPinnedBadge,
                              child: Icon(
                                Icons.push_pin,
                                size: 16,
                                color: foreground,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              container: true,
              child: PopupMenuButton<_RowAction>(
                key: Key('chat-panel-menu-${conversation.id}'),
                tooltip: l10n.chatPanelRowMenu(title),
                icon: Icon(Icons.more_vert, color: foreground),
                onSelected: (action) => switch (action) {
                  _RowAction.rename => onRename(),
                  _RowAction.togglePin => onTogglePin(),
                  _RowAction.delete => onDelete(),
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: const Key('chat-panel-rename'),
                    value: _RowAction.rename,
                    child: ListTile(
                      leading: const Icon(Icons.drive_file_rename_outline),
                      title: Text(l10n.commonRename),
                    ),
                  ),
                  PopupMenuItem(
                    key: const Key('chat-panel-pin'),
                    value: _RowAction.togglePin,
                    child: ListTile(
                      leading: Icon(
                        pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      ),
                      title: Text(
                        pinned ? l10n.chatPanelUnpin : l10n.chatPanelPin,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    key: const Key('chat-panel-delete'),
                    value: _RowAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: scheme.error),
                      title: Text(
                        l10n.chatHistoryDeleteTooltip,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// Lo que queda de una conversación recién borrada: lo dice y la recupera.
class _DeletedRow extends StatelessWidget {
  const _DeletedRow({required this.title, required this.onUndo});

  final String title;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A mano, como la fila: «Deshacer» es su propio botón para el lector.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 8, 6),
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.chatPanelDeleted(title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('chat-panel-undo'),
                  onPressed: onUndo,
                  child: Text(l10n.chatPanelUndo),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 12),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Al pie: el nombre con que la app llama a la persona —tocarlo lo
/// cambia— y «Nueva».
class _Footer extends ConsumerWidget {
  const _Footer({required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = ref.watch(ownerNameProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: name == null
                  ? l10n.chatPanelOwnerUnnamed
                  : l10n.chatPanelOwnerSemantics(name),
              excludeSemantics: true,
              child: InkWell(
                key: const Key('chat-panel-owner'),
                borderRadius: BorderRadius.circular(28),
                onTap: () => unawaited(showOwnerNameDialog(context, ref)),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.onPrimaryContainer,
                        child: name == null
                            ? const Icon(Icons.person_outline, size: 20)
                            : Text(
                                name.characters.first.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          name ?? l10n.chatPanelOwnerUnnamed,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: name == null
                              ? theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                )
                              : theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            key: const Key('chat-panel-new'),
            onPressed: onNew,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(l10n.chatPanelNew),
          ),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial, required this.hint});

  final String initial;
  final String hint;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.chatPanelRenameTitle),
      content: TextField(
        key: const Key('chat-panel-rename-field'),
        controller: _controller,
        autofocus: true,
        maxLength: _kTitleMaxLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('chat-panel-rename-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.ownerNameSave),
        ),
      ],
    );
  }
}
