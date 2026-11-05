import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/audio/lock_screen_title.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Mostrar el título en la pantalla de bloqueo» (F47, paso 7a-bis): si la
/// tarjeta de lo que suena deja ver qué suena sin desbloquear el teléfono. De
/// entrada, apagado; cambiarlo cambia la tarjeta que está a la vista.
///
/// Va en Ajustes › Privacidad. Es una pieza suelta para poder moverla si
/// «Voz y lectura» (paso 7b) la reclama.
///
/// La explicación va debajo, a todo el ancho, y no como subtítulo del
/// interruptor: con la letra al doble en un teléfono angosto, al costado del
/// interruptor quedaría en una columna de pocas letras.
class LockScreenTitleTile extends ConsumerWidget {
  const LockScreenTitleTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final show = ref.watch(lockScreenTitleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('settings-lock-screen-title'),
          secondary: const Icon(Icons.screen_lock_portrait_outlined),
          title: Text(l10n.f47P7bisLockScreenTitle),
          value: show,
          onChanged: (value) => unawaited(
            ref.read(lockScreenTitleProvider.notifier).set(show: value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            show ? l10n.f47P7bisLockScreenOn : l10n.f47P7bisLockScreenOff,
            key: const Key('settings-lock-screen-title-explanation'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
