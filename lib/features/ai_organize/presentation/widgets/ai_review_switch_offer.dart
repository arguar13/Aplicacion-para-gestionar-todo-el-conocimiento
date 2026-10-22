import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_capability.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_scope.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_review_offer.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Al cambiar a un modelo más capaz, ofrece **una vez** que revise lo que
/// hizo el anterior (F33, decisión D): *«Cambiaste a Gemini 3.8 Flash.
/// ¿Querés que revise lo que hizo Gemma 4 E4B?»*, con «No, gracias».
///
/// No escucha el cambio en sí sino lo que queda: cuando el modelo elegido
/// está listo para contestar y tiene algo para revisar de uno menos capaz
/// (`isMoreCapableModel`), y todavía no se le ofreció. Así también sale
/// cuando el modelo nuevo recién queda listo —se bajó Gemma 4 12B, se cargó
/// la clave— y no mientras la persona todavía lo está preparando. Ofrecido
/// una vez, queda el botón de «Lo que hizo la IA».
///
/// Va por encima de toda pantalla, como la oferta de que siga con la app
/// cerrada: abre la hoja con el navegador principal ([navigatorKey]).
class AiReviewSwitchOfferListener extends ConsumerStatefulWidget {
  const AiReviewSwitchOfferListener({
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  @override
  ConsumerState<AiReviewSwitchOfferListener> createState() =>
      _AiReviewSwitchOfferListenerState();
}

class _AiReviewSwitchOfferListenerState
    extends ConsumerState<AiReviewSwitchOfferListener> {
  var _offering = false;

  @override
  void initState() {
    super.initState();
    ref
      ..listenManual(
        aiReviewOfferProvider,
        (_, _) => unawaited(_consider()),
        fireImmediately: true,
      )
      ..listenManual(
        languageModelStatusProvider,
        (_, _) => unawaited(_consider()),
      );
  }

  Future<void> _consider() async {
    if (_offering) return;
    final offer = ref.read(aiReviewOfferProvider);
    // Mientras se vuelve a contar, lo que tiene es del modelo de antes.
    if (offer.isLoading) return;
    final work = offer.valueOrNull ?? const <AiModelWork>[];
    // Una revisión a la vista: ya está revisando.
    if (ref.read(aiReviewBatchProvider) != null) return;
    final status = ref.read(languageModelStatusProvider).valueOrNull;
    if (status == null || !status.isReady) return;
    final reviewer = ref.read(aiReviewerNameProvider);
    final offers = ref.read(aiReviewSwitchOffersProvider);
    if (offers.wasOffered(reviewer)) return;
    // La de más cosas primero, como las cuenta la tarjeta.
    final earlier = work
        .where((w) => isMoreCapableModel(previous: w.model, next: reviewer))
        .firstOrNull;
    if (earlier == null) return;
    final navigator = widget.navigatorKey.currentContext;
    if (navigator == null) return;

    _offering = true;
    try {
      await offers.markOffered(reviewer);
      if (!navigator.mounted) return;
      final wantsReview = await showModalBottomSheet<bool>(
        context: navigator,
        showDragHandle: true,
        // Con letra grande o en un teléfono chico, el texto entero.
        isScrollControlled: true,
        builder: (_) =>
            _AiReviewSwitchOfferSheet(reviewer: reviewer, earlier: earlier),
      );
      if (!(wantsReview ?? false) || !navigator.mounted) return;
      await startAiReview(navigator, ref, madeBy: earlier.model);
    } finally {
      _offering = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AiReviewSwitchOfferSheet extends StatelessWidget {
  const _AiReviewSwitchOfferSheet({
    required this.reviewer,
    required this.earlier,
  });

  /// El modelo elegido ahora, como lo guardan las pasadas.
  final String reviewer;

  /// Lo que hizo el modelo anterior y falta revisar.
  final AiModelWork earlier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final model = modelLabel(reviewer);
    final madeBy = earlier.model == null
        ? l10n.aiRecheckEarlierModel
        : modelLabel(earlier.model!);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.aiRecheckSwitchTitle(model),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.aiRecheckSwitchBody(
                madeBy,
                l10n.aiRecheckThings(earlier.things),
                l10n.aiRecheckItems(earlier.items),
              ),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const Key('ai-review-switch-later'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.aiRecheckSwitchLater),
                ),
                FilledButton.icon(
                  key: const Key('ai-review-switch-review'),
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(l10n.aiRecheckWith(model)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
