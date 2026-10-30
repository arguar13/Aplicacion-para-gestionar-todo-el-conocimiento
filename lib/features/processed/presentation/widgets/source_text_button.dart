import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel_more.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Si el texto de una fuente de [kind] puede tener algo que hacer desde su
/// documento procesado: volver a extraerlo —un audio, un video, un documento,
/// una foto, un video de YouTube—, quitarle las marcas de tiempo —una
/// transcripción— o soltarlo —un libro o un documento—. Ver
/// `sourceMoreActionsFor`, que decide con el elemento entero.
///
/// Una página web, una publicación o una referencia no tienen nada de eso:
/// volver a bajarlas no es volver a leer el mismo original.
bool offersSourceTextActions(SourceKind kind) => switch (kind) {
  SourceKind.youtube ||
  SourceKind.audio ||
  SourceKind.video ||
  SourceKind.document ||
  SourceKind.image => true,
  _ => false,
};

/// «El texto de la fuente» (F45, paso 3): en el documento procesado, lo que
/// estaba en el «Más» de la fuente en la Biblioteca —volver a extraer el texto,
/// quitarle las marcas de tiempo, soltar el texto de un libro—, con la misma
/// hoja, las mismas opciones y lo mismo al tocarlas.
///
/// Se mudó porque la Biblioteca muestra solo el original (decisión E): su
/// texto se lee, se marca y se estudia acá. Lo que se hace sigue siendo sobre
/// la fuente —es el texto que la búsqueda, el chat y los vínculos usan—, y la
/// hoja lo dice: el texto nuevo llega a este documento con «Volver a triar».
///
/// La fuente se lee entera recién al tocarlo, no al abrir el documento: el
/// documento procesado nunca trae el texto entero de un libro a la pantalla, y
/// lo que ofrece la hoja depende de ese texto —si tiene marcas de tiempo, si
/// tiene algo que soltar—. Mientras la lee, el botón espera.
class SourceTextButton extends ConsumerStatefulWidget {
  const SourceTextButton({required this.sourceItemId, super.key});

  final String sourceItemId;

  @override
  ConsumerState<SourceTextButton> createState() => _SourceTextButtonState();
}

class _SourceTextButtonState extends ConsumerState<SourceTextButton> {
  var _loading = false;

  Future<void> _open() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _loading = true);
    final found = await ref
        .read(libraryRepositoryProvider)
        .findById(widget.sourceItemId);
    if (!mounted) return;
    setState(() => _loading = false);

    final failure = found.getLeft().toNullable();
    if (failure != null) {
      await showSourceMoreNotice(
        context,
        title: l10n.f45S3SourceText,
        note: failure.localizedMessage(l10n),
      );
      return;
    }
    // Sin la fuente no hay nada que hacer: se borró mientras tanto, y la
    // tarjeta deja de ofrecer el botón con el próximo cambio.
    final item = found.getRight().toNullable();
    if (item == null) return;

    final actions = sourceMoreActionsFor(item);
    // Sin opciones, la hoja igual: con el motivo, en vez de un botón que no
    // hace nada al tocarlo.
    await showSourceMoreSheet(
      context,
      ref,
      item,
      actions,
      title: l10n.f45S3SourceText,
      note: actions.isNotEmpty
          ? l10n.f45S3SourceTextNote
          : item.isBeingProcessed
          ? l10n.f45S3SourceTextBusy
          : l10n.f45S3SourceTextNothing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: l10n.f45S3SourceTextHint,
      child: OutlinedButton.icon(
        key: const Key('processed-source-text'),
        onPressed: _loading ? null : () => unawaited(_open()),
        icon: _loading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.notes_outlined),
        label: Text(l10n.f45S3SourceText),
      ),
    );
  }
}
