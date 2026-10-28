import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Volver a triar» (F41, paso 4 del plan): qué hacer al tocarlo, o `null`
/// mientras no está.
///
/// Es el único punto por el que pasa todo botón «Volver a triar» —el del
/// documento procesado, el del vacío de «Procesado» y, cuando llegue, el de la
/// Bandeja y el del detalle de la fuente—. Con [sourceItemId], vuelve a triar
/// esa fuente: abre la hoja «¿Qué va a Procesado?» con lo que su documento ya
/// tiene. Sin él, abre el selector con toda la Biblioteca.
///
/// Hoy devuelve `null`, y cada botón se ve **apagado, con «Próximamente»**:
///
/// - un botón que hace como que anda —un aviso de «todavía no»— enseña a
///   desconfiar de los que sí andan;
/// - esconderlo correría la pantalla cuando llegue, y el plan lo promete
///   acá;
/// - apagado y con su motivo, el lector de pantalla lo anuncia igual.
///
/// El paso 4 lo implementa acá, y todos los botones se prenden solos.
VoidCallback? retriageAction(
  BuildContext context,
  WidgetRef ref, {
  String? sourceItemId,
}) => null;

/// El botón «Volver a triar», con su motivo mientras está apagado.
class RetriageButton extends ConsumerWidget {
  const RetriageButton({this.sourceItemId, this.filled = false, super.key});

  /// La fuente a volver a triar; `null` para elegirla en toda la Biblioteca.
  final String? sourceItemId;

  /// Relleno —la acción principal de un vacío— o de contorno.
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final action = retriageAction(context, ref, sourceItemId: sourceItemId);
    final label = Text(l10n.processedRetriage);
    const icon = Icon(Icons.replay_outlined);
    final button = filled
        ? FilledButton.tonalIcon(onPressed: action, icon: icon, label: label)
        : OutlinedButton.icon(onPressed: action, icon: icon, label: label);
    if (action != null) return button;
    // El motivo, también para el lector de pantalla —el `Tooltip` lo anuncia—:
    // un botón apagado sin explicación no dice si falta algo o si no se puede.
    return Tooltip(message: l10n.processedRetriageSoon, child: button);
  }
}
