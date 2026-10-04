import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/keep_working/domain/services/background_settings.dart';
import 'package:sinapsis/features/keep_working/presentation/providers/keep_working_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// "Que siga con la app cerrada" (F29): lleva a los dos ajustes que, en
/// Xiaomi y otras marcas, deciden si el sistema deja seguir el trabajo
/// después de cerrar la app.
///
/// Se ofrece una sola vez, la primera vez que hay trabajo largo
/// (`KeepWorkingOfferListener`), y queda en Ajustes. La app no puede
/// cambiar esos ajustes: abre la pantalla justa —la de Xiaomi si la hay, la
/// de Android si no— y dice qué tocar ahí. Al volver se mira de nuevo lo que
/// se puede saber (la batería; "Inicio automático" no se puede leer).
class KeepWorkingScreen extends ConsumerStatefulWidget {
  const KeepWorkingScreen({super.key});

  @override
  ConsumerState<KeepWorkingScreen> createState() => _KeepWorkingScreenState();
}

class _KeepWorkingScreenState extends ConsumerState<KeepWorkingScreen> {
  BackgroundSettingsStatus? _status;

  /// Lo que hay que tocar en la pantalla que se abrió, si no fue la justa.
  String? _autostartHint;
  String? _batteryHint;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // De vuelta de los ajustes del sistema: lo que se cambió allá.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_refresh()));
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final settings = ref.read(backgroundSettingsProvider);
    if (settings == null) return;
    final status = await settings.status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _openAutostart() async {
    final l10n = AppLocalizations.of(context)!;
    final opened = await ref.read(backgroundSettingsProvider)?.openAutostart();
    if (!mounted) return;
    setState(
      () => _autostartHint = switch (opened) {
        BackgroundSettingsScreen.autostart => null,
        null => l10n.keepWorkingCouldNotOpen,
        _ => l10n.keepWorkingAutostartFallback,
      },
    );
  }

  Future<void> _openBattery() async {
    final l10n = AppLocalizations.of(context)!;
    final opened = await ref.read(backgroundSettingsProvider)?.openBattery();
    if (!mounted) return;
    setState(
      () => _batteryHint = switch (opened) {
        BackgroundSettingsScreen.battery => null,
        BackgroundSettingsScreen.appDetails => l10n.keepWorkingBatteryFallback,
        BackgroundSettingsScreen.batteryList =>
          l10n.keepWorkingBatteryListFallback,
        BackgroundSettingsScreen.autostart ||
        null => l10n.keepWorkingCouldNotOpen,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final status = _status;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.keepWorkingTitle)),
      body: SafeArea(
        // Arriba, como el resto de las pantallas de Ajustes: es una lista de
        // pasos, no un aviso suelto.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: status == null
                ? const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                // Pocas cosas, todas a la vista: una columna que se
                // desplaza si no entra, sin construir a demanda.
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.nights_stay_outlined,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.keepWorkingIntro,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                        if (status.isXiaomi) ...[
                          const SizedBox(height: 8),
                          Text(
                            l10n.keepWorkingXiaomiNote,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (status.isXiaomi) ...[
                          _StepCard(
                            key: const Key('keep-working-autostart'),
                            step: 1,
                            icon: Icons.restart_alt,
                            title: l10n.keepWorkingAutostartTitle,
                            body: l10n.keepWorkingAutostartBody,
                            hint: _autostartHint,
                            actionLabel: l10n.keepWorkingAutostartAction,
                            onAction: _openAutostart,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _StepCard(
                          key: const Key('keep-working-battery'),
                          step: status.isXiaomi ? 2 : 1,
                          icon: Icons.battery_charging_full,
                          title: l10n.keepWorkingBatteryTitle,
                          body: l10n.keepWorkingBatteryBody,
                          done: status.batteryUnrestricted
                              ? l10n.keepWorkingBatteryDone
                              : null,
                          // Hecho, ya no hay nada que buscar en los ajustes.
                          hint: status.batteryUnrestricted
                              ? null
                              : _batteryHint,
                          actionLabel: l10n.keepWorkingBatteryAction,
                          onAction: _openBattery,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.keepWorkingReassurance,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Un paso de la ayuda: qué es, para qué, y el botón que lleva ahí. Con el
/// lenguaje de las tarjetas de Ajustes (`Card`, radio 16).
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.done,
    this.hint,
    super.key,
  });

  final int step;
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  /// Si ya está hecho, lo que se ve en su lugar.
  final String? done;

  /// Qué tocar en la pantalla que se abrió, si no fue la justa.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDone = done != null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: isDone
                  ? colors.primary
                  : colors.secondaryContainer,
              foregroundColor: isDone
                  ? colors.onPrimary
                  : colors.onSecondaryContainer,
              child: isDone
                  ? const Icon(Icons.check, size: 18)
                  : Text('$step', style: theme.textTheme.labelLarge),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 20, color: colors.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(title, style: theme.textTheme.titleMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: theme.textTheme.bodyMedium),
                  if (isDone) ...[
                    const SizedBox(height: 8),
                    Text(
                      done!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ],
                  if (hint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      hint!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: onAction,
                    child: Text(actionLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
