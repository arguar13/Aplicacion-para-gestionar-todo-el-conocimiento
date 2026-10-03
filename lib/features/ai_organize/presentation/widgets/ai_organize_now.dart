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
}) {
  final l10n = AppLocalizations.of(context)!;
  return _organizeWithAi(
    context,
    ref,
    itemIds: [itemId],
    see: RoutePaths.aiActivityFor(itemId),
    message: (state) => switch (state) {
      _AiState.paused => l10n.aiOrganizeNowPaused,
      _AiState.needsModel => l10n.aiOrganizeNowNeedsModel,
      _AiState.ready => l10n.aiOrganizeNowQueued,
    },
  );
}

/// [organizeNowWithAi] para varios elementos a la vez: lo que ofrece el Mapa
/// para lo que quedó sin tema o sin etiquetas (F28). «Ver» abre todo lo que
/// hizo la IA, no lo de un elemento.
Future<void> organizeAllNowWithAi(
  BuildContext context,
  WidgetRef ref, {
  required List<String> itemIds,
}) {
  final l10n = AppLocalizations.of(context)!;
  final count = itemIds.length;
  return _organizeWithAi(
    context,
    ref,
    itemIds: itemIds,
    see: RoutePaths.aiActivity,
    message: (state) => switch (state) {
      _AiState.paused => l10n.aiOrganizeManyPaused(count),
      _AiState.needsModel => l10n.aiOrganizeManyNeedsModel(count),
      _AiState.ready => l10n.aiOrganizeManyQueued(count),
    },
  );
}

/// Si la IA va a poder hacer lo pedido ahora.
enum _AiState { paused, needsModel, ready }

Future<void> _organizeWithAi(
  BuildContext context,
  WidgetRef ref, {
  required List<String> itemIds,
  required String see,
  required String Function(_AiState state) message,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  // Lo que hace falta de `ref` se toma antes de esperar: para cuando los
  // modelos contestan, quien lo pidió puede haberse ido.
  final enabled = ref.read(aiOrganizeSettingsProvider).enabled;
  final chatModel = ref.read(chatModelManagerProvider);
  final embeddingModel = ref.read(embeddingModelManagerProvider);
  ref.read(aiOrganizeQueueProvider).organizeAllNow(itemIds);

  final _AiState state;
  if (!enabled) {
    state = _AiState.paused;
  } else {
    final ready = await Future.wait([
      chatModel.isReady(),
      embeddingModel.isReady(),
    ]);
    state = ready.every((r) => r) ? _AiState.ready : _AiState.needsModel;
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message(state)),
        action: SnackBarAction(
          label: l10n.aiItemLineSee,
          onPressed: () {
            if (!context.mounted) return;
            unawaited(context.push(see));
          },
        ),
      ),
    );
}
