import 'package:flutter/material.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La barrita que aparece sobre un texto seleccionado para resaltarlo a mano
/// (F38): una grilla de colores para resaltar de fondo —nueve, en dos filas—,
/// «Subrayar» con una línea del color elegido al final de la grilla, y debajo
/// Copiar, Escuchar, Nota, Extraer como nota y Hacer tarjeta. Lo que no
/// entra —Compartir, Seleccionar todo, Buscar en la Web— queda detrás de «Más
/// opciones».
///
/// **API, para quien la pone sobre cualquier documento**
///
/// No sabe de dónde viene la selección —un `SelectableText`, el PDF real, una
/// página web—: solo dónde está en la pantalla y qué hacer con cada botón.
///
///  * [anchors]: dónde está la selección, en coordenadas de la pantalla. La
///    barrita se para encima del [TextSelectionToolbarAnchors.primaryAnchor]
///    (el borde de arriba de la selección) o, si arriba no entra, debajo del
///    [TextSelectionToolbarAnchors.secondaryAnchor] (el borde de abajo). Con
///    un `SelectableText` son los `contextMenuAnchors` de su
///    `EditableTextState`; con una selección sobre un PDF, los bordes del
///    rectángulo que ocupa.
///  * [underlineColor]: el color de la línea de «Subrayar» —el último que se
///    eligió, o el primero—. Lo guarda quien la usa; ver
///    `lastHighlightColorProvider`.
///  * [onHighlight] y [onUnderline] reciben el color tocado; el segundo
///    siempre [underlineColor].
///  * Los otros botones son opcionales: **sin su callback no se dibuja**, así
///    que un documento al que no se le puede extraer una nota simplemente no
///    ofrece ese botón.
///  * [moreActions]: lo que va detrás de «Más opciones», ya con su texto.
///
/// Se dibuja dentro de un `Overlay` —lo que arma `contextMenuBuilder`, o un
/// `OverlayEntry` propio—, ocupando el lugar que le toque: no cierra nada por
/// su cuenta, quien la muestra la saca cuando se toca un botón.
///
/// Cada botón mide lo que un dedo necesita y dice qué hace con su
/// descripción: un lector de pantalla la anuncia como una sola barra con sus
/// botones.
class HighlightToolbar extends StatelessWidget {
  const HighlightToolbar({
    required this.anchors,
    required this.underlineColor,
    required this.onHighlight,
    required this.onUnderline,
    this.onCopy,
    this.onReadAloud,
    this.onNote,
    this.onExtract,
    this.onCreateFlashcard,
    this.moreActions = const [],
    super.key,
  });

  final TextSelectionToolbarAnchors anchors;
  final HighlightColor underlineColor;
  final ValueChanged<HighlightColor> onHighlight;
  final ValueChanged<HighlightColor> onUnderline;
  final VoidCallback? onCopy;
  final VoidCallback? onReadAloud;
  final VoidCallback? onNote;
  final VoidCallback? onExtract;
  final VoidCallback? onCreateFlashcard;
  final List<HighlightToolbarAction> moreActions;

  /// Cuántas muestras de color hay por fila (F39: nueve colores en una grilla
  /// de cinco columnas, que entra en un teléfono angosto sin deslizar nada).
  static const _columns = 5;

  /// Lo que mide la barrita de alto: tres filas de botones —dos de colores y
  /// una de acciones— con su borde. Sirve para decidir si entra encima de la
  /// selección.
  static const _height = 160.0;

  /// El aire con el borde de la pantalla, y con la selección.
  static const _screenPadding = 8.0;
  static const _distanceAbove = 8.0;
  static const _distanceBelow =
      TextSelectionToolbar.kToolbarContentDistanceBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // Lo mismo que hace la barra de Flutter para pararse junto a la
    // selección: encima si entra, debajo si no.
    final anchorAbove = anchors.primaryAnchor - const Offset(0, _distanceAbove);
    final anchorBelow =
        (anchors.secondaryAnchor ?? anchors.primaryAnchor) +
        const Offset(0, _distanceBelow);
    final paddingAbove = MediaQuery.paddingOf(context).top + _screenPadding;
    final fitsAbove = _height <= anchorAbove.dy - _distanceAbove - paddingAbove;
    final localAdjustment = Offset(_screenPadding, paddingAbove);

    final colorButtons = [
      for (final color in HighlightColor.values)
        HighlightColorDot(
          key: Key('highlight-color-${color.name}'),
          color: color,
          tooltip: l10n.highlightWithColor(highlightColorName(l10n, color)),
          onPressed: () => onHighlight(color),
        ),
    ];
    final actions = <Widget>[
      if (onCopy != null)
        _ActionButton(
          icon: Icons.copy_outlined,
          tooltip: l10n.highlightCopy,
          onPressed: onCopy!,
        ),
      if (onReadAloud != null)
        _ActionButton(
          icon: Icons.volume_up_outlined,
          tooltip: l10n.highlightListen,
          onPressed: onReadAloud!,
        ),
      if (onNote != null)
        _ActionButton(
          icon: Icons.sticky_note_2_outlined,
          tooltip: l10n.highlightAddNote,
          onPressed: onNote!,
        ),
      if (onExtract != null)
        _ActionButton(
          icon: Icons.content_cut,
          tooltip: l10n.detailExtractSelection,
          onPressed: onExtract!,
        ),
      if (onCreateFlashcard != null)
        _ActionButton(
          icon: Icons.style_outlined,
          tooltip: l10n.flashcardsFromSelection,
          onPressed: onCreateFlashcard!,
        ),
      if (moreActions.isNotEmpty)
        PopupMenuButton<HighlightToolbarAction>(
          icon: const Icon(Icons.more_horiz),
          tooltip: l10n.highlightMore,
          onSelected: (action) => action.onPressed(),
          itemBuilder: (context) => [
            for (final action in moreActions)
              PopupMenuItem(value: action, child: Text(action.label)),
          ],
        ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _screenPadding,
        paddingAbove,
        _screenPadding,
        _screenPadding,
      ),
      child: CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(
          anchorAbove: anchorAbove - localAdjustment,
          anchorBelow: anchorBelow - localAdjustment,
          fitsAbove: fitsAbove,
        ),
        child: Semantics(
          container: true,
          label: l10n.highlightToolbarLabel,
          child: Material(
            key: const Key('highlight-toolbar-card'),
            elevation: 6,
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Las muestras en una grilla de [_columns] columnas: la
                    // primera fila, llena; la segunda, lo que sobra y
                    // «Subrayar» en la última columna.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: colorButtons.take(_columns).toList(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ...colorButtons.skip(_columns),
                        IconButton(
                          key: const Key('highlight-underline'),
                          tooltip: l10n.highlightUnderlineWithColor(
                            highlightColorName(l10n, underlineColor),
                          ),
                          onPressed: () => onUnderline(underlineColor),
                          icon: Icon(
                            Icons.format_underlined,
                            color: HighlightPalette.line(
                              context,
                              underlineColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (actions.isNotEmpty) ...[
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: actions,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Una opción de «Más opciones» de [HighlightToolbar].
@immutable
class HighlightToolbarAction {
  const HighlightToolbarAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// El nombre de [color], en el idioma de la app.
String highlightColorName(AppLocalizations l10n, HighlightColor color) =>
    switch (color) {
      HighlightColor.lightYellow => l10n.highlightColorLightYellow,
      HighlightColor.orange => l10n.highlightColorOrange,
      HighlightColor.coral => l10n.highlightColorCoral,
      HighlightColor.sand => l10n.highlightColorSand,
      HighlightColor.lime => l10n.highlightColorLime,
      HighlightColor.turquoise => l10n.highlightColorTurquoise,
      HighlightColor.blue => l10n.highlightColorBlue,
      HighlightColor.violet => l10n.highlightColorViolet,
      HighlightColor.gray => l10n.highlightColorGray,
    };

/// Un botón redondo con el tono de [color], para elegirlo: el de la barrita y
/// los de la ficha de un resaltado. Con [selected], lleva una tilde y el
/// borde del color principal del tema.
class HighlightColorDot extends StatelessWidget {
  const HighlightColorDot({
    required this.color,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final HighlightColor color;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      icon: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: HighlightPalette.resolve(context, color),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
        ),
        // La letra va oscura sobre un tono de resaltador, también en modo
        // oscuro.
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.black87)
            : null,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      IconButton(icon: Icon(icon), tooltip: tooltip, onPressed: onPressed);
}
