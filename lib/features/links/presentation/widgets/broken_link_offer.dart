import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El aviso del editor cuando un `[[Título]]` no tiene ninguna nota con ese
/// título: "Esa nota no existe. ¿La creamos?", con el subtipo a elegir y
/// `living` por defecto —el caso frecuente—.
///
/// Enlazar primero y crear la nota después es el flujo natural de destilar,
/// así que la oferta aparece en el momento, sin salir del editor.
///
/// Nada de lo que hay acá puede quitarle el foco al campo en el que se
/// escribe. Son dos mecanismos distintos y hacen falta los dos: en escritorio
/// un botón al que se hace clic toma el foco —`ExcludeFocus` lo impide—, y un
/// campo de texto suelta el suyo ante cualquier clic fuera de él
/// —`TextFieldTapRegion` hace que un clic acá cuente como un clic adentro—.
class BrokenLinkOffer extends StatefulWidget {
  const BrokenLinkOffer({
    required this.title,
    required this.onCreate,
    required this.onDismiss,
    this.moreCount = 0,
    this.busy = false,
    super.key,
  });

  /// El título como se escribió entre corchetes: con él se crea la nota.
  final String title;

  /// Cuántos enlaces más sin nota hay, además de este.
  final int moreCount;

  /// Mientras la nota se crea, los controles no responden: una segunda
  /// pulsación crearía dos.
  final bool busy;

  final ValueChanged<NoteKind> onCreate;
  final VoidCallback onDismiss;

  @override
  State<BrokenLinkOffer> createState() => _BrokenLinkOfferState();
}

class _BrokenLinkOfferState extends State<BrokenLinkOffer> {
  NoteKind _kind = NoteKind.living;

  @override
  void didUpdateWidget(BrokenLinkOffer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cada enlace se ofrece con el subtipo por defecto: haber elegido "mapa"
    // para uno no lo deja elegido para el siguiente.
    if (oldWidget.title != widget.title) _kind = NoteKind.living;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = !widget.busy;

    return TextFieldTapRegion(
      child: ExcludeFocus(
        child: Card(
          margin: EdgeInsets.zero,
          color: scheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.link_off,
                        size: 20,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.blocksBrokenLinkTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                          Text(
                            '[[${widget.title}]]',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                          if (widget.moreCount > 0)
                            Text(
                              l10n.blocksBrokenLinkMore(widget.moreCount),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  label: l10n.blocksBrokenLinkKind,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final kind in NoteKind.values)
                        ChoiceChip(
                          avatar: Icon(kind.icon, size: 18),
                          label: Text(kind.label(l10n)),
                          selected: _kind == kind,
                          showCheckmark: false,
                          onSelected: enabled
                              ? (_) => setState(() => _kind = kind)
                              : null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // `Wrap` y no `Row`: con un texto grande o una pantalla angosta
                // el segundo botón baja a otra línea en vez de desbordar.
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        onPressed: enabled ? widget.onDismiss : null,
                        child: Text(l10n.blocksBrokenLinkDismiss),
                      ),
                      FilledButton(
                        onPressed: enabled
                            ? () => widget.onCreate(_kind)
                            : null,
                        child: Text(l10n.blocksBrokenLinkCreate),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
