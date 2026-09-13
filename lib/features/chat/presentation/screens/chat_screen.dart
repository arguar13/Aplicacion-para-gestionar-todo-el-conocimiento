import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/chat_answer.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
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

/// Preguntarle algo a la bóveda y recibir una respuesta con sus fuentes.
///
/// Funciona en dos niveles, sin que uno bloquee al otro (principio 4:
/// degradar antes que fallar). Sin el modelo de lenguaje descargado, cada
/// pregunta ya devuelve qué elementos de la bóveda son relevantes, con un
/// fragmento de cada uno — la búsqueda de FTS5 que ya existía, aplicada
/// acá. Con el modelo descargado, además se redacta una respuesta que cita
/// esas mismas fuentes. Ver la decisión 20 en docs/arquitectura.md.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatTurn> _turns = [];
  var _modelReady = false;
  var _asking = false;

  @override
  void initState() {
    super.initState();
    _refreshModelStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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

  Future<void> _ask() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _asking) return;

    final turn = _ChatTurn(question: question);
    setState(() {
      _turns.add(turn);
      _controller.clear();
      _asking = true;
    });
    _scrollToEnd();

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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chatTitle),
        actions: [
          IconButton(
            icon: Icon(
              _modelReady ? Icons.smart_toy_outlined : Icons.download_outlined,
            ),
            tooltip: l10n.chatModelTooltip,
            onPressed: _openModelScreen,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_modelReady)
              _ModelBanner(
                message: l10n.chatModelNotReadyBanner,
                actionLabel: l10n.chatModelDownloadAction,
                onDownload: _openModelScreen,
              ),
            Expanded(
              child: _turns.isEmpty
                  ? _EmptyState(explanation: l10n.chatEmptyExplanation)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _turns.length,
                      itemBuilder: (context, index) =>
                          _TurnView(turn: _turns[index]),
                    ),
            ),
            _Composer(controller: _controller, enabled: !_asking, onSend: _ask),
          ],
        ),
      ),
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
          else if (answer.sources.isEmpty)
            Text(l10n.chatNoSourcesFound, style: theme.textTheme.bodyMedium)
          else ...[
            if (answer.text != null) ...[
              Text(answer.text!, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
            ] else ...[
              Text(
                l10n.chatSourcesOnlyExplanation,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
            ],
            for (final source in answer.sources) _SourceCard(source: source),
          ],
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
