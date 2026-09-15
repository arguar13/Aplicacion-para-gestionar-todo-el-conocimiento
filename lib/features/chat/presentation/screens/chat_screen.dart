import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/chat_answer.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un intercambio de la conversación: lo que se preguntó y, cuando ya está,
/// lo que contestó — o `null` mientras se está procesando.
class _ChatTurn {
  _ChatTurn({required this.question});

  final String question;
  ChatAnswer? answer;
  String? error;
}

/// Un intercambio de la conversación libre: sin fuentes, solo pregunta y
/// respuesta en lenguaje natural.
class _FreeTurn {
  _FreeTurn({required this.message});

  final String message;
  String? answer;
  String? error;
  bool done = false;
}

/// Los dos modos del chat. Cada uno lleva su propio historial, en vez de
/// mezclarse en una sola lista: son dos conversaciones distintas, con
/// reglas distintas —una cita fuentes y nunca inventa nada que no esté en
/// la bóveda, la otra es una charla común y corriente—, y verlas juntas
/// confundiría cuál es cuál.
enum _ChatMode { vault, free }

/// El chat de la app, en dos modos.
///
/// **Con mi bóveda**: busca qué hay guardado y, si el modelo de lenguaje ya
/// está descargado, redacta una respuesta que cita esas fuentes. Sin el
/// modelo, ya sirve como buscador —principio 4: degradar antes que
/// fallar—. Ver la decisión 20 en docs/arquitectura.md.
///
/// **Conversación libre**: el mismo modelo, sin restringirlo al contenido
/// de la bóveda — para hablar con él como con cualquier asistente. Acá no
/// hay red de contención: sin el modelo descargado no hay nada que
/// contestar, porque no existe una "búsqueda" de respaldo para una charla
/// que no busca nada.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatTurn> _vaultTurns = [];
  final List<_FreeTurn> _freeTurns = [];
  var _mode = _ChatMode.vault;
  var _modelReady = false;
  var _asking = false;

  /// La sesión de la conversación libre en curso. Vive mientras dure la
  /// charla —no se abre y se cierra pregunta a pregunta—, para que el
  /// modelo tenga todo lo dicho antes como contexto.
  FreeConversation? _conversation;

  /// Lo mismo, para el modo con la bóveda: solo existe cuando el modelo
  /// está descargado —sin él, cada pregunta pasa por
  /// `AskVaultQuestionUseCase`, que no necesita memoria porque no redacta
  /// nada, solo busca—.
  VaultConversation? _vaultConversation;

  @override
  void initState() {
    super.initState();
    _refreshModelStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    unawaited(_conversation?.close());
    unawaited(_vaultConversation?.close());
    super.dispose();
  }

  Future<void> _refreshModelStatus() async {
    final ready = await ref.read(chatModelManagerProvider).isReady();
    if (!mounted) return;
    setState(() => _modelReady = ready);
  }

  Future<void> _openModelScreen() async {
    await context.push(RoutePaths.chatModel);
    if (!mounted) return;
    unawaited(_refreshModelStatus());
  }

  void _changeMode(_ChatMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  /// Cierra la sesión del modo activo y borra su historial, para empezar de
  /// cero sin que el modelo siga arrastrando lo que se habló antes.
  void _newConversation() {
    switch (_mode) {
      case _ChatMode.free:
        unawaited(_conversation?.close());
        setState(() {
          _conversation = null;
          _freeTurns.clear();
        });
      case _ChatMode.vault:
        unawaited(_vaultConversation?.close());
        setState(() {
          _vaultConversation = null;
          _vaultTurns.clear();
        });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _asking) return;

    switch (_mode) {
      case _ChatMode.vault:
        await _askVault(text);
      case _ChatMode.free:
        await _askFree(text);
    }
  }

  Future<void> _askVault(String question) async {
    final turn = _ChatTurn(question: question);
    setState(() {
      _vaultTurns.add(turn);
      _controller.clear();
      _asking = true;
    });
    _scrollToEnd();

    // Sin el modelo, esto es un buscador y nada más (principio 4: degradar
    // antes que fallar) — el mismo camino de siempre, sin sesión ni
    // historial porque no hay nada que redactar.
    if (!_modelReady) {
      final result = await ref.read(askVaultQuestionUseCaseProvider)(question);
      if (!mounted) return;

      final l10n = AppLocalizations.of(context)!;
      setState(() {
        result.match(
          (failure) => turn.error = failure.localizedMessage(l10n),
          (answer) => turn.answer = answer,
        );
        _asking = false;
      });
      _scrollToEnd();
      return;
    }

    // Con el modelo: una charla de verdad, no una pregunta suelta cada vez.
    // La sesión se mantiene entre mensajes para que "¿y qué más dice sobre
    // eso?" tenga sentido sin repetir el contexto a mano; lo que sí se
    // busca de nuevo en cada vuelta es la bóveda, porque cada mensaje puede
    // hablar de algo distinto.
    try {
      final sources = await ref.read(vaultRetrieverProvider).retrieve(question);

      var conversation = _vaultConversation;
      conversation ??= await ref
          .read(chatModelProvider)
          .startVaultConversation();
      _vaultConversation = conversation;

      final text = await conversation.send(message: question, sources: sources);
      if (!mounted) return;
      setState(() {
        turn.answer = ChatAnswer(text: text, sources: sources);
        _asking = false;
      });
      // El motor de inferencia es de terceros (flutter_gemma); puede fallar
      // de formas que no tienen un tipo propio en Dart.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        turn.error = l10n.globalErrorUnexpected;
        _asking = false;
      });
    }
    _scrollToEnd();
  }

  Future<void> _askFree(String message) async {
    final l10n = AppLocalizations.of(context)!;
    final turn = _FreeTurn(message: message);

    // Sin el modelo no hay con qué contestar: a diferencia del modo con la
    // bóveda, acá no hay ninguna búsqueda de respaldo que ofrecer.
    if (!_modelReady) {
      setState(() {
        _freeTurns.add(
          turn
            ..error = l10n.chatFreeModelRequired
            ..done = true,
        );
        _controller.clear();
      });
      _scrollToEnd();
      return;
    }

    setState(() {
      _freeTurns.add(turn);
      _controller.clear();
      _asking = true;
    });
    _scrollToEnd();

    try {
      var conversation = _conversation;
      conversation ??= await ref.read(chatModelProvider).startConversation();
      _conversation = conversation;

      final answer = await conversation.send(message);
      if (!mounted) return;
      setState(() {
        turn
          ..answer = answer
          ..done = true;
        _asking = false;
      });
      // El motor de inferencia es de terceros (flutter_gemma); puede fallar
      // de formas que no tienen un tipo propio en Dart.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      if (!mounted) return;
      setState(() {
        turn
          ..error = l10n.globalErrorUnexpected
          ..done = true;
        _asking = false;
      });
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isFree = _mode == _ChatMode.free;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chatTitle),
        actions: [
          if (isFree ? _freeTurns.isNotEmpty : _vaultTurns.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: l10n.chatNewConversationTooltip,
              onPressed: _newConversation,
            ),
          IconButton(
            icon: Icon(
              _modelReady ? Icons.smart_toy_outlined : Icons.download_outlined,
            ),
            tooltip: l10n.chatModelTooltip,
            onPressed: _openModelScreen,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              child: SegmentedButton<_ChatMode>(
                segments: [
                  ButtonSegment(
                    value: _ChatMode.vault,
                    label: Text(l10n.chatModeVault),
                    icon: const Icon(Icons.folder_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: _ChatMode.free,
                    label: Text(l10n.chatModeFree),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) => _changeMode(selection.first),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_modelReady)
              _ModelBanner(
                message: isFree
                    ? l10n.chatFreeModelRequired
                    : l10n.chatModelNotReadyBanner,
                actionLabel: l10n.chatModelDownloadAction,
                onDownload: _openModelScreen,
              ),
            Expanded(child: isFree ? _freeBody(l10n) : _vaultBody(l10n)),
            _Composer(
              controller: _controller,
              enabled: !_asking,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }

  Widget _vaultBody(AppLocalizations l10n) {
    if (_vaultTurns.isEmpty) {
      return _EmptyState(explanation: l10n.chatEmptyExplanation);
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _vaultTurns.length,
      itemBuilder: (context, index) => _TurnView(turn: _vaultTurns[index]),
    );
  }

  Widget _freeBody(AppLocalizations l10n) {
    if (_freeTurns.isEmpty) {
      return _EmptyState(explanation: l10n.chatFreeEmptyExplanation);
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _freeTurns.length,
      itemBuilder: (context, index) => _FreeTurnView(turn: _freeTurns[index]),
    );
  }
}

class _ModelBanner extends StatelessWidget {
  const _ModelBanner({
    required this.message,
    required this.actionLabel,
    required this.onDownload,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
          TextButton(onPressed: onDownload, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.explanation});

  final String explanation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              explanation,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({required this.turn});

  final _ChatTurn turn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final answer = turn.answer;
    final error = turn.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                turn.question,
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (error != null)
            Text(error, style: TextStyle(color: theme.colorScheme.error))
          else if (answer == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (answer.text != null) ...[
            // Con el modelo conversando, una respuesta redactada es la
            // respuesta —haya podido citar fuentes o no—: a diferencia del
            // buscador sin modelo, acá "no encontré nada específico" ya es
            // parte de lo que el propio modelo puede decir con naturalidad,
            // no un mensaje aparte que lo reemplace.
            Text(answer.text!, style: theme.textTheme.bodyLarge),
            if (answer.sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final source in answer.sources) _SourceCard(source: source),
            ],
          ] else if (answer.sources.isNotEmpty) ...[
            Text(
              l10n.chatSourcesOnlyExplanation,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final source in answer.sources) _SourceCard(source: source),
          ] else
            Text(l10n.chatNoSourcesFound, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final ChatSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(RoutePaths.itemDetail(source.itemId)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(source.itemTitle, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                source.excerpt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un intercambio de la conversación libre: sin tarjetas de fuentes, solo el
/// mensaje y la respuesta —lo mismo que se espera de cualquier chat de
/// texto común—.
class _FreeTurnView extends StatelessWidget {
  const _FreeTurnView({required this.turn});

  final _FreeTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                turn.message,
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (turn.error != null)
            Text(turn.error!, style: TextStyle(color: theme.colorScheme.error))
          else if (!turn.done)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Text(turn.answer ?? '', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(hintText: l10n.chatInputHint),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.send),
            onPressed: enabled ? onSend : null,
          ),
        ],
      ),
    );
  }
}
