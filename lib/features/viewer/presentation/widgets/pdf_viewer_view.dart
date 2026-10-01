import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:pdfrx/pdfrx.dart';

/// El PDF, paginado y con zoom, igual que cualquier lector nativo —Adobe
/// Reader, el visor del sistema—.
///
/// `pdfrx` es el mismo PDFium que ya usa `PdfParser` para extraer texto (ver
/// `pdfrx_engine` en `pubspec.yaml`), con el widget de lectura completo
/// encima. Renderiza página por página bajo demanda —no carga el documento
/// entero en memoria de una vez—, así que abrir un PDF de mil páginas cuesta
/// lo mismo que uno de diez: se puede embeber directo en el detalle de un
/// elemento sin distinguir "vista previa" de "el visor de verdad", los dos
/// son el mismo widget.
///
/// Mantener apretado sobre el texto lo selecciona, con tiradores para
/// ajustarlo y el menú "Copiar / Seleccionar todo" —todo de `pdfrx`, con sus
/// valores por defecto—. Ese menú solo se puede construir dentro de
/// [PdfrxMaterialBridge]: ver ahí por qué.
///
/// Sin `Scaffold` propio a propósito: `PdfViewerScreen` lo envuelve para
/// mostrarlo a pantalla completa, y `EmbeddedFileViewer` lo embebe tal cual
/// dentro de un marco acotado en el detalle del elemento.
class PdfViewerView extends StatelessWidget {
  const PdfViewerView({required this.path, super.key});

  final String path;

  @override
  Widget build(BuildContext context) {
    return PdfrxMaterialBridge(
      child: PdfViewer.file(
        path,
        params: PdfViewerParams(
          // Un fondo neutro entre página y página, para que se distinga
          // dónde termina una y empieza la otra al scrollear — lo mismo que
          // hace cualquier lector de PDF de verdad.
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          textSelectionParams: const PdfTextSelectionParams(
            buildSelectionHandle: buildPdfSelectionHandle,
          ),
        ),
      ),
    );
  }
}

/// El lado del área táctil de un tirador: más grande que lo que se ve, para
/// que se agarre con el dedo sin buscarlo.
const pdfSelectionHandleTouchSize = 40.0;

/// El diámetro de la gota que se ve.
const _handleDiameter = 22.0;

/// Los tiradores de la selección de texto del PDF: una gota —un círculo con
/// una punta que toca la letra—, como los de Material y Google Lens, en vez
/// del triángulo de `pdfrx` (F22, pedido del usuario).
///
/// `pdfrx` pone el tirador del principio arriba y a la izquierda de la
/// primera letra —la esquina de abajo a la derecha del tirador toca la
/// letra— y el del final abajo y a la derecha de la última —la esquina de
/// arriba a la izquierda—. La gota se dibuja en esa esquina, con la punta
/// ahí; el resto del área táctil es transparente.
Widget? buildPdfSelectionHandle(
  BuildContext context,
  PdfTextSelectionAnchor anchor,
  PdfViewerTextSelectionAnchorHandleState state,
) {
  final tip = pdfSelectionHandleTip(
    start: anchor.type == PdfTextSelectionAnchorType.a,
    // En un texto de derecha a izquierda, `pdfrx` los pone del lado
    // opuesto.
    rightToLeft:
        anchor.direction == PdfTextDirection.rtl ||
        anchor.direction == PdfTextDirection.vrtl,
  );
  final color = Theme.of(context).colorScheme.primary;
  return SizedBox.square(
    dimension: pdfSelectionHandleTouchSize,
    child: ColoredBox(
      color: Colors.transparent,
      child: Align(
        alignment: tip,
        child: _Teardrop(
          tip: tip,
          color: state == PdfViewerTextSelectionAnchorHandleState.dragging
              ? color
              : color.withValues(alpha: 0.9),
          elevated: state != PdfViewerTextSelectionAnchorHandleState.dragging,
        ),
      ),
    ),
  );
}

/// La esquina del tirador que toca la letra —donde va la punta de la
/// gota—, según dónde lo pone `pdfrx`: ver [buildPdfSelectionHandle].
Alignment pdfSelectionHandleTip({
  required bool start,
  required bool rightToLeft,
}) => switch ((start, rightToLeft)) {
  (true, false) => Alignment.bottomRight,
  (true, true) => Alignment.bottomLeft,
  (false, false) => Alignment.topLeft,
  (false, true) => Alignment.topRight,
};

class _Teardrop extends StatelessWidget {
  const _Teardrop({
    required this.tip,
    required this.color,
    required this.elevated,
  });

  /// La esquina con punta: la que toca la letra.
  final Alignment tip;
  final Color color;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    const round = Radius.circular(_handleDiameter / 2);
    return Container(
      width: _handleDiameter,
      height: _handleDiameter,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: tip == Alignment.topLeft ? Radius.zero : round,
          topRight: tip == Alignment.topRight ? Radius.zero : round,
          bottomLeft: tip == Alignment.bottomLeft ? Radius.zero : round,
          bottomRight: tip == Alignment.bottomRight ? Radius.zero : round,
        ),
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
    );
  }
}

/// Les da a los widgets de `pdfrx` las traducciones y el tema que esperan.
///
/// Desde la 2.5.0, `pdfrx` arma sus widgets —el menú de copiar, entre
/// otros— con `material_ui`, una **copia** de Material publicada aparte,
/// con sus propias clases: su `MaterialLocalizations` y su `Theme` son de
/// otro tipo que los de `package:flutter/material.dart`, que es lo que usa
/// esta app. Sin este puente, `MaterialLocalizations.of` de `material_ui` no
/// encuentra nada: en Android, mantener apretado sobre el texto seleccionaba
/// bien, pero el menú reventaba al pedir la etiqueta "Copiar" y la versión
/// release lo reemplazaba por el recuadro gris de error de Flutter, del
/// tamaño del visor entero (F22). Las traducciones heredan el idioma de la
/// app; el tema copia los colores y la tipografía del tema de la app, para
/// que el menú se vea igual que el resto —modo oscuro incluido— y no con el
/// tema de respaldo claro de `material_ui`.
///
/// Si algún día la app migra entera a `material_ui`, este puente sobra.
class PdfrxMaterialBridge extends StatelessWidget {
  const PdfrxMaterialBridge({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Localizations.override(
      context: context,
      delegates: const [mui.GlobalMaterialLocalizations.delegate],
      child: mui.Theme(
        data: mui.ThemeData(
          colorScheme: _colorScheme(theme.colorScheme),
          fontFamily: theme.textTheme.bodyMedium?.fontFamily,
        ),
        child: child,
      ),
    );
  }

  static mui.ColorScheme _colorScheme(ColorScheme c) => mui.ColorScheme(
    brightness: c.brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primaryContainer,
    onPrimaryContainer: c.onPrimaryContainer,
    secondary: c.secondary,
    onSecondary: c.onSecondary,
    secondaryContainer: c.secondaryContainer,
    onSecondaryContainer: c.onSecondaryContainer,
    tertiary: c.tertiary,
    onTertiary: c.onTertiary,
    error: c.error,
    onError: c.onError,
    surface: c.surface,
    onSurface: c.onSurface,
    surfaceContainerLowest: c.surfaceContainerLowest,
    surfaceContainerLow: c.surfaceContainerLow,
    surfaceContainer: c.surfaceContainer,
    surfaceContainerHigh: c.surfaceContainerHigh,
    surfaceContainerHighest: c.surfaceContainerHighest,
    onSurfaceVariant: c.onSurfaceVariant,
    outline: c.outline,
    outlineVariant: c.outlineVariant,
    shadow: c.shadow,
    scrim: c.scrim,
    inverseSurface: c.inverseSurface,
    onInverseSurface: c.onInverseSurface,
    inversePrimary: c.inversePrimary,
    surfaceTint: c.surfaceTint,
  );
}
