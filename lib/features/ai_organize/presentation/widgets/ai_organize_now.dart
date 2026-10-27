import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
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
      _AiState.needsKey => l10n.aiOrganizeNowNeedsKey,
      _AiState.waiting => l10n.aiOrganizeNowWaits,
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
      _AiState.needsKey => l10n.aiOrganizeManyNeedsKey(count),
      _AiState.waiting => l10n.aiOrganizeManyWaits(count),
      _AiState.ready => l10n.aiOrganizeManyQueued(count),
    },
  );
}

/// Le pide a la IA que busque **solo las fechas** de [itemIds] para la línea
/// de tiempo (F40), y avisa qué va a pasar, con «Ver» para seguirlo en «Lo que
/// hizo la IA»: lo que usa «Organizar con IA» de la línea de tiempo y «Buscar
/// fechas con IA» del detalle.
///
/// No pide el modelo de vínculos —las fechas no lo usan—; el aviso es el mismo
/// de [organizeNowWithAi]: no dice «en un momento» si no es cierto.
Future<void> findDatesNowWithAi(
  BuildContext context,
  WidgetRef ref, {
  required List<String> itemIds,
  String? seeItemId,
}) {
  final l10n = AppLocalizations.of(context)!;
  final count = itemIds.length;
  return _organizeWithAi(
    context,
    ref,
    itemIds: itemIds,
    see: seeItemId == null
        ? RoutePaths.aiActivity
        : RoutePaths.aiActivityFor(seeItemId),
    enqueue: (queue) => queue.findDates(itemIds),
    needsEmbeddingModel: false,
    message: (state) => switch (state) {
      _AiState.paused => l10n.datesAskPaused(count),
      _AiState.needsModel => l10n.datesAskNeedsModel(count),
      _AiState.needsKey => l10n.datesAskNeedsKey(count),
      _AiState.waiting => l10n.datesAskWaits(count),
      _AiState.ready => l10n.datesAskQueued(count),
    },
  );
}

/// Si la IA va a poder hacer lo pedido ahora: en pausa, falta bajar un
/// modelo, falta una clave de la nube (F32), espera que vuelva la cuota o su
/// tope del día (F32), o sí.
enum _AiState { paused, needsModel, needsKey, waiting, ready }

Future<void> _organizeWithAi(
  BuildContext context,
  WidgetRef ref, {
  required List<String> itemIds,
  required String see,
  required String Function(_AiState state) message,
  void Function(AiOrganizeQueue queue)? enqueue,
  bool needsEmbeddingModel = true,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  // Lo que hace falta de `ref` se toma antes de esperar: para cuando los
  // modelos contestan, quien lo pidió puede haberse ido.
  final enabled = ref.read(aiOrganizeSettingsProvider).enabled;
  final languageModel = ref.read(languageModelStatusCheckProvider);
  final embeddingModel = ref.read(embeddingModelManagerProvider);
  final queue = ref.read(aiOrganizeQueueProvider);
  if (enqueue != null) {
    enqueue(queue);
  } else {
    queue.organizeAllNow(itemIds);
  }

  final _AiState state;
  if (!enabled) {
    state = _AiState.paused;
  } else {
    // Lo pedido lo hace la IA de fondo: con su tope del día.
    final language = await languageModel(background: true);
    // Organizar de verdad usa también el modelo de vínculos; solo las fechas,
    // no.
    final embeddingReady =
        !needsEmbeddingModel || await embeddingModel.isReady();
    state = switch (language) {
      _ when !embeddingReady => _AiState.needsModel,
      LanguageModelNeedsDownload() => _AiState.needsModel,
      LanguageModelNeedsAccount() => _AiState.needsKey,
      LanguageModelOutOfQuota() ||
      LanguageModelBackgroundCapReached() => _AiState.waiting,
      LanguageModelReady() => _AiState.ready,
    };
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
