import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Le pide a la IA que organice [itemId] ahora, antes que lo demás (F27), y
/// avisa qué va a pasar, con «Ver» para seguirlo en «Lo que hizo la IA».
///
/// Lo usan «Organizar con IA» en la hoja «Más» del panel de la fuente y
/// «Volver a organizar» en la línea del detalle: sirve igual para lo que es
/// de la biblioteca existente —que sin esto espera al cargador— y para lo
/// que se deshizo —que la IA no vuelve a tocar sola—.
///
/// El aviso no dice «en un momento» si no es cierto: con la IA en pausa o
/// sin uno de los dos modelos, el pedido queda anotado pero no avanza, y la
/// persona tiene que saber por qué.
Future<void> organizeNowWithAi(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  // Lo que hace falta de `ref` se toma antes de esperar: para cuando los
  // modelos contestan, quien lo pidió puede haberse ido.
  final enabled = ref.read(aiOrganizeSettingsProvider).enabled;
  final chatModel = ref.read(chatModelManagerProvider);
  final embeddingModel = ref.read(embeddingModelManagerProvider);
  ref.read(aiOrganizeQueueProvider).organizeNow(itemId);

  final String message;
  if (!enabled) {
    message = l10n.aiOrganizeNowPaused;
  } else {
    final ready = await Future.wait([
      chatModel.isReady(),
      embeddingModel.isReady(),
    ]);
    message = ready.every((r) => r)
        ? l10n.aiOrganizeNowQueued
        : l10n.aiOrganizeNowNeedsModel;
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: l10n.aiItemLineSee,
          onPressed: () {
            if (!context.mounted) return;
            unawaited(context.push(RoutePaths.aiActivityFor(itemId)));
          },
        ),
      ),
    );
}
