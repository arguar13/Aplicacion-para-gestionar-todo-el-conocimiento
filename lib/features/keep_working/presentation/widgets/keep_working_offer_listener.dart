import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/keep_working/presentation/providers/keep_working_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Ofrece **una sola vez** la ayuda "Que siga con la app cerrada" (F29): la
/// primera vez que la app vuelve al frente con un trabajo largo en curso
/// —procesar lo que se guardó, transcribir, la IA—. Después queda en
/// Ajustes.
///
/// Al volver al frente y no cuando el trabajo empieza: el primer trabajo
/// largo es también cuando Android pide permiso para las notificaciones
/// (`SinapsisEngine`), y las dos preguntas salían encimadas. Ese diálogo
/// del sistema saca a la app del frente; al cerrarlo vuelve, y recién ahí
/// aparece esta oferta, una después de la otra. Y es el momento en que se
/// entiende: la persona vuelve y Sinapsis sigue trabajando.
///
/// Va por encima de toda pantalla, como el lector flotante: abre la hoja con
/// el navegador principal ([navigatorKey]).
class KeepWorkingOfferListener extends ConsumerStatefulWidget {
  const KeepWorkingOfferListener({
    required this.navigatorKey,
    required this.onOpenHelp,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;

  /// Abrir la ayuda: la ruta la conoce la app.
  final VoidCallback onOpenHelp;

  final Widget child;

  @override
  ConsumerState<KeepWorkingOfferListener> createState() =>
      _KeepWorkingOfferListenerState();
}

class _KeepWorkingOfferListenerState
    extends ConsumerState<KeepWorkingOfferListener> {
  AppLifecycleListener? _lifecycle;
  var _offering = false;

  @override
  void initState() {
    super.initState();
    // Fuera de Android no hay nada que ofrecer; ya ofrecida, tampoco.
    if (ref.read(backgroundSettingsProvider) == null) return;
    if (ref.read(keepWorkingHelpOfferProvider).alreadyOffered) return;
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_offer()));
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _offer() async {
    final offer = ref.read(keepWorkingHelpOfferProvider);
    if (_offering || offer.alreadyOffered) return;
    if (!ref.read(longWorkCoordinatorProvider).isWorking) return;
    final navigator = widget.navigatorKey.currentContext;
    if (navigator == null) return;

    _offering = true;
    // Ya no hay nada más que ofrecer: deja de escuchar desde ya.
    _lifecycle?.dispose();
    _lifecycle = null;
    await offer.markOffered();
    if (!navigator.mounted) return;
    final wantsHelp = await showModalBottomSheet<bool>(
      context: navigator,
      showDragHandle: true,
      builder: (_) => const _KeepWorkingOfferSheet(),
    );
    if (wantsHelp ?? false) widget.onOpenHelp();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _KeepWorkingOfferSheet extends StatelessWidget {
  const _KeepWorkingOfferSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.nights_stay_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.keepWorkingOfferTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.keepWorkingOfferBody, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.keepWorkingOfferLater),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.keepWorkingOfferAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
