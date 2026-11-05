import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/help/presentation/providers/help_providers.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/presentation/providers/home_widgets_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Si el teléfono deja poner un widget desde la app. Se pregunta al abrir la
/// pantalla de los widgets, no en Ajustes: es una pregunta al sistema.
final homeWidgetsCanAddProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(homeScreenWidgetsProvider).canAddFromApp(),
);

/// Los widgets de la pantalla de inicio (F47, paso 7): qué muestra y qué
/// hace cada uno, y «Agregar» para ponerlo sin salir de la app —el sistema
/// pregunta dónde—. Si el teléfono no deja, dice cómo hacerlo a mano. Al
/// final, si «Seguir escuchando» deja ver el título con la bóveda cerrada
/// (paso 7a-bis).
class HomeWidgetsScreen extends ConsumerWidget {
  const HomeWidgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final canAdd = ref.watch(homeWidgetsCanAddProvider).valueOrNull ?? false;
    final appName = ref.watch(appVersionProvider).valueOrNull?.name;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.f47P7WidgetsTile)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(l10n.f47P7WidgetsIntro, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final kind in HomeWidgetKind.values) ...[
                  if (kind.index > 0) const Divider(height: 1),
                  _WidgetRow(kind: kind, canAdd: canAdd),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!canAdd && appName != null && appName.isNotEmpty) ...[
            Text(
              l10n.f47P7WidgetsManualHint(appName),
              key: const Key('home-widgets-manual-hint'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: _ShowWhileLockedSwitch(),
          ),
        ],
      ),
    );
  }
}

/// «Mostrar el título con la bóveda cerrada» (F47, paso 7a-bis): si «Seguir
/// escuchando» deja ver lo último que se escuchó aunque la bóveda esté
/// cerrada. De entrada, apagado; cambiarlo cambia el widget al instante.
///
/// Va acá, junto a los widgets, y no suelto en Ajustes: es cómo se ve uno de
/// ellos, y quien no los usa no tiene nada que decidir.
///
/// La explicación va debajo, a todo el ancho, y no como subtítulo del
/// interruptor: es larga, y con la letra al doble en un teléfono angosto, al
/// lado del interruptor quedaba en una columna de pocas letras más alta que
/// la pantalla.
class _ShowWhileLockedSwitch extends ConsumerWidget {
  const _ShowWhileLockedSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final show = ref.watch(continueListeningShowWhileLockedProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('home-widgets-show-while-locked'),
          title: Text(l10n.f47P7WidgetsShowLockedTitle),
          value: show,
          onChanged: (value) => unawaited(
            ref
                .read(continueListeningShowWhileLockedProvider.notifier)
                .set(show: value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            show
                ? l10n.f47P7WidgetsShowLockedOn
                : l10n.f47P7WidgetsShowLockedOff,
            key: const Key('home-widgets-show-while-locked-explanation'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Un widget: su ícono, su nombre, qué hace y, si se puede, «Agregar».
class _WidgetRow extends ConsumerWidget {
  const _WidgetRow({required this.kind, required this.canAdd});

  final HomeWidgetKind kind;
  final bool canAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final (icon, name, description) = switch (kind) {
      HomeWidgetKind.dueToday => (
        Icons.event_available_outlined,
        l10n.f47P7WidgetDueToday,
        l10n.f47P7WidgetDueTodayDescription,
      ),
      HomeWidgetKind.quickCapture => (
        Icons.content_paste,
        l10n.f47P7WidgetQuickCapture,
        l10n.f47P7WidgetQuickCaptureDescription,
      ),
      HomeWidgetKind.continueListening => (
        Icons.headphones_outlined,
        l10n.f47P7WidgetContinueListening,
        l10n.f47P7WidgetContinueListeningDescription,
      ),
    };

    return Padding(
      key: Key('home-widget-${kind.name}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (canAdd) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                key: Key('home-widget-add-${kind.name}'),
                onPressed: () =>
                    unawaited(ref.read(homeScreenWidgetsProvider).add(kind)),
                icon: const Icon(Icons.add),
                // «Agregar» solo no dice qué: el lector de pantalla lo lee
                // con el nombre del widget.
                label: Text(
                  l10n.f47P7WidgetAdd,
                  semanticsLabel: l10n.f47P7WidgetAddSemantics(name),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
