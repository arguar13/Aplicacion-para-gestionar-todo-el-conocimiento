import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/network/model_download_providers.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/chat/presentation/providers/hugging_face_token_notifier.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/features/transform/presentation/widgets/model_download_progress.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

const _modelPageUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m';
const _tokenPageUrl = 'https://huggingface.co/settings/tokens';

/// Si el modelo de embeddings del motor de relaciones está descargado, y
/// descargarlo si no.
///
/// Calco de `ChatModelScreen`, sin selector de variantes: un solo modelo
/// fijo (ver la decisión sobre F5, D9) — nadie interactúa directo con "el
/// embedder", solo se beneficia de que exista. Reusa
/// [huggingFaceTokenNotifierProvider] del feature `chat` tal cual: es el
/// mismo token de la misma cuenta, no uno aparte por modelo.
class EmbeddingModelScreen extends ConsumerStatefulWidget {
  const EmbeddingModelScreen({super.key});

  @override
  ConsumerState<EmbeddingModelScreen> createState() =>
      _EmbeddingModelScreenState();
}

class _EmbeddingModelScreenState extends ConsumerState<EmbeddingModelScreen> {
  var _checkingStatus = true;
  var _isReady = false;
  int? _downloadSizeInBytes;

  // La descarga en sí —su avance, su error— no vive acá sino en
  // `embeddingModelDownloadProvider`: sigue aunque se salga de esta
  // pantalla, y al volver se ve cuánto va en vez de ofrecer bajarlo de
  // nuevo.

  /// Inicializado en [initState], no como `late final` perezoso: si el
  /// modelo ya está listo desde el primer build, `_body()` nunca visita
  /// la rama que lo usa —y un campo perezoso que recién se evalúa en
  /// [dispose] intenta leer `ref` justo cuando el widget ya no puede.
  late final TextEditingController _tokenController;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(
      text: ref.read(huggingFaceTokenNotifierProvider) ?? '',
    );
    unawaited(_checkStatus());
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final manager = ref.read(embeddingModelManagerProvider);
    final ready = await manager.isReady();
    if (!mounted) return;

    setState(() {
      _isReady = ready;
      _checkingStatus = false;
    });

    if (!ready) unawaited(_loadDownloadSize());
  }

  Future<void> _loadDownloadSize() async {
    final size = await ref
        .read(embeddingModelManagerProvider)
        .downloadSizeInBytes();
    if (!mounted) return;

    setState(() => _downloadSizeInBytes = size);
  }

  void _startDownload() {
    unawaited(
      ref
          .read(huggingFaceTokenNotifierProvider.notifier)
          .setToken(_tokenController.text),
    );

    // Si ya hay una en curso, no arranca otra: dos descargas escribiendo
    // el mismo archivo lo dejarían corrupto.
    ref
        .read(embeddingModelDownloadProvider.notifier)
        .start(
          () => ref
              .read(embeddingModelManagerProvider)
              .download(
                huggingFaceToken: ref.read(huggingFaceTokenNotifierProvider),
              ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final download = ref.watch(embeddingModelDownloadProvider);
    // Terminó —con esta pantalla abierta o no—: se vuelve a mirar si el
    // modelo quedó listo.
    ref.listen(embeddingModelDownloadProvider, (previous, next) {
      if (previous is ModelDownloadRunning && next is ModelDownloadIdle) {
        unawaited(_checkStatus());
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.embeddingModelTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
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
    if (_isReady) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ReadyView(message: l10n.embeddingModelReady),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => context.push(RoutePaths.embeddingBackfill),
            child: Text(l10n.embeddingBackfillAction),
          ),
        ],
      );
    }

    if (download case ModelDownloadRunning(:final progress)) {
      return ModelDownloadProgress(
        progress: progress,
        label: l10n.embeddingModelDownloading(
          (progress * 100).round().toString(),
        ),
        continuesWithAppClosed: ref
            .watch(modelFileTransferProvider)
            .continuesWithAppClosed,
        onCancel: () => unawaited(
          ref
              .read(embeddingModelDownloadProvider.notifier)
              .cancel(ref.read(embeddingModelManagerProvider).cancelDownload),
        ),
      );
    }

    final failure = download is ModelDownloadFailed ? download.error : null;
    final error = switch (failure) {
      null => null,
      final EmbeddingModelDownloadError error => error,
      final other => EmbeddingModelDownloadFailed('$other'),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null) ...[
          _ErrorView(
            message:
                modelDownloadSpaceMessage(l10n, failure!) ??
                switch (error) {
                  EmbeddingModelNeedsAuthentication() =>
                    l10n.embeddingModelAuthRequired,
                  EmbeddingModelDownloadFailed() => l10n.embeddingModelError,
                },
          ),
          const SizedBox(height: 24),
        ] else ...[
          Icon(
            Icons.hub_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(l10n.embeddingModelExplanation, textAlign: TextAlign.center),
          if (_downloadSizeInBytes != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.embeddingModelSize(
                formatFileSize(_downloadSizeInBytes!, l10n.localeName),
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
        _TokenSection(controller: _tokenController),
        const SizedBox(height: 24),
        PrimaryButton(
          label: error == null
              ? l10n.embeddingModelDownloadAction
              : l10n.embeddingModelRetryAction,
          onPressed: _startDownload,
        ),
      ],
    );
  }
}

/// Pedir y guardar el token de acceso de Hugging Face, con la explicación
/// de por qué hace falta — mismo texto y mismo patrón que `_TokenSection`
/// de `ChatModelScreen`, sin el parámetro de opción: acá solo hay un
/// modelo.
class _TokenSection extends StatelessWidget {
  const _TokenSection({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.embeddingModelTokenExplanation,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _LinkText(label: l10n.chatModelTokenAcceptLicense, url: _modelPageUrl),
        _LinkText(label: l10n.chatModelTokenGenerate, url: _tokenPageUrl),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: l10n.chatModelTokenLabel,
            hintText: l10n.chatModelTokenHint,
            border: const OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ],
    );
  }
}

/// Una URL como texto seleccionable, para copiarla a mano — mismo patrón
/// que `_LinkText` de `ChatModelScreen`.
class _LinkText extends StatelessWidget {
  const _LinkText({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SelectableText.rich(
        contextMenuBuilder: buildSelectionMenu,
        TextSpan(
          children: [
            TextSpan(text: '$label: ', style: theme.textTheme.bodySmall),
            TextSpan(
              text: url,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }
}
