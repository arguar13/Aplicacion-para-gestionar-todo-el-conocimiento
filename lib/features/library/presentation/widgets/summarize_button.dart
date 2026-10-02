import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_selection_aloud.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántos caracteres de [content] se le mandan al modelo para resumir. Un
/// libro entero desbordaría la ventana de contexto antes de llegar a
/// redactar nada; con un tope, el resumen sale de lo que alcanza a leer,
/// que para el propósito de "dame la idea general" es más que suficiente
/// — mismo criterio que `_kAttachmentTextBudget` en el compositor del
/// chat.
const _kSummarizeContentBudget = 8000;

/// El botón "Resumir con IA": pide un resumen de [content] al modelo de
/// lenguaje ya cargado y lo muestra en un diálogo, con su propio botón de
/// copiar.
///
/// Sin el modelo descargado, no hay nada que resumir —a diferencia del
/// chat en modo bóveda, acá no hay una versión "solo buscador" de un
/// resumen—, así que se avisa y se ofrece ir a descargarlo, en vez de
/// deshabilitar el botón sin explicar por qué.
class SummarizeButton extends ConsumerStatefulWidget {
  const SummarizeButton({required this.content, super.key});

  final String content;

  @override
  ConsumerState<SummarizeButton> createState() => _SummarizeButtonState();
}

class _SummarizeButtonState extends ConsumerState<SummarizeButton> {
  var _loading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return TextButton.icon(
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome_outlined, size: 18),
      label: Text(l10n.summarizeAction),
      onPressed: _loading ? null : _summarize,
    );
  }

  Future<void> _summarize() async {
    final l10n = AppLocalizations.of(context)!;
    final ready = await ref.read(chatModelManagerProvider).isReady();
    if (!mounted) return;

    if (!ready) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.summarizeModelRequired),
            action: SnackBarAction(
              label: l10n.summarizeDownloadAction,
              onPressed: () => context.push(RoutePaths.chatModel),
            ),
          ),
        );
      return;
    }

    setState(() => _loading = true);
    final truncated = widget.content.length > _kSummarizeContentBudget
        ? widget.content.substring(0, _kSummarizeContentBudget)
        : widget.content;

    String? summary;
    try {
      summary = await ref
          .read(summarizationServiceProvider)
          .summarize(content: truncated);
      // El motor de inferencia es de terceros (flutter_gemma); puede fallar
      // de formas que no tienen un tipo propio en Dart.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.summarizeError)));
      return;
    }

    if (!mounted) return;
    // El diálogo se cierra recién cuando la persona lo cierra: el ícono de
    // "cargando" tiene que apagarse antes de abrirlo, no cuando el diálogo
    // se cierre — si no, quedaría girando por detrás todo ese tiempo.
    setState(() => _loading = false);
    await _showSummary(context, summary);
  }

  Future<void> _showSummary(BuildContext context, String summary) async {
    final l10n = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.summarizeDialogTitle),
        content: SingleChildScrollView(
          child: SelectableText(
            summary,
            style: Theme.of(context).textTheme.bodyMedium,
            // El menú de la app; el resumen no es parte de lo que la
            // pantalla ofrece para leer, así que se lee lo seleccionado tal
            // cual (F25).
            contextMenuBuilder: (context, editable) => buildSelectionMenu(
              context,
              editable,
              onReadAloud: () => unawaited(
                readSelectionAloud(
                  ref,
                  text: editable.textEditingValue.selection.textInside(summary),
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: Text(l10n.summarizeCopyAction),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: summary));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(l10n.summarizeCopied)));
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
  }
}
