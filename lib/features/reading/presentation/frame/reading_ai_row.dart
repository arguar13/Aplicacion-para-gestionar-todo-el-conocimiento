import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/podcast/presentation/podcast_entry.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La fila de IA del marco de lectura (F47, paso 1, captura 4): las fichas en
/// un renglón, del mismo alto, que **en angosto se desplaza de costado** en
/// vez de cortarse o pasar a varios renglones. Cada ficha trae su ancho —el
/// que necesita para no cortar una palabra con la letra de ahora—.
class ReadingAiStrip extends StatelessWidget {
  const ReadingAiStrip({required this.children, super.key});

  final List<Widget> children;

  /// El aire entre una ficha y la otra.
  static const gap = 8.0;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('reading-ai-strip'),
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const SizedBox(width: gap),
            child,
          ],
        ],
      ),
    ),
  );
}

/// El ancho de una ficha que lleva [lines] —el nombre, el estado— con la
/// letra de ahora, sin cortar ninguna palabra: la palabra más larga de cada
/// renglón, más [extra] —el ícono, el ⋯—, nunca menos que [min].
double readingChipWidth(
  BuildContext context,
  List<(String, TextStyle?)> lines, {
  double extra = 0,
  double min = 120,
}) {
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (final (text, style) in lines) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  // Un píxel de más: lo que mide el texto y lo que ocupa redondean distinto.
  return math.max(min, widest + extra + 1);
}

/// Una ficha de la fila de IA que no es de estudiar: su ícono, su nombre y,
/// debajo, para qué es o en qué está. Del mismo alto que las de Resumir,
/// Sintetizar y Palabras clave. Sin [onPressed], apagada.
class ReadingAiChip extends StatelessWidget {
  const ReadingAiChip({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onPressed,
    this.semanticsHint,
    super.key,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback? onPressed;

  /// Lo que dice el lector de pantalla además del nombre y el detalle.
  final String? semanticsHint;

  static const _padding = EdgeInsets.fromLTRB(12, 8, 14, 8);
  static const _icon = 20.0;
  static const _iconGap = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null;
    final nameStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
    );
    final detailStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final width = readingChipWidth(context, [
      (label, nameStyle),
      (detail, detailStyle),
    ], extra: _padding.horizontal + _icon + _iconGap);

    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label. $detail',
      hint: semanticsHint,
      excludeSemantics: true,
      onTap: onPressed,
      child: SizedBox(
        width: width,
        child: Material(
          color: enabled ? scheme.surfaceContainerLow : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: enabled
                  ? scheme.outlineVariant
                  : scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: _padding,
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: _icon,
                      color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: _iconGap),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, maxLines: 1, style: nameStyle),
                          const SizedBox(height: 2),
                          Text(detail, maxLines: 1, style: detailStyle),
                        ],
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

/// «Preguntar a la IA»: el chat sobre este documento.
class ReadingAskAiChip extends StatelessWidget {
  const ReadingAskAiChip({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ReadingAiChip(
      key: const Key('reading-ai-ask'),
      icon: Icons.forum_outlined,
      label: l10n.f47P1AskAi,
      detail: l10n.f47P1AskAiHint,
      onPressed: onPressed,
    );
  }
}

/// «Podcast»: abre la hoja del podcast (F47, paso 6a) sobre [scope] —el
/// documento procesado que se lee, o el recorte de lo creado—, la misma que
/// la tarjeta «Podcast» de Repasar.
///
/// Sin [scope] —una nota, una fuente de la Biblioteca, el pasaje de una
/// tarjeta— queda apagada y dice por qué: el podcast se arma con lo
/// procesado.
class ReadingPodcastChip extends StatelessWidget {
  const ReadingPodcastChip({required this.scope, super.key});

  final CreationScope? scope;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scope = this.scope;
    return ReadingAiChip(
      key: const Key('reading-ai-podcast'),
      icon: Icons.podcasts_outlined,
      label: l10n.f47P1Podcast,
      detail: scope == null
          ? l10n.f47P1PodcastOnlyProcessed
          : l10n.f47P1PodcastMade,
      semanticsHint: scope == null
          ? l10n.f47P1PodcastOnlyProcessedHint
          : l10n.f47P1PodcastHint,
      onPressed: scope == null
          ? null
          : () => unawaited(startPodcast(context, scope)),
    );
  }
}
