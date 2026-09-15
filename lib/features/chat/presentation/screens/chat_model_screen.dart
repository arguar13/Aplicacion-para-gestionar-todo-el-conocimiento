import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_model_option_notifier.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/hugging_face_token_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La página del modelo en Hugging Face, para aceptar su licencia, según
/// cuál [ChatModelOption] esté elegida — las dos viven en repositorios
/// protegidos distintos, así que la licencia que hay que aceptar es
/// distinta según cuál se vaya a bajar. Se muestra como texto seleccionable
/// y no como enlace: abrir un navegador desde acá exigiría un paquete
/// aparte (`url_launcher`) solo para esto.
String _modelPageUrl(ChatModelOption option) => switch (option) {
  ChatModelOption.gemma4E4b =>
    'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm',
  ChatModelOption.gemma3nE4b =>
    'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm',
};
const _tokenPageUrl = 'https://huggingface.co/settings/tokens';

/// Si el modelo de lenguaje del chat está descargado, y descargarlo si no.
///
/// Calco de `TranscriptionModelScreen` (Fase 7, decisión 8): mismos
/// principios, mismo motivo. Es una pantalla propia y no un diálogo porque
/// la descarga pesa cientos de megas y puede tardar; nada se baja solo, el
/// pedido tiene que ser un botón que el usuario toca.
///
/// A diferencia de Whisper, Gemma vive en un repositorio protegido de
/// Hugging Face —Google exige aceptar su licencia con una cuenta antes de
/// dejar bajar el archivo, ver la decisión 20 y `GemmaChatModelManager`—,
/// así que esta pantalla también pide el token de acceso que esa cuenta
/// genera, y lo recuerda entre reinicios.
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
  ChatModelDownloadError? _error;

  StreamSubscription<double>? _downloadSubscription;
  late final _tokenController = TextEditingController(
    text: ref.read(huggingFaceTokenNotifierProvider) ?? '',
  );

  @override
  void initState() {
    super.initState();
    unawaited(_checkStatus());
  }

  @override
  void dispose() {
    unawaited(_downloadSubscription?.cancel());
    _tokenController.dispose();
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

  /// Cambia qué [ChatModelOption] gestiona esta pantalla y vuelve a
  /// consultar su estado desde cero: una opción recién elegida puede estar
  /// lista, a medio bajar de una sesión anterior, o sin empezar, y nada de
  /// eso tiene por qué coincidir con lo que valía para la opción anterior.
  Future<void> _selectOption(ChatModelOption option) async {
    if (option == ref.read(chatModelOptionNotifierProvider)) return;

    await _downloadSubscription?.cancel();
    _downloadSubscription = null;
    await ref.read(chatModelOptionNotifierProvider.notifier).select(option);
    if (!mounted) return;

    setState(() {
      _checkingStatus = true;
      _isReady = false;
      _downloadSizeInBytes = null;
      _downloadProgress = null;
      _error = null;
    });
    await _checkStatus();
  }

  void _startDownload() {
    unawaited(
      ref
          .read(huggingFaceTokenNotifierProvider.notifier)
          .setToken(_tokenController.text),
    );

    setState(() {
      _downloadProgress = 0;
      _error = null;
    });

    _downloadSubscription = ref
        .read(chatModelManagerProvider)
        .download(huggingFaceToken: ref.read(huggingFaceTokenNotifierProvider))
        .listen(
          (progress) {
            if (!mounted) return;
            setState(() => _downloadProgress = progress);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _downloadProgress = null;
              _error = error is ChatModelDownloadError
                  ? error
                  : ChatModelDownloadFailed(error.toString());
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
    final selectedOption = ref.watch(chatModelOptionNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.chatModelTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ModelOptionSelector(
                    selected: selectedOption,
                    // Cambiar de opción a mitad de una descarga la
                    // cancela (ver `_selectOption`), así que se
                    // deshabilita mientras hay una en curso: elegirla por
                    // accidente ahí perdería el progreso sin avisar.
                    onSelected: _downloadProgress == null
                        ? _selectOption
                        : null,
                  ),
                  const SizedBox(height: 24),
                  if (_checkingStatus)
                    const Center(child: CircularProgressIndicator())
                  else
                    _body(l10n, selectedOption),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n, ChatModelOption option) {
    if (_isReady) return _ReadyView(message: l10n.chatModelReady);

    final progress = _downloadProgress;
    if (progress != null) {
      return _DownloadingView(
        progress: progress,
        label: l10n.chatModelDownloading((progress * 100).round().toString()),
      );
    }

    final error = _error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null) ...[
          _ErrorView(
            message: switch (error) {
              ChatModelNeedsAuthentication() => l10n.chatModelAuthRequired,
              ChatModelDownloadFailed() => l10n.chatModelError,
            },
          ),
          const SizedBox(height: 24),
        ] else ...[
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(l10n.chatModelExplanation, textAlign: TextAlign.center),
          if (_downloadSizeInBytes != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.chatModelSize(formatFileSize(_downloadSizeInBytes!)),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
        _TokenSection(controller: _tokenController, option: option),
        const SizedBox(height: 24),
        PrimaryButton(
          label: error == null
              ? l10n.chatModelDownloadAction
              : l10n.chatModelRetryAction,
          onPressed: _startDownload,
        ),
      ],
    );
  }
}

/// Elegir entre las opciones de [ChatModelOption], antes de mostrar nada
/// sobre la descarga en sí: la opción elegida decide qué repositorio, qué
/// licencia y qué tamaño le siguen a esto, así que va primero.
///
/// Un [SegmentedButton] y no dos botones sueltos: dejan clarísimo que es
/// una elección excluyente entre dos caminos, no dos acciones
/// independientes que se puedan tocar las dos.
class _ModelOptionSelector extends StatelessWidget {
  const _ModelOptionSelector({
    required this.selected,
    required this.onSelected,
  });

  final ChatModelOption selected;

  /// `null` mientras hay una descarga en curso: cambiar de opción ahí la
  /// cancelaría sin avisar, así que el selector se deshabilita en vez de
  /// permitirlo.
  final ValueChanged<ChatModelOption>? onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.chatModelOptionTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<ChatModelOption>(
          segments: [
            ButtonSegment(
              value: ChatModelOption.gemma4E4b,
              label: Text(l10n.chatModelOptionGemma4Title),
            ),
            ButtonSegment(
              value: ChatModelOption.gemma3nE4b,
              label: Text(l10n.chatModelOptionGemma3nTitle),
            ),
          ],
          selected: {selected},
          onSelectionChanged: onSelected == null
              ? null
              : (selection) => onSelected!(selection.single),
        ),
        const SizedBox(height: 4),
        Text(
          switch (selected) {
            ChatModelOption.gemma4E4b => l10n.chatModelOptionGemma4Description,
            ChatModelOption.gemma3nE4b =>
              l10n.chatModelOptionGemma3nDescription,
          },
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Pedir y guardar el token de acceso de Hugging Face, con la explicación
/// de por qué hace falta.
///
/// Siempre visible, y no solo tras un primer intento fallido: sin él, la
/// primera descarga fracasaría siempre —el repositorio es privado sin
/// autenticarse—, así que no tiene sentido dejar que alguien lo intente a
/// ciegas una vez para recién ahí pedirle el token.
class _TokenSection extends StatelessWidget {
  const _TokenSection({required this.controller, required this.option});

  final TextEditingController controller;
  final ChatModelOption option;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.chatModelTokenExplanation,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _LinkText(
          label: l10n.chatModelTokenAcceptLicense,
          url: _modelPageUrl(option),
        ),
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
/// que `_OriginalLink` en el detalle de un elemento, y por el mismo motivo:
/// abrir un navegador desde acá exigiría un paquete que hoy no está.
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
