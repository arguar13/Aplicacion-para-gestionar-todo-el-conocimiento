import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/features/relations/domain/usecases/backfill_embeddings_usecase.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Calcula bajo demanda los embeddings que le falten a lo ya capturado
/// antes de que el modelo estuviera descargado —el modelo en sí, una vez
/// listo, se usa solo en cada captura nueva (ver
/// `GenerateRelationSuggestionsUseCase`), pero lo ya guardado necesita
/// este empujón puntual (ver la decisión sobre F5, D13).
///
/// Mismo patrón de progreso que `VaultBackupScreen`, con una barra
/// determinada en vez de un giro indeterminado: acá sí se sabe de
/// antemano cuántas fuentes hay que recorrer.
class EmbeddingBackfillScreen extends ConsumerStatefulWidget {
  const EmbeddingBackfillScreen({super.key});

  @override
  ConsumerState<EmbeddingBackfillScreen> createState() =>
      _EmbeddingBackfillScreenState();
}

class _EmbeddingBackfillScreenState
    extends ConsumerState<EmbeddingBackfillScreen> {
  EmbeddingBackfillProgress? _progress;
  var _running = false;
  var _done = false;

  Future<void> _start() async {
    setState(() {
      _running = true;
      _done = false;
      _progress = null;
    });

    await for (final progress
        in ref.read(backfillEmbeddingsUseCaseProvider).call()) {
      if (!mounted) return;
      setState(() => _progress = progress);
    }
    if (!mounted) return;

    setState(() {
      _running = false;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.embeddingBackfillTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.embeddingBackfillExplanation,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _body(l10n),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_done) {
      final progress = _progress;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            progress == null
                ? l10n.embeddingBackfillNothingToDo
                : l10n.embeddingBackfillDone(progress.indexedChunks),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    if (_running) {
      final progress = _progress;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress == null || progress.totalItems == 0
                ? null
                : progress.processedItems / progress.totalItems,
          ),
          const SizedBox(height: 16),
          Text(
            progress == null
                ? l10n.embeddingBackfillStarting
                : l10n.embeddingBackfillProgress(
                    progress.processedItems,
                    progress.totalItems,
                  ),
          ),
        ],
      );
    }

    return PrimaryButton(
      label: l10n.embeddingBackfillStartAction,
      onPressed: _start,
    );
  }
}
