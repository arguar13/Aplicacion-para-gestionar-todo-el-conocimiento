import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/external_url_launcher.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/image_requirement_lines.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja para agregar una cuenta de Hugging Face —o, con [replacing],
/// cambiarle el token— (F43), con el mismo estilo que la de claves de F32:
/// el token se prueba antes de guardarlo y, si no anda, se dice por qué y no
/// se guarda nada. Devuelve si se guardó.
Future<bool> showHuggingFaceTokenSheet(
  BuildContext context, {
  IllustrationAccount? replacing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _HuggingFaceTokenSheet(replacing: replacing),
  );
  return saved ?? false;
}

class _HuggingFaceTokenSheet extends ConsumerStatefulWidget {
  const _HuggingFaceTokenSheet({this.replacing});

  final IllustrationAccount? replacing;

  @override
  ConsumerState<_HuggingFaceTokenSheet> createState() =>
      _HuggingFaceTokenSheetState();
}

class _HuggingFaceTokenSheetState
    extends ConsumerState<_HuggingFaceTokenSheet> {
  final _name = TextEditingController();
  final _key = TextEditingController();
  var _lastKey = '';
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

  Future<void> _openTokens() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final url = IllustrationProvider.huggingFace.keysUrl!;
    if (await launchExternalUrl(url)) return;
    messenger?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: SelectableText(l10n.f43AiOpenLinkFailed(url)),
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final key = _key.text.trim();
    if (key.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final actions = ref.read(illustrationActionsProvider);
    try {
      final replacing = widget.replacing;
      if (replacing != null) {
        await actions.replaceKey(replacing, key);
      } else {
        final name = _name.text.trim();
        await actions.addHuggingFace(
          key: key,
          label: name.isEmpty ? null : name,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ImageGenerationException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.lmTestFailed(
          illustrationReason(
            l10n,
            error.failure,
            account: widget.replacing?.label ?? l10n.f43AiProviderHuggingFace,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final replacing = widget.replacing;

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
                  child: Icon(
                    IllustrationProvider.huggingFace.icon,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    replacing == null
                        ? l10n.f43AiHfTitle
                        : l10n.f43AiHfReplaceTitle(replacing.label),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const ImageRequirementLines(provider: null),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const Key('hf-token-get'),
                onPressed: () => unawaited(_openTokens()),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(l10n.f43AiHfGetToken),
              ),
            ),
            const SizedBox(height: 20),
            if (replacing == null) ...[
              TextField(
                key: const Key('hf-token-name'),
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
              key: const Key('hf-token-value'),
              controller: _key,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              onSubmitted: (_) => unawaited(_save()),
              decoration: InputDecoration(
                labelText: l10n.f43AiHfTokenLabel,
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
              key: const Key('hf-token-save'),
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
