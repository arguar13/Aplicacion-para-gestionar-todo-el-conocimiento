import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Si el modelo de lenguaje del chat está descargado, y descargarlo si no.
///
/// Calco de `TranscriptionModelScreen` (Fase 7, decisión 8): mismos
/// principios, mismo motivo. Es una pantalla propia y no un diálogo porque
/// la descarga pesa cientos de megas y puede tardar; nada se baja solo, el
/// pedido tiene que ser un botón que el usuario toca.
class ChatModelScreen extends ConsumerStatefulWidget {
  const ChatModelScreen({super.key});

  @override
  ConsumerState<ChatModelScreen> createState() => _ChatModelScreenState();
}

class _ChatModelScreenState extends ConsumerState<ChatModelScreen> {
  var _checkingStatus = true;
  var _isReady = false;
  int? _downloadSizeInBytes;

  double? _downloadProgress;
  Object? _error;

  StreamSubscription<double>? _downloadSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_checkStatus());
  }

  @override
  void dispose() {
    unawaited(_downloadSubscription?.cancel());
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final manager = ref.read(chatModelManagerProvider);
    final ready = await manager.isReady();
    if (!mounted) return;

    setState(() {
      _isReady = ready;
      _checkingStatus = false;
    });

    if (!ready) unawaited(_loadDownloadSize());
  }

  Future<void> _loadDownloadSize() async {
    final size = await ref.read(chatModelManagerProvider).downloadSizeInBytes();
    if (!mounted) return;

    setState(() => _downloadSizeInBytes = size);
  }

  void _startDownload() {
    setState(() {
      _downloadProgress = 0;
      _error = null;
    });

    _downloadSubscription = ref
        .read(chatModelManagerProvider)
        .download()
        .listen(
          (progress) {
            if (!mounted) return;
            setState(() => _downloadProgress = progress);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _downloadProgress = null;
              _error = error;
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() {
              _downloadProgress = null;
              _isReady = true;
            });
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.chatModelTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _checkingStatus
                  ? const Center(child: CircularProgressIndicator())
                  : _body(l10n),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_isReady) return _ReadyView(message: l10n.chatModelReady);

    final progress = _downloadProgress;
    if (progress != null) {
      return _DownloadingView(
        progress: progress,
        label: l10n.chatModelDownloading((progress * 100).round().toString()),
      );
    }

    final error = _error;
    if (error != null) {
      return _ErrorView(
        message: l10n.chatModelError,
        onRetry: _startDownload,
        retryLabel: l10n.chatModelRetryAction,
      );
    }

    return _NotDownloadedView(
      explanation: l10n.chatModelExplanation,
      sizeLabel: _downloadSizeInBytes == null
          ? null
          : l10n.chatModelSize(formatFileSize(_downloadSizeInBytes!)),
      actionLabel: l10n.chatModelDownloadAction,
      onDownload: _startDownload,
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }
}

class _NotDownloadedView extends StatelessWidget {
  const _NotDownloadedView({
    required this.explanation,
    required this.sizeLabel,
    required this.actionLabel,
    required this.onDownload,
  });

  final String explanation;
  final String? sizeLabel;
  final String actionLabel;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.chat_bubble_outline,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(explanation, textAlign: TextAlign.center),
        if (sizeLabel != null) ...[
          const SizedBox(height: 8),
          Text(
            sizeLabel!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 24),
        PrimaryButton(label: actionLabel, onPressed: onDownload),
      ],
    );
  }
}

class _DownloadingView extends StatelessWidget {
  const _DownloadingView({required this.progress, required this.label});

  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 16),
        Text(label),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        PrimaryButton(label: retryLabel, onPressed: onRetry),
      ],
    );
  }
}
