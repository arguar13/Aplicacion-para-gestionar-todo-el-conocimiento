import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Avisa que se vinculó [itemId] con otro, con «Ver en el Mapa»: la vista
/// «Vínculos» con el foco en él (F28). Vincular deja de ser un «no pasa
/// nada»: se ve adónde fue.
void showLinkedNotice(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
}) {
  final l10n = AppLocalizations.of(context)!;
  // El router y el pedido, antes de mostrar: cuando se toque el botón, la
  // pantalla que vinculó puede ya no estar. Sin router —una pantalla montada
  // sola— no hay adónde ir, y el botón no se ofrece.
  final router = GoRouter.maybeOf(context);
  final focus = ref.read(mapLinksFocusRequestProvider.notifier);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.relationLinked),
        action: router == null
            ? null
            : SnackBarAction(
                label: l10n.relationSeeInMap,
                onPressed: () {
                  focus.state = itemId;
                  router.go(RoutePaths.graph);
                },
              ),
      ),
    );
}
