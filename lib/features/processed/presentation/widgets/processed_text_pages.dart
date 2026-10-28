import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_part_tile.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En qué página del texto está el documento procesado `documentId`, de 0 en
/// adelante: lo que mira el lector en voz alta para empezar ahí.
final processedTextPageProvider = StateProvider.autoDispose.family<int, String>(
  (ref, documentId) => 0,
);

/// El texto de un documento procesado, **de a una página** (F41).
///
/// El texto ya está guardado en páginas (`kProcessedTextPageChars`), así que
/// se pide solo la que se mira (`processedPartsProvider` con un tramo de uno):
/// abrir un libro de 390 páginas cuesta lo que cuesta una. El lector paginado
/// de los visores (`DocumentReaderView`) no encaja acá: arma sus páginas
/// partiendo el texto entero en memoria, que es justo lo que esto evita.
///
/// Arriba, el paso de páginas —primera, anterior, «Página n de N» (tocarlo
/// lleva a una), siguiente, última— y, con el teclado, las flechas. Cada
/// página se edita o se quita como cualquier parte.
class ProcessedTextPages extends ConsumerStatefulWidget {
  const ProcessedTextPages({
    required this.documentId,
    required this.pageCount,
    required this.sourceItemId,
    super.key,
  });

  final String documentId;

  /// Cuántas páginas tiene el texto, de las cuentas del documento.
  final int pageCount;

  /// La fuente, para «Abrir en el original»; `null` si no se puede abrir.
  final String? sourceItemId;

  @override
  ConsumerState<ProcessedTextPages> createState() => _ProcessedTextPagesState();
}

class _ProcessedTextPagesState extends ConsumerState<ProcessedTextPages> {
  /// La última página que llegó: mientras se trae la próxima se sigue viendo
  /// esta, en vez de una ruedita entre página y página.
  ProcessedPart? _shown;

  void _go(int page) {
    final last = widget.pageCount - 1;
    ref.read(processedTextPageProvider(widget.documentId).notifier).state = page
        .clamp(0, last < 0 ? 0 : last);
  }

  Future<void> _jump(int current) async {
    final page = await showDialog<int>(
      context: context,
      builder: (context) =>
          _JumpDialog(pageCount: widget.pageCount, current: current),
    );
    if (page != null) _go(page);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final total = widget.pageCount;
    // Si se quitaron páginas y la de ahora ya no existe, la última.
    final page = ref
        .watch(processedTextPageProvider(widget.documentId))
        .clamp(0, total < 1 ? 0 : total - 1);
    final parts = ref.watch(
      processedPartsProvider((
        documentId: widget.documentId,
        section: ProcessedSection.text,
        offset: page,
        limit: 1,
      )),
    );
    final current = parts.valueOrNull?.firstOrNull;
    if (current != null) _shown = current;
    final shown = parts.hasValue ? current : _shown;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _go(page - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _go(page + 1),
      },
      child: Focus(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (total > 1)
              _Pager(
                page: page,
                total: total,
                onGo: _go,
                onJump: () => unawaited(_jump(page)),
              ),
            if (shown != null)
              ProcessedPartTile(
                key: ValueKey(shown.id),
                part: shown,
                sourceItemId: widget.sourceItemId,
              )
            else if (parts.isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (total > 1 && shown != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: page < total - 1 ? () => _go(page + 1) : null,
                  icon: const Icon(Icons.chevron_right),
                  label: Text(l10n.processedPageNext),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.total,
    required this.onGo,
    required this.onJump,
  });

  final int page;
  final int total;
  final ValueChanged<int> onGo;
  final VoidCallback onJump;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final atStart = page == 0;
    final atEnd = page >= total - 1;

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.first_page),
          tooltip: l10n.processedPageFirst,
          onPressed: atStart ? null : () => onGo(0),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: l10n.processedPagePrevious,
          onPressed: atStart ? null : () => onGo(page - 1),
        ),
        Expanded(
          child: Tooltip(
            message: l10n.processedPageJump,
            child: TextButton(
              key: const Key('processed-page-of'),
              onPressed: onJump,
              child: Text(
                l10n.processedPageOf(page + 1, total),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: l10n.processedPageNext,
          onPressed: atEnd ? null : () => onGo(page + 1),
        ),
        IconButton(
          icon: const Icon(Icons.last_page),
          tooltip: l10n.processedPageLast,
          onPressed: atEnd ? null : () => onGo(total - 1),
        ),
      ],
    );
  }
}

/// Elegir una página por su número, del 1 al último.
class _JumpDialog extends StatefulWidget {
  const _JumpDialog({required this.pageCount, required this.current});

  final int pageCount;
  final int current;

  @override
  State<_JumpDialog> createState() => _JumpDialogState();
}

class _JumpDialogState extends State<_JumpDialog> {
  late final _controller = TextEditingController(text: '${widget.current + 1}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// La página elegida, de 0 en adelante, o `null` si no es una que exista.
  int? get _chosen {
    final number = int.tryParse(_controller.text.trim());
    if (number == null || number < 1 || number > widget.pageCount) return null;
    return number - 1;
  }

  void _submit() {
    final chosen = _chosen;
    if (chosen != null) Navigator.of(context).pop(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.processedPageJump),
      content: TextField(
        key: const Key('processed-page-jump'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: l10n.processedPageJumpHint(widget.pageCount),
          helperText: l10n.processedPageJumpHint(widget.pageCount),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, _, _) => FilledButton(
            onPressed: _chosen == null ? null : _submit,
            child: Text(l10n.processedPageJumpGo),
          ),
        ),
      ],
    );
  }
}
