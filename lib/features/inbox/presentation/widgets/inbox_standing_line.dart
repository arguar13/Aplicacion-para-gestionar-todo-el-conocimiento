import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_standing.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_status_presentation.dart';
import 'package:sinapsis/features/processed/presentation/retriage.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En el detalle de una fuente, la tarjeta «Bandeja» (F45, mejora 18): qué se
/// decidió en la Bandeja y cuándo (F28), y lo que se puede hacer desde ahí.
///
/// - Arriba, el estado con su ícono: «✓ Triado el 3 oct», «Descartado el…» o
///   «En la Bandeja».
/// - Debajo, sus botones, del mismo alto y uno al lado del otro: «Volver a
///   triar» (F41, paso 4), relleno porque es lo que más se usa, y «Volver a la
///   Bandeja», con borde y el ícono de la Bandeja —no la flecha de deshacer,
///   que se confunde con «volver»—. Si no entran a lo ancho —360 dp con la
///   letra al doble—, uno debajo del otro, a todo lo ancho.
/// - Lo que todavía espera en la Bandeja, un solo botón: «Triar ahora».
///
/// Antes eran un chip y dos enlaces sueltos debajo del título, en dos
/// renglones desparejos, y se perdían. Conserva el nombre de «línea» para que
/// el detalle, que la pone debajo del título, no cambie.
///
/// Es la otra mitad de la sección «Bandeja» de los filtros: lo triado se
/// encuentra filtrando, y al abrirlo se ve que se trió y se puede deshacer
/// desde ahí, sin volver a la Bandeja a buscarlo. No dibuja nada —ni el
/// espacio de arriba— en lo que no pasa por la Bandeja: una nota. Una fuente
/// que todavía se procesa ya está «En la Bandeja» (F41).
class InboxStandingLine extends ConsumerWidget {
  const InboxStandingLine({
    required this.itemId,
    required this.itemTitle,
    super.key,
  });

  final String itemId;

  /// Para el aviso de «Volver a la Bandeja».
  final String itemTitle;

  /// El ícono de la Bandeja: el de su destino en la barra.
  static const _inboxIcon = Icons.move_to_inbox_outlined;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(inboxStandingProvider(itemId)).valueOrNull;
    if (standing == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = standing.status.color(colors);

    final buttons = <_LabeledButton>[
      if (standing.status == InboxStatus.pending)
        _LabeledButton(
          l10n.inboxTriageNow,
          (label) => FilledButton.icon(
            key: const Key('detail-triage-now'),
            onPressed: () {
              ref.read(inboxFocusedIdProvider.notifier).state = itemId;
              context.go(RoutePaths.inbox);
            },
            icon: const Icon(_inboxIcon),
            label: label,
          ),
        )
      else ...[
        // Lo que ya se decidió se puede volver a triar desde acá (F41, paso
        // 4): la hoja de siempre, con lo que su documento procesado ya tiene.
        // Con el ícono de «Volver a triar» en todos lados.
        _LabeledButton(
          l10n.processedRetriage,
          (label) => FilledButton.icon(
            key: const Key('detail-retriage'),
            onPressed: retriageAction(context, ref, sourceItemId: itemId),
            icon: const Icon(Icons.replay_outlined),
            label: label,
          ),
        ),
        // Vuelve todo lo que entraría al guardarse, tenga texto o no (F41);
        // una referencia sin texto, no (decisión E).
        if (standing.canReturn)
          _LabeledButton(
            l10n.inboxBackToInbox,
            (label) => OutlinedButton.icon(
              key: const Key('detail-back-to-inbox'),
              onPressed: () => _backToInbox(context, ref),
              icon: const Icon(_inboxIcon),
              label: label,
            ),
          ),
      ],
    ];

    // La tarjeta «Bandeja» también para el lector de pantalla: su nombre, y
    // adentro el estado y cada botón por su lado.
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: l10n.navInbox,
        child: Material(
          key: const Key('inbox-standing-card'),
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // El color del estado, como la insignia de madurez de una
                // nota: se lee de un vistazo.
                Row(
                  key: const Key('inbox-standing-status'),
                  children: [
                    Icon(standing.status.icon, size: 20, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _label(
                          context,
                          l10n,
                          standing,
                          now: ref.read(clockProvider)(),
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ButtonPair(buttons: buttons),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// «Triado el 3 oct»: el día y el mes, y el año solo si no es este —«el 3
  /// oct» de hace dos años no es el de esta semana—.
  static String _label(
    BuildContext context,
    AppLocalizations l10n,
    InboxStanding standing, {
    required DateTime now,
  }) {
    final since = standing.since;
    final locale = Localizations.localeOf(context).toString();
    String date(DateTime at) =>
        (at.year == now.year
                ? DateFormat.MMMd(locale)
                : DateFormat.yMMMd(locale))
            .format(at.toLocal());

    return switch (standing.status) {
      InboxStatus.pending => l10n.inboxStandingPending,
      InboxStatus.triaged =>
        since == null
            ? l10n.inboxStandingTriaged
            : l10n.inboxStandingTriagedOn(date(since)),
      InboxStatus.discarded =>
        since == null
            ? l10n.inboxStandingDiscarded
            : l10n.inboxStandingDiscardedOn(date(since)),
    };
  }

  Future<void> _backToInbox(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(inboxRepositoryProvider)
        .returnToInbox(itemId);

    messenger.hideCurrentSnackBar();
    result.match(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failure.localizedMessage(l10n))),
      ),
      (_) => messenger.showSnackBar(
        SnackBar(content: Text(l10n.inboxBackToInboxSnack(itemTitle))),
      ),
    );
  }
}

/// Un botón con su nombre aparte, para medirlo antes de decidir dónde va.
class _LabeledButton {
  const _LabeledButton(this.label, this.build);

  final String label;

  /// El botón, con el nombre ya armado como [Text].
  final Widget Function(Widget label) build;
}

/// Uno o dos botones del mismo alto: uno al lado del otro, partiéndose el
/// ancho, si cada nombre entra en su mitad en hasta dos renglones sin cortar
/// una palabra; si no, uno debajo del otro, a todo lo ancho, en el orden en
/// que vienen. Uno solo va a todo lo ancho.
///
/// El nombre se mide con la letra de verdad —la del botón, con la escala de la
/// persona—, como las opciones unidas de «Lo creado». En un teléfono con la
/// letra normal, los nombres van en dos renglones, uno al lado del otro y los
/// dos del alto de la fila; a 360 dp con la letra al doble, «Bandeja» sola ya
/// no entra en medio ancho y se apilan.
class _ButtonPair extends StatelessWidget {
  const _ButtonPair({required this.buttons});

  final List<_LabeledButton> buttons;

  static const double _gap = 8;

  /// Lo que ocupa un botón con ícono de Material 3 además de su nombre: el
  /// relleno de los costados (16 y 24), el ícono (18) y su separación (8).
  /// Con la letra más grande Material achica el relleno y la separación, así
  /// que es lo más que puede ocupar.
  static const double _chrome = 16 + 18 + 8 + 24;

  /// Más renglones en un botón ya no es un botón: es un párrafo.
  static const int _maxLines = 2;

  @override
  Widget build(BuildContext context) {
    Widget built(_LabeledButton button) =>
        button.build(Text(button.label, textAlign: TextAlign.center));

    if (buttons.length == 1) return built(buttons.single);

    final style = Theme.of(context).textTheme.labelLarge!;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    /// El ancho de [text] en un renglón, con la letra del botón.
    double widthOf(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    /// Si [label] entra en [width] en hasta dos renglones, cortando solo
    /// entre palabras: una palabra que no entra entera se partiría por la
    /// mitad, y eso no se lee.
    bool fitsIn(String label, double width) {
      if (width <= 0) return false;
      if (label.split(' ').any((word) => widthOf(word) > width)) return false;
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: direction,
        textScaler: scaler,
        textAlign: TextAlign.center,
      )..layout(maxWidth: width);
      final lines = painter.computeLineMetrics().length;
      painter.dispose();
      return lines <= _maxLines;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final room = (constraints.maxWidth - _gap) / 2 - _chrome;
        final fits = buttons.every((button) => fitsIn(button.label, room));

        if (!fits) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, button) in buttons.indexed) ...[
                if (index > 0) const SizedBox(height: _gap),
                built(button),
              ],
            ],
          );
        }
        // Del mismo alto pase lo que pase: el de la fila.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, button) in buttons.indexed) ...[
                if (index > 0) const SizedBox(width: _gap),
                Expanded(child: built(button)),
              ],
            ],
          ),
        );
      },
    );
  }
}
