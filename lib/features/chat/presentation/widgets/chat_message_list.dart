import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_answer.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_answer_message.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_typing_indicator.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_user_bubble.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Hasta qué ancho crece la conversación (F42): en una tableta o en la
/// computadora, una respuesta de lado a lado de la pantalla no se lee; se
/// centra en una columna, como un texto.
const kChatColumnMaxWidth = 760.0;

/// Cuánto hay que haberse alejado del final para que aparezca «↓».
const _kJumpThreshold = 240.0;

/// Lleva [controller] al final de la conversación (F42), y al final de
/// verdad: la lista arma solo los mensajes que se ven, así que el largo que
/// conoce antes de llegar es una estimación —con mensajes de largos muy
/// distintos, queda corta o larga—. Después de ir (con [animate], de a poco)
/// se corrige hasta que el final deje de moverse: cada salto arma lo que
/// faltaba y el largo se vuelve exacto.
Future<void> scrollChatToEnd(
  ScrollController controller, {
  required bool animate,
}) async {
  if (!controller.hasClients) return;
  if (animate) {
    await controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }
  for (var i = 0; i < 8 && controller.hasClients; i++) {
    final position = controller.position;
    // Si la persona la agarró con el dedo, manda ella.
    if (position.isScrollingNotifier.value ||
        position.maxScrollExtent - position.pixels < 0.5) {
      return;
    }
    position.jumpTo(position.maxScrollExtent);
    await WidgetsBinding.instance.endOfFrame;
  }
}

/// Con qué nombre conoce el lector flotante a un mensaje (F25).
String chatMessageKey(String messageId) => 'chat:$messageId';

/// Lo que se lee en voz alta de una conversación (F25): los mensajes, en
/// orden —los del usuario y las respuestas—, cada uno con su resaltado. Sin
/// los avisos de error ni los mensajes que son solo adjuntos. Se arma de
/// nuevo solo cuando llega un mensaje.
///
/// Las respuestas se leen como Markdown (F42): ya se ven con formato, y el
/// lector no dice los `#` ni los `**`.
final chatReadableProvider = Provider.autoDispose
    .family<ReadableDocument?, ({String conversationId, String title})>((
      ref,
      chat,
    ) {
      final messages = ref
          .watch(chatMessagesProvider(chat.conversationId))
          .valueOrNull;
      if (messages == null) return null;
      return documentFrom('chat:${chat.conversationId}', chat.title, [
        for (final message in messages)
          if (message.error == null && message.text.isNotEmpty)
            (
              sourceKey: chatMessageKey(message.id),
              text: message.text,
              markdown: !message.isUser,
              transcript: false,
            ),
      ]);
    });

/// La conversación abierta (F42): lo de la persona en burbujas a la derecha,
/// las respuestas a todo lo ancho, y la que se está escribiendo al final.
///
/// Al subir a releer algo aparece «↓», que vuelve al final.
class ChatMessageList extends ConsumerStatefulWidget {
  const ChatMessageList({
    required this.conversationId,
    required this.mode,
    required this.asking,
    required this.streaming,
    required this.scrollController,
    required this.empty,
    this.streamingSources = const [],
    this.onRegenerate,
    this.onResend,
    super.key,
  });

  final String conversationId;
  final ChatConversationMode mode;

  /// Si en esta conversación se está esperando una respuesta.
  final bool asking;

  /// La respuesta mientras se escribe (F30).
  final ValueListenable<String?> streaming;

  /// Las fuentes de la respuesta que se está escribiendo, para que sus citas
  /// sean chips desde que aparecen.
  final List<ChatSource> streamingSources;

  final ScrollController scrollController;

  /// Lo que se ve si la conversación no tiene mensajes todavía.
  final Widget empty;

  /// Vuelve a pedir la última respuesta; `null` mientras se espera una.
  final void Function(PersistedChatMessage answer)? onRegenerate;

  /// Manda corregido un mensaje de la persona; `null` mientras se espera una
  /// respuesta.
  final void Function(PersistedChatMessage original, String text)? onResend;

  @override
  ConsumerState<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends ConsumerState<ChatMessageList> {
  /// Si se ve «↓»: vive aparte para no volver a armar la lista al deslizar.
  final _awayFromEnd = ValueNotifier(false);

  @override
  void dispose() {
    _awayFromEnd.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollMetrics metrics) {
    if (metrics.axis == Axis.vertical) {
      _awayFromEnd.value =
          metrics.maxScrollExtent - metrics.pixels > _kJumpThreshold;
    }
    return false;
  }

  void _jumpToEnd() => unawaited(
    scrollChatToEnd(
      widget.scrollController,
      animate: !MediaQuery.disableAnimationsOf(context),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scrollController = widget.scrollController;
    final messagesAsync = ref.watch(
      chatMessagesProvider(widget.conversationId),
    );

    ref.listen(chatMessagesProvider(widget.conversationId), (previous, next) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(scrollChatToEnd(scrollController, animate: true)),
      );
    });

    return messagesAsync.when(
      data: (messages) {
        if (messages.isEmpty && !widget.asking) return widget.empty;
        return ReadableRegion(
          document: ref.watch(
            chatReadableProvider((
              conversationId: widget.conversationId,
              title: l10n.chatTitle,
            )),
          ),
          child: Stack(
            children: [
              NotificationListener<ScrollMetricsNotification>(
                onNotification: (n) => _onScroll(n.metrics),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) => _onScroll(n.metrics),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side = math.max<double>(
                        16,
                        (constraints.maxWidth - kChatColumnMaxWidth) / 2,
                      );
                      return ListView.builder(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(side, 16, side, 24),
                        itemCount: messages.length + (widget.asking ? 1 : 0),
                        itemBuilder: (context, index) =>
                            index >= messages.length
                            ? _growing()
                            : _message(messages, index),
                      );
                    },
                  ),
                ),
              ),
              _JumpToEnd(visible: _awayFromEnd, onPressed: _jumpToEnd),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, stackTrace) => Center(child: Text(l10n.globalErrorUnexpected)),
    );
  }

  Widget _message(List<PersistedChatMessage> messages, int index) {
    final message = messages[index];
    final key = chatMessageKey(message.id);
    if (message.isUser) {
      final resend = widget.onResend;
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: ChatUserBubble(
          key: ValueKey(message.id),
          message: message,
          sourceKey: key,
          onResend: resend == null ? null : (text) => resend(message, text),
        ),
      );
    }
    final regenerate = widget.onRegenerate;
    final last = index == messages.length - 1 && !widget.asking;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: ChatAnswerMessage(
        key: ValueKey(message.id),
        message: message,
        sourceKey: key,
        onRegenerate: last && regenerate != null
            ? () => regenerate(message)
            : null,
      ),
    );
  }

  /// La respuesta que se está escribiendo: el indicador vivo hasta la primera
  /// palabra, y después el texto que crece.
  Widget _growing() => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: ValueListenableBuilder<String?>(
      valueListenable: widget.streaming,
      builder: (context, text, _) => text == null || text.isEmpty
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: ChatTypingIndicator(mode: widget.mode),
            )
          : ChatAnswerBody(
              key: const Key('chat-streaming-reply'),
              text: text,
              sourceKey: 'chat:streaming',
              sources: widget.streamingSources,
              growing: true,
            ),
    ),
  );
}

/// «↓»: aparece al alejarse del final y vuelve a él.
class _JumpToEnd extends StatelessWidget {
  const _JumpToEnd({required this.visible, required this.onPressed});

  final ValueListenable<bool> visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, shown, child) => IgnorePointer(
            ignoring: !shown,
            child: ExcludeSemantics(
              excluding: !shown,
              child: AnimatedOpacity(
                opacity: shown ? 1 : 0,
                duration: duration,
                child: AnimatedScale(
                  scale: shown ? 1 : 0.8,
                  duration: duration,
                  curve: Curves.easeOutBack,
                  child: child,
                ),
              ),
            ),
          ),
          child: Material(
            color: scheme.surfaceContainerHigh,
            shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
            elevation: 3,
            shadowColor: scheme.shadow.withValues(alpha: 0.3),
            child: IconButton(
              key: const Key('chat-jump-to-end'),
              icon: const Icon(Icons.arrow_downward_rounded),
              color: scheme.onSurface,
              tooltip: l10n.chatJumpToEnd,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}
