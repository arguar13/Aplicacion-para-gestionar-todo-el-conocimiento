import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/app_semantic_colors.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_model_picker.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_selection.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_scope_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La barra de arriba del chat (F42): ☰ a la izquierda abre las
/// conversaciones, al centro la píldora con el modelo —y debajo, en chico,
/// dónde se pregunta— y a la derecha ✎, una conversación nueva.
///
/// Limpia a propósito: lo que antes ocupaba la barra —el título, el
/// historial, la cuenta, el robot, el selector de modo y el de cuaderno—
/// tiene ahora su lugar en la píldora, en la línea de abajo y en el panel.
class ChatTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const ChatTopBar({
    required this.textScaler,
    required this.onOpenPanel,
    required this.onNewConversation,
    required this.onOpenRoute,
    super.key,
  });

  /// La escala de letra de la pantalla: con letra grande la barra crece, en
  /// vez de cortar la píldora o la línea de abajo.
  final TextScaler textScaler;

  final VoidCallback onOpenPanel;

  /// `null` si no hay nada que dejar atrás: la conversación ya es nueva.
  final VoidCallback? onNewConversation;

  /// Abre una pantalla de la IA desde la hoja del modelo.
  final ValueChanged<String> onOpenRoute;

  @override
  Size get preferredSize => Size.fromHeight(chatTopBarHeight(textScaler));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return AppBar(
      toolbarHeight: preferredSize.height,
      centerTitle: true,
      leading: IconButton(
        key: const Key('chat-open-panel'),
        icon: const Icon(Icons.menu_rounded),
        tooltip: l10n.chatPanelOpenTooltip,
        onPressed: onOpenPanel,
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChatModelPill(onOpenRoute: onOpenRoute),
          const SizedBox(height: 2),
          const ChatScopeLine(),
        ],
      ),
      actions: [
        IconButton(
          key: const Key('chat-new-conversation'),
          icon: const Icon(Icons.edit_outlined),
          tooltip: l10n.chatNewConversationTooltip,
          onPressed: onNewConversation,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Lo alto de [ChatTopBar] con [textScaler]: la píldora y la línea de abajo,
/// con su aire, y nunca menos que una barra común.
double chatTopBarHeight(TextScaler textScaler) {
  final pill = textScaler.scale(14) * 1.43 + 14;
  final line = textScaler.scale(12) * 1.34 + 4;
  return math.max(kToolbarHeight + 8, pill + line + 14);
}

/// La píldora con el modelo que contesta (F42): «Gemma 4 E4B ▾»,
/// «Gemini 3.1 Flash Lite ▾». Un punto dice si puede contestar ahora. Tocarla
/// abre la hoja para elegir el proveedor, el modelo y la cuenta.
class ChatModelPill extends ConsumerWidget {
  const ChatModelPill({required this.onOpenRoute, super.key});

  final ValueChanged<String> onOpenRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final model = watchChosenModelTitle(ref, l10n);
    final status = ref.watch(languageModelStatusProvider).valueOrNull;
    final ok = theme.extension<AppSemanticColors>()?.success ?? scheme.primary;
    final (dot, condition) = switch (status) {
      null => (scheme.outline, l10n.lmStatusChecking),
      LanguageModelReady() ||
      LanguageModelBackgroundCapReached() => (ok, l10n.lmStatusReady),
      LanguageModelOutOfQuota(keysRejected: true) => (
        scheme.error,
        l10n.lmStatusKeysRejected,
      ),
      _ => (scheme.tertiary, l10n.chatModelPillNotReady),
    };

    return Tooltip(
      message: l10n.chatModelPillTooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: l10n.chatModelPillSemantics(model, condition),
        excludeSemantics: true,
        child: Material(
          color: scheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('chat-model-pill'),
            onTap: () =>
                unawaited(showAiModelPicker(context, onOpenRoute: onOpenRoute)),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 7, 8, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    key: const Key('chat-model-pill-dot'),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dot,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Debajo de la píldora, en chico: dónde se pregunta (F42, decisión C).
/// Tocarla abre la hoja para cambiar el modo y el cuaderno.
class ChatScopeLine extends ConsumerWidget {
  const ChatScopeLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = watchChatScopeSummary(ref, l10n);
    final isFree = ref.watch(chatSelectionProvider.select((s) => s.isFree));
    final style = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Semantics(
      button: true,
      label: l10n.chatScopeLineSemantics(summary),
      excludeSemantics: true,
      child: InkWell(
        key: const Key('chat-scope-line'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => unawaited(showChatScopeSheet(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFree ? Icons.chat_bubble_outline : Icons.folder_outlined,
                size: 13,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
