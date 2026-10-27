import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/chat/domain/services/dictation.dart';
import 'package:sinapsis/features/chat/presentation/providers/dictation_providers.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_attachments.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántas líneas crece el campo antes de empezar a desplazarse.
const _kMaxLines = 6;

/// El lado de los botones redondos de la cápsula.
const _kButton = 40.0;

/// El campo del chat, una cápsula que flota abajo (F42): «+» a la izquierda
/// —abre «Agregar al chat»—, el texto, y a la derecha 🎤 para dictar y el
/// botón redondo de enviar, que mientras el modelo escribe es «Detener».
///
/// Arriba del texto, adentro de la cápsula, lo adjunto que espera el mensaje
/// ([attachments]) y, si está prendido, «Pensar más» ([thinkMore]).
///
/// Lo que es solo del campo vive acá y no en la pantalla:
///
/// - **Dictar** ([Dictation]): lo oído se escribe en el campo mientras se
///   dice, después de lo que ya había. El 🎤 aparece solo si el dispositivo
///   tiene reconocimiento de voz.
/// - **Teclado de computadora**: Enter manda y Shift+Enter hace un salto de
///   línea. En el teléfono, el Enter del teclado de pantalla es un salto de
///   línea —el campo crece— y se manda con el botón, como en cualquier chat.
///   Mientras un método de entrada compone (japonés, chino), Enter confirma
///   lo compuesto y no manda nada.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    required this.controller,
    required this.hintText,
    required this.attachments,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onAdd,
    this.onStop,
    this.asking = false,
    this.attaching = false,
    this.thinkMore = false,
    this.onThinkMoreOff,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final List<PendingChatAttachment> attachments;
  final ValueChanged<PendingChatAttachment> onRemoveAttachment;
  final VoidCallback onSend;

  /// El «+»; `null` lo deja apagado (mientras se lee un documento adjunto).
  final VoidCallback? onAdd;

  /// Corta la respuesta que se está escribiendo; `null` si no hay ninguna.
  /// Mientras haya una, enviar es «Detener» (F30).
  final VoidCallback? onStop;

  /// Si se está esperando una respuesta: no se manda otro mensaje, pero se
  /// puede ir escribiendo el próximo.
  final bool asking;

  /// Si se está leyendo un documento recién adjuntado: el «+» gira.
  final bool attaching;
  final bool thinkMore;
  final VoidCallback? onThinkMoreOff;
  final FocusNode? focusNode;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  /// Lo que se está dictando; `null` si el 🎤 no escucha.
  StreamSubscription<DictationUpdate>? _dictating;

  /// Lo que había escrito antes de dictar: lo oído va después.
  var _beforeDictation = '';

  /// Qué tan fuerte llega la voz, para el latido del 🎤.
  final _level = ValueNotifier<double>(0);

  @override
  void dispose() {
    unawaited(_dictating?.cancel());
    _level.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !widget.asking &&
      (widget.controller.text.trim().isNotEmpty ||
          widget.attachments.isNotEmpty);

  /// Enter y Shift+Enter, con teclado de computadora (ver la clase).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_enterSends || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final composing = widget.controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (_canSend) widget.onSend();
    // Enter solo nunca es un salto de línea, aunque no haya qué mandar.
    return KeyEventResult.handled;
  }

  /// Si Enter manda: en la computadora (y la web, que se usa con una). En el
  /// teléfono algunos teclados de pantalla mandan el Enter como una tecla, y
  /// ahí tiene que ser el salto de línea que muestran.
  bool get _enterSends =>
      kIsWeb ||
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

  Future<void> _toggleDictation() async {
    final dictation = ref.read(dictationProvider);
    if (_dictating != null) {
      await dictation.stop();
      return;
    }
    _beforeDictation = widget.controller.text;
    _dictating = dictation
        .listen(localeTag: _speechLocale())
        .listen(
          (update) {
            switch (update) {
              case DictationHeard(:final text):
                _writeHeard(text);
              case DictationLevel(:final level):
                _level.value = level;
            }
          },
          onError: _dictationFailed,
          onDone: _dictationEnded,
          cancelOnError: true,
        );
    // El 🎤 pasa a «escuchando».
    setState(() {});
  }

  /// El idioma en que se habla: el del teléfono si es el de la app —«es-AR»
  /// reconoce mejor el voseo que «es» a secas—; si no, el de la app.
  String _speechLocale() {
    final app = Localizations.localeOf(context);
    final device = WidgetsBinding.instance.platformDispatcher.locales;
    final same = device.where((l) => l.languageCode == app.languageCode);
    return (same.isEmpty ? app : same.first).toLanguageTag();
  }

  void _writeHeard(String heard) {
    final before = _beforeDictation;
    final spoken = heard.trim();
    final text = before.isEmpty || spoken.isEmpty
        ? '$before$spoken'
        : RegExp(r'\s$').hasMatch(before)
        ? '$before$spoken'
        : '$before $spoken';
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _dictationFailed(Object error) {
    _dictationEnded();
    final l10n = AppLocalizations.of(context)!;
    final message = switch (error) {
      DictationPermissionDeniedException() =>
        l10n.chatDictationPermissionDenied,
      DictationFailedException(code: 'network') => l10n.chatDictationNoNetwork,
      _ => l10n.chatDictationFailed,
    };
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _dictationEnded() {
    _level.value = 0;
    if (mounted) setState(() => _dictating = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canDictate =
        ref.watch(dictationAvailableProvider).valueOrNull ?? false;
    final listening = _dictating != null;

    final field = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: TextField(
        key: const Key('chat-composer-field'),
        controller: widget.controller,
        focusNode: _focus,
        minLines: 1,
        maxLines: _kMaxLines,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        style: theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: listening && widget.controller.text.isEmpty
              ? l10n.chatComposerListeningHint
              : widget.hintText,
          hintStyle: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          hintMaxLines: 1,
          isCollapsed: true,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          key: const Key('chat-composer'),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? scheme.surfaceContainerHigh
                : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.attachments.isNotEmpty)
                PendingAttachmentsStrip(
                  attachments: widget.attachments,
                  onRemove: widget.onRemoveAttachment,
                ),
              if (widget.thinkMore)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _ThinkMorePill(onTurnOff: widget.onThinkMoreOff),
                ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _RoundButton(
                      tooltip: l10n.chatAddTooltip,
                      onPressed: widget.onAdd,
                      child: widget.attaching
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: field),
                    const SizedBox(width: 6),
                    if (canDictate) ...[
                      _MicButton(
                        listening: listening,
                        level: _level,
                        onPressed: _toggleDictation,
                      ),
                      const SizedBox(width: 6),
                    ],
                    ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) => _SendButton(
                        canSend: _canSend,
                        onSend: widget.onSend,
                        onStop: widget.onStop,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un botón redondo de la cápsula, sin fondo.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: child,
      constraints: const BoxConstraints.tightFor(
        width: _kButton + 4,
        height: _kButton + 4,
      ),
      style: IconButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Enviar —un círculo con la flecha, lleno del color del tema cuando hay
/// qué mandar— o, mientras el modelo escribe, «Detener» (un cuadrado).
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.canSend,
    required this.onSend,
    required this.onStop,
  });

  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final stop = onStop;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final button = stop != null
        ? IconButton.filled(
            key: const ValueKey('stop'),
            tooltip: l10n.chatStopTooltip,
            onPressed: stop,
            icon: const Icon(Icons.stop_rounded),
          )
        : IconButton.filled(
            key: const ValueKey('send'),
            tooltip: l10n.chatSendTooltip,
            onPressed: canSend ? onSend : null,
            style: IconButton.styleFrom(
              disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.08),
              disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
            ),
            icon: const Icon(Icons.arrow_upward_rounded),
          );

    return SizedBox.square(
      dimension: _kButton + 4,
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        // Desde 0,7 y no desde 0: lo que entra se puede tocar desde el
        // primer cuadro —«Detener» apenas aparece—.
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.7, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: button,
      ),
    );
  }
}

/// El 🎤: dicta. Mientras escucha se llena del color del tema y un anillo
/// late con la voz —quieto con «sin animaciones»—.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.listening,
    required this.level,
    required this.onPressed,
  });

  final bool listening;
  final ValueListenable<double> level;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (!listening) {
      return _RoundButton(
        tooltip: l10n.chatDictateTooltip,
        onPressed: onPressed,
        child: const Icon(Icons.mic_none_rounded),
      );
    }

    final still = MediaQuery.disableAnimationsOf(context);
    return SizedBox.square(
      dimension: _kButton + 4,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: level,
            builder: (context, value, _) => Transform.scale(
              scale: still ? 1.1 : 1 + 0.35 * value,
              child: Container(
                width: _kButton,
                height: _kButton,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: 0.22),
                ),
              ),
            ),
          ),
          IconButton.filled(
            tooltip: l10n.chatDictateStopTooltip,
            onPressed: onPressed,
            icon: const Icon(Icons.mic_rounded),
          ),
        ],
      ),
    );
  }
}

/// «Pensar más», prendido: una pastilla arriba del texto, que se apaga
/// tocándola.
class _ThinkMorePill extends StatelessWidget {
  const _ThinkMorePill({required this.onTurnOff});

  final VoidCallback? onTurnOff;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: l10n.chatThinkMoreTurnOffTooltip,
      child: Material(
        key: const Key('chat-think-more-pill'),
        color: scheme.secondaryContainer,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTurnOff,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.psychology_alt_outlined,
                    size: 16,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      l10n.chatThinkMoreChip,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: scheme.onSecondaryContainer,
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
