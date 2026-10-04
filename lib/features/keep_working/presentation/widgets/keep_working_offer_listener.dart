import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/keep_working/presentation/providers/keep_working_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Ofrece **una sola vez** la ayuda "Que siga con la app cerrada" (F29): la
/// primera vez que empieza un trabajo largo —procesar lo que se guardó,
/// transcribir, la IA— con la app a la vista, que es cuando importa y se
/// entiende por qué. Después queda en Ajustes.
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
  StreamSubscription<void>? _starts;
  var _offering = false;

  @override
  void initState() {
    super.initState();
    // Fuera de Android no hay nada que ofrecer, ni a quién escuchar.
    if (ref.read(backgroundSettingsProvider) == null) return;
    if (ref.read(keepWorkingHelpOfferProvider).alreadyOffered) return;
    _starts = ref
        .read(longWorkCoordinatorProvider)
        .workStarted
        .listen((_) => unawaited(_offer()));
  }

  @override
  void dispose() {
    unawaited(_starts?.cancel());
    super.dispose();
  }

  Future<void> _offer() async {
    final offer = ref.read(keepWorkingHelpOfferProvider);
    if (_offering || offer.alreadyOffered) return;
    // Con la app a la vista: un trabajo que arranca en segundo plano —la IA
    // con el cargador— no es momento de preguntar nada.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final navigator = widget.navigatorKey.currentContext;
    if (navigator == null) return;

    _offering = true;
    await offer.markOffered();
    // Ya no hay nada más que ofrecer: deja de escuchar desde ya.
    unawaited(_starts?.cancel());
    _starts = null;
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
