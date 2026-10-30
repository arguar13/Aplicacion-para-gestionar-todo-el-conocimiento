import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_actions.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_standing.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_text.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/inbox_status_presentation.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/pending_text_status.dart';
import 'package:sinapsis/features/processed/presentation/retriage.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En el detalle de una fuente, la tarjeta «Bandeja» (F45, mejora 18): qué se
/// decidió en la Bandeja y cuándo (F28), y lo que se puede hacer desde ahí.
/// Es el único lugar del detalle que ofrece triar (F45, paso 7c): antes la
/// línea de «dónde se estudia» ofrecía también el suyo, y en una fuente sin
/// documento procesado «Volver a triar» salía dos veces.
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
/// Los dos botones de triar hacen lo mismo, ahí mismo y sin ir a la Bandeja:
/// abren la hoja «¿Qué va a Procesado?» por el camino de «Volver a triar»
/// (`retriageAction`), que tría también lo que todavía espera, y con «Listo»
/// el aviso trae «Ver» y «Deshacer», que deja la fuente y su documento como
/// estaban. Siguen la regla de la Bandeja ([InboxActions]): sin texto
/// todavía, esperan apagados, con el motivo que da la Bandeja —que llega,
/// que sacarlo falló, que no tenía—, y se prenden solos cuando el texto
/// llega. Una referencia bibliográfica sin texto no tiene qué triar ni texto
/// que esperar (decisión E): no los ofrece.
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
  const InboxStandingLine({required this.item, super.key});

  /// La fuente: su id, su nombre para el aviso de «Volver a la Bandeja», y lo
  /// que [InboxActions] mira para saber si ya se puede triar —sus imágenes,
  /// que se trían aun sin texto (decisión L)—.
  final KnowledgeItem item;

  /// El ícono de la Bandeja: el de su destino en la barra.
  static const _inboxIcon = Icons.move_to_inbox_outlined;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(inboxStandingProvider(item.id)).valueOrNull;
    if (standing == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = standing.status.color(colors);

    final pending = standing.status == InboxStatus.pending;
    // Triar, con lo que la Bandeja permite según el texto. Mientras se
    // averigua, apagado: un botón prendido que enseguida se apaga invita a
    // tocar lo que no se puede.
    final text =
        ref.watch(inboxPendingTextProvider(item.id)).valueOrNull ??
        PendingText.arriving;
    final canTriage = InboxActions.of(item, text).triage;
    // Apagado se ofrece solo lo que puede prenderse: el texto de una fuente
    // llega, o se vuelve a extraer; una referencia no trae texto que procesar
    // (decisión E), y sin él no tiene qué triar.
    final offersTriage = canTriage || standing.canReturn;
    final onTriage = canTriage
        ? retriageAction(context, ref, sourceItemId: item.id)
        : null;
    // El motivo, dicho como lo dice la Bandeja según en qué está el texto:
    // que llega solo no es lo mismo que sacarlo falló.
    final waitingReason = canTriage ? null : text.neededReason(l10n);

    final buttons = <_LabeledButton>[
      // Tría ahí mismo, como «Volver a triar»: antes llevaba a la Bandeja, y
      // el detalle tenía otro botón que triaba sin irse.
      if (offersTriage && pending)
        _LabeledButton(
          l10n.inboxTriageNow,
          disabledReason: waitingReason,
          (label) => FilledButton.icon(
            key: const Key('detail-triage-now'),
            onPressed: onTriage,
            icon: const Icon(_inboxIcon),
            label: label,
          ),
        ),
      // Lo que ya se decidió se puede volver a triar desde acá (F41, paso 4):
      // la hoja de siempre, con lo que su documento procesado ya tiene. Con
      // el ícono de «Volver a triar» en todos lados.
      if (offersTriage && !pending)
        _LabeledButton(
          l10n.processedRetriage,
          disabledReason: waitingReason,
          (label) => FilledButton.icon(
            key: const Key('detail-retriage'),
            onPressed: onTriage,
            icon: const Icon(Icons.replay_outlined),
            label: label,
          ),
        ),
      // Vuelve todo lo que entraría al guardarse, tenga texto o no (F41): en
      // la Bandeja espera su texto como lo recién guardado, así que no lleva
      // la guarda de triar. Una referencia sin texto, no (decisión E).
      if (!pending && standing.canReturn)
        _LabeledButton(
          l10n.inboxBackToInbox,
          (label) => OutlinedButton.icon(
            key: const Key('detail-back-to-inbox'),
            onPressed: () => _backToInbox(context, ref),
            icon: const Icon(_inboxIcon),
            label: label,
          ),
        ),
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
                // Sin nada que hacer —una referencia sin texto—, solo el
                // estado.
                if (buttons.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ButtonPair(buttons: buttons),
                ],
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
        .returnToInbox(item.id);

    messenger.hideCurrentSnackBar();
    result.match(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failure.localizedMessage(l10n))),
      ),
      (_) => messenger.showSnackBar(
        SnackBar(content: Text(l10n.inboxBackToInboxSnack(item.title))),
      ),
    );
  }
}

/// Un botón con su nombre aparte, para medirlo antes de decidir dónde va.
class _LabeledButton {
  const _LabeledButton(this.label, this.build, {this.disabledReason});

  final String label;

  /// El botón, con el nombre ya armado como [Text].
  final Widget Function(Widget label) build;

  /// Por qué espera apagado, o `null` si se puede tocar: un botón apagado sin
  /// explicación no dice si falta algo o si no se puede.
  final String? disabledReason;
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
    Widget built(_LabeledButton button) {
      final widget = button.build(
        Text(button.label, textAlign: TextAlign.center),
      );
      final reason = button.disabledReason;
      if (reason == null) return widget;
      // El motivo, también para el lector de pantalla, y en el mismo nodo que
      // el botón: si no, el botón es un nodo propio y la ayuda queda en el de
      // la tarjeta, lejos de lo que explica.
      return MergeSemantics(
        child: Tooltip(message: reason, child: widget),
      );
    }

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
