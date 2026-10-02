import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/media_player_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

// Las piezas con que se arma el panel de la fuente (F26): una franja de
// estado, el reproductor del audio y un mosaico de acción. Aparte del panel
// porque también las usa la descarga del audio de YouTube
// —`YouTubeAudioDownloadSection`—, que vive en otra parte de la app y tiene
// que verse igual que el resto del panel.

/// El aire de los costados de cada sección del panel.
const sourcePanelInset = 16.0;

/// Si una franja de estado cuenta algo que está pasando o algo que falló.
enum SourcePanelTone { neutral, error }

/// Lo que está pasando con el elemento, dicho siempre de la misma forma
/// (F26): un ícono en un círculo suave, el texto, la barra si hay avance y,
/// si hay algo que hacer, **un** botón del mismo estilo en todos los casos
/// —ver [SourcePanelStatusButton]—.
///
/// El botón va debajo del texto y no a su lado: los motivos de un fallo son
/// largos —"No se pudo traer el contenido. El enlace y todo lo que se sabe
/// sigue guardado."—, y a su lado, en un teléfono de 360 px, quedaban en una
/// columna de cuatro palabras.
class SourcePanelStatus extends StatelessWidget {
  const SourcePanelStatus({
    required this.icon,
    required this.message,
    this.messageKey,
    this.tone = SourcePanelTone.neutral,
    this.progress,
    this.action,
    super.key,
  });

  final IconData icon;
  final String message;

  /// Para encontrar el texto en las pruebas.
  final Key? messageKey;
  final SourcePanelTone tone;

  /// La barra de avance, si se sabe cuánto va.
  final Widget? progress;

  /// Qué hacer: reintentar, bajar lo que falta.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error = tone == SourcePanelTone.error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        sourcePanelInset,
        14,
        sourcePanelInset,
        14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToneCircle(
            icon: icon,
            size: 32,
            iconSize: 18,
            background: error ? scheme.errorContainer : scheme.surfaceContainer,
            foreground: error ? scheme.onErrorContainer : scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Centrado con el círculo cuando entra en un renglón.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      message,
                      key: messageKey,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: error
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (progress case final progress?) ...[
                  const SizedBox(height: 10),
                  progress,
                ],
                if (action case final action?) ...[
                  const SizedBox(height: 10),
                  action,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// El único botón de una franja de estado —"Reintentar", "Descargar el
/// modelo"—: tonal y chico, el mismo en todas, para que lo que se puede
/// hacer se reconozca de un vistazo sin importar qué falló (F26).
class SourcePanelStatusButton extends StatelessWidget {
  const SourcePanelStatusButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// La barra de avance de una franja, del mismo grosor y radio en todas.
class SourcePanelProgressBar extends StatelessWidget {
  const SourcePanelProgressBar({required this.value, super.key});

  /// De 0 a 1, o `null` mientras no se sabe cuánto falta.
  final double? value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(value: value, minHeight: 6),
    );
  }
}

/// El audio de un video dentro del panel (F26, decisión B): un encabezado
/// —"Audio del video"— y los controles compactos del mismo reproductor que
/// el del video de arriba, el mini reproductor y el texto que sigue al
/// audio —ver `playbackSessionProvider`—.
class SourcePanelAudio extends StatelessWidget {
  const SourcePanelAudio({
    required this.path,
    this.subtitle,
    this.playerKey,
    super.key,
  });

  /// La ruta absoluta del archivo, o `null` mientras se resuelve: se
  /// reserva el lugar de los controles para que el panel no salte.
  final String? path;

  /// Una aclaración debajo del título: que se escucha sin conexión.
  final String? subtitle;

  /// La llave del reproductor, para encontrarlo.
  final Key? playerKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final path = this.path;

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: sourcePanelInset),
            child: Row(
              children: [
                _ToneCircle(
                  icon: Icons.graphic_eq,
                  size: 32,
                  iconSize: 18,
                  background: scheme.primaryContainer,
                  foreground: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.sourcePanelAudioTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (subtitle case final subtitle?)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (path == null)
            const SizedBox(height: 100)
          else
            MediaPlayerView(
              key: playerKey,
              path: path,
              isVideo: false,
              audioOnly: true,
              compact: true,
            ),
        ],
      ),
    );
  }
}

/// Un mosaico de acción del panel (F26, decisión A): el ícono en un círculo
/// de color suave y su nombre debajo, todos del mismo ancho.
///
/// Al tocarlo responde con la onda de Material, una vibración corta y el
/// círculo que se hunde apenas; mientras trabaja —[busy], "Resumir"— el
/// ícono deja lugar a un indicador que gira. Sin [onTap] queda apagado pero
/// a la vista, con [tooltip] diciendo por qué: un mosaico que aparece y
/// desaparece mueve a los demás de lugar.
class SourcePanelTile extends StatefulWidget {
  const SourcePanelTile({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
    super.key,
  });

  final IconData icon;
  final String label;

  /// Qué hace, dicho entero —"Leer para destilar"—, o por qué está apagado.
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  State<SourcePanelTile> createState() => _SourcePanelTileState();
}

class _SourcePanelTileState extends State<SourcePanelTile> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.onTap != null && !widget.busy;
    // Apagado como Material apaga lo que no se puede tocar: el mismo color,
    // con menos opacidad.
    final foreground = enabled || widget.busy
        ? scheme.onSecondaryContainer
        : scheme.onSurface.withValues(alpha: 0.38);
    final background = enabled || widget.busy
        ? scheme.secondaryContainer
        : scheme.onSurface.withValues(alpha: 0.08);

    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        child: Tooltip(
          message: widget.tooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    widget.onTap!();
                  }
                : null,
            onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      scale: _pressed ? 0.9 : 1,
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOut,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: background,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: widget.busy
                              ? SizedBox.square(
                                  key: const ValueKey('busy'),
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: foreground,
                                  ),
                                )
                              : Icon(
                                  widget.icon,
                                  key: const ValueKey('icon'),
                                  size: 22,
                                  color: foreground,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: enabled || widget.busy
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.38),
                      ),
                    ),
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

/// Un ícono en un círculo de color: el idioma de todo el panel —los
/// mosaicos, las franjas de estado, el audio, las opciones de "Más"—.
class _ToneCircle extends StatelessWidget {
  const _ToneCircle({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: foreground),
    );
  }
}

/// [_ToneCircle] para las opciones de la hoja "Más".
class SourcePanelIconCircle extends StatelessWidget {
  const SourcePanelIconCircle({
    required this.icon,
    this.tone = SourcePanelTone.neutral,
    super.key,
  });

  final IconData icon;
  final SourcePanelTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = tone == SourcePanelTone.error;
    return _ToneCircle(
      icon: icon,
      size: 40,
      iconSize: 20,
      background: error ? scheme.errorContainer : scheme.secondaryContainer,
      foreground: error ? scheme.onErrorContainer : scheme.onSecondaryContainer,
    );
  }
}
