import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/external_url_launcher.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre la página donde se crea una clave de [provider]; si no se puede, dice
/// la dirección para copiarla.
Future<void> openKeysPage(BuildContext context, AiProvider provider) async {
  final url = provider.keysUrl;
  if (url == null) return;
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (await launchExternalUrl(url)) return;
  messenger?.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: SelectableText(l10n.lmCouldNotOpenLink(url)),
    ),
  );
}

/// La hoja para agregar una cuenta de [provider] —o, con [replacing],
/// cambiarle la clave—. La clave se prueba antes de guardarla: si no anda,
/// se dice por qué y no se guarda nada. Devuelve si se guardó.
Future<bool> showAiKeySheet(
  BuildContext context, {
  required AiProvider provider,
  AiAccount? replacing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _AiKeySheet(provider: provider, replacing: replacing),
  );
  return saved ?? false;
}

class _AiKeySheet extends ConsumerStatefulWidget {
  const _AiKeySheet({required this.provider, this.replacing});

  final AiProvider provider;
  final AiAccount? replacing;

  @override
  ConsumerState<_AiKeySheet> createState() => _AiKeySheetState();
}

class _AiKeySheetState extends ConsumerState<_AiKeySheet> {
  final _name = TextEditingController();
  final _key = TextEditingController();
  var _showKey = false;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _key.addListener(_keyChanged);
  }

  @override
  void dispose() {
    _key
      ..removeListener(_keyChanged)
      ..dispose();
    _name.dispose();
    super.dispose();
  }

  /// La clave que se vio la última vez: el controlador avisa también cuando
  /// cambia la selección o el foco, y eso no es una clave nueva.
  var _lastKey = '';

  /// Redibuja el botón, que se habilita con una clave escrita; y el error de
  /// la clave anterior ya no vale para la nueva.
  void _keyChanged() {
    if (_key.text == _lastKey) return;
    _lastKey = _key.text;
    setState(() => _error = null);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _key.text = text;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final key = _key.text.trim();
    if (key.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final actions = ref.read(aiAccountActionsProvider);
    try {
      final replacing = widget.replacing;
      if (replacing != null) {
        await actions.replaceKey(replacing, key);
      } else {
        final name = _name.text.trim();
        await actions.add(
          provider: widget.provider,
          key: key,
          label: name.isEmpty ? null : name,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on CloudModelException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.lmTestFailed(aiFailureReason(l10n, error.failure));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = widget.provider;
    final replacing = widget.replacing;
    final providerName = provider.label(l10n);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primaryContainer,
                  ),
                  child: Icon(provider.icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    replacing == null
                        ? l10n.lmAddTitle(providerName)
                        : l10n.lmReplaceKeyTitle(replacing.label),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.lmAddGetKeyStep(providerName),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const Key('ai-key-get'),
                onPressed: () => unawaited(openKeysPage(context, provider)),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(l10n.lmGetKey),
              ),
            ),
            const SizedBox(height: 20),
            if (replacing == null) ...[
              TextField(
                key: const Key('ai-key-name'),
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.lmNameLabel,
                  hintText: l10n.lmNameHint,
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              key: const Key('ai-key-value'),
              controller: _key,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              onSubmitted: (_) => unawaited(_save()),
              decoration: InputDecoration(
                labelText: l10n.lmKeyLabel,
                prefixIcon: const Icon(Icons.key_outlined),
                errorText: _error,
                errorMaxLines: 3,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n.lmPaste,
                      onPressed: () => unawaited(_paste()),
                      icon: const Icon(Icons.content_paste),
                    ),
                    IconButton(
                      tooltip: _showKey ? l10n.lmHideKey : l10n.lmShowKey,
                      onPressed: () => setState(() => _showKey = !_showKey),
                      icon: Icon(
                        _showKey ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.lmKeyStoredSafely,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('ai-key-save'),
              onPressed: _key.text.trim().isEmpty || _saving
                  ? null
                  : () => unawaited(_save()),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(_saving ? l10n.lmTesting : l10n.lmTestAndSave),
            ),
          ],
        ),
      ),
    );
  }
}
