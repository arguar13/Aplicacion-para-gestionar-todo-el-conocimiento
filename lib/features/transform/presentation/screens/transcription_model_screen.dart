import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Si el modelo de transcripción está descargado, y descargarlo si no.
///
/// Una pantalla propia y no un diálogo, a propósito: son cientos de megas, la
/// descarga puede tardar, y quien la mira tiene que poder navegar a otro
/// lado sin perder el progreso —la descarga sigue viva aparte de la
/// pantalla, ver `transcriptionModelDownloadProvider`, y al volver se ve
/// cuánto va—.
///
/// Nada se descarga solo. El principio 1 de la arquitectura es tajante: las
/// únicas conexiones salientes son las que el usuario pide explícitamente, y
/// acá el pedido es un botón, no una descarga que arranca al abrir la app.
class TranscriptionModelScreen extends ConsumerStatefulWidget {
  const TranscriptionModelScreen({super.key});

  @override
  ConsumerState<TranscriptionModelScreen> createState() =>
      _TranscriptionModelScreenState();
}

class _TranscriptionModelScreenState
    extends ConsumerState<TranscriptionModelScreen> {
  var _checkingStatus = true;
  var _isReady = false;
  int? _downloadSizeInBytes;

  @override
  void initState() {
    super.initState();
    unawaited(_checkStatus());
  }

  Future<void> _checkStatus() async {
    final manager = ref.read(whisperModelManagerProvider);
    final ready = await manager.isReady();
    // También al abrir con el modelo ya descargado: la descarga sigue aunque
    // se salga de esta pantalla, y entonces nadie vio terminarla.
    if (ready) _resumeWaitingForModel();
    if (!mounted) return;

    setState(() {
      _isReady = ready;
      _checkingStatus = false;
    });

    if (!ready) unawaited(_loadDownloadSize());
  }

  Future<void> _loadDownloadSize() async {
    final size = await ref
        .read(whisperModelManagerProvider)
        .downloadSizeInBytes();
    if (!mounted) return;

    setState(() => _downloadSizeInBytes = size);
  }

  void _startDownload() {
    // Si ya hay una en curso, no arranca otra. Al terminar, lo que esperaba
    // el modelo vuelve a la cola desde el proveedor, aunque esta pantalla ya
    // no esté.
    ref
        .read(transcriptionModelDownloadProvider.notifier)
        .start(() => ref.read(whisperModelManagerProvider).download());
  }

  /// Lo que falló porque faltaba este modelo vuelve a quedar en espera, y la
  /// cola —que sigue a la base— lo retoma sola: nadie tiene que ir audio por
  /// audio a tocar "Reintentar" (F21).
  void _resumeWaitingForModel() {
    unawaited(
      ref
          .read(processingStateRepositoryProvider)
          .requeueFailedWith(ProcessingFailureReason.transcriptionModelMissing)
          .catchError((Object _) => 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final download = ref.watch(transcriptionModelDownloadProvider);
    // Terminó —con esta pantalla abierta o no—: se vuelve a mirar si el
    // modelo quedó listo.
    ref.listen(transcriptionModelDownloadProvider, (previous, next) {
      if (previous is ModelDownloadRunning && next is ModelDownloadIdle) {
        unawaited(_checkStatus());
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.transcriptionModelTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _checkingStatus
                  ? const Center(child: CircularProgressIndicator())
                  : _body(l10n, download),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n, ModelDownloadState download) {
    if (_isReady) return _ReadyView(message: l10n.transcriptionModelReady);

    if (download case ModelDownloadRunning(:final progress)) {
      return _DownloadingView(
        progress: progress,
        label: l10n.transcriptionModelDownloading(
          (progress * 100).round().toString(),
        ),
      );
    }

    if (download is ModelDownloadFailed) {
      return _ErrorView(
        message: l10n.transcriptionModelError,
        onRetry: _startDownload,
        retryLabel: l10n.transcriptionModelRetryAction,
      );
    }

    return _NotDownloadedView(
      explanation: l10n.transcriptionModelExplanation,
      sizeLabel: _downloadSizeInBytes == null
          ? null
          : l10n.transcriptionModelSize(
              formatFileSize(_downloadSizeInBytes!, l10n.localeName),
            ),
      actionLabel: l10n.transcriptionModelDownloadAction,
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
          Icons.mic_none_outlined,
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
