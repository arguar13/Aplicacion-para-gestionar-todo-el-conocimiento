import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_models/presentation/language_model_missing.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck_prompt.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_customize_sheet.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_coverage_reader.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_style.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/ai_flashcards_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Para cada documento» en la hoja de «Tarjetas didácticas» (F43, M18,
/// decisión O): lo que hacía el ✨ de la barra de Repasar (F30), sobre los
/// documentos procesados tildados en «Fuentes».
///
/// Cada documento recibe **sus** tarjetas con la cola de la IA de F30 —en
/// segundo plano, con su notificación, el aviso de arriba de Repasar y
/// «Lo que hizo la IA» para deshacer—. Quedan en el documento procesado, donde
/// Repasar las cuenta para cualquier recorte que lo tenga. No se arma un mazo
/// ni hay fila en «Lo creado».
///
/// El idioma, el tema, el número y la dificultad de la hoja van al pedido
/// ([deckEachDocumentStyle]); «Incluir imágenes» y «Sumar a mi repaso» son de
/// un mazo y no se muestran: las de cada documento entran siempre al repaso.
final deckEachDocument = CreationEachDocument(
  oneLabel: (l) => l.f43S21HowOne,
  eachLabel: (l) => l.f43S21HowEach,
  eachHint: (l) => l.f43S21HowEachHint,
  onlyForOne: const {CreationOptionValues.images, DeckOptionKeys.addToReview},
  panel: (context, each) => DeckEachDocumentPanel(each: each),
  action: (context, each) => DeckEachDocumentButton(each: each),
);

/// Lo elegido en la hoja, dicho para la cola de F30.
FlashcardStyle deckEachDocumentStyle(
  Map<String, Object?> options, {
  required String languageCode,
  required String topic,
}) => FlashcardStyle(
  languageCode: languageCode,
  difficulty: switch (options[CreationOptionValues.difficulty]) {
    CreationOptionValues.easy => FlashcardDifficulty.easy,
    CreationOptionValues.hard => FlashcardDifficulty.hard,
    _ => FlashcardDifficulty.medium,
  },
  topic: topic.trim(),
  amount: switch (options[CreationOptionValues.count]) {
    CreationOptionValues.fewer => FlashcardAmount.fewer,
    CreationOptionValues.more => FlashcardAmount.more,
    _ => FlashcardAmount.standard,
  },
);

/// De los documentos tildados, cuáles tienen texto del que salgan tarjetas y
/// cuáles ya tienen alguna (`FlashcardCoverageReader`, la misma cuenta de
/// F30); o el fallo, para decirlo.
final deckEachDocumentCoverageProvider = FutureProvider.autoDispose
    .family<Either<Failure, FlashcardCoverage>, CreationSourceIds>(
      (ref, key) =>
          ref.watch(flashcardCoverageReaderProvider).coverageOf(key.ids),
    );

/// A cuáles se les piden: los que no tienen ninguna o, con «También los que
/// ya tienen», todos los que tienen texto.
List<String> _wanted(FlashcardCoverage coverage, {required bool also}) =>
    also ? coverage.eligible : coverage.withoutCards;

/// Debajo de las opciones: cuántos entran y cuántos ya tienen tarjetas,
/// «También los que ya tienen tarjetas» y, si falta el modelo, cómo bajarlo.
class DeckEachDocumentPanel extends ConsumerWidget {
  const DeckEachDocumentPanel({required this.each, super.key});

  final CreationEachDocumentContext each;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final coverage = ref.watch(
      deckEachDocumentCoverageProvider(CreationSourceIds(each.sourceIds)),
    );
    final modelStatus = ref.watch(languageModelStatusProvider).valueOrNull;
    return Column(
      key: const Key('deck-each-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        _CoverageLine(coverage: coverage),
        const SizedBox(height: 4),
        SwitchListTile(
          key: const Key('deck-each-also-with-cards'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.reviewAiAlsoWithCards),
          subtitle: Text(l10n.reviewAiAlsoWithCardsHint),
          value: each.alsoExisting,
          onChanged: each.setAlsoExisting,
        ),
        if (modelStatus != null && !modelStatus.isReady) ...[
          const SizedBox(height: 8),
          LanguageModelMissingBanner(
            status: modelStatus,
            downloadMessage: l10n.flashcardsModelMissing,
            downloadLabel: l10n.flashcardsDownloadModel,
          ),
        ],
      ],
    );
  }
}

/// Cuántos entran y cuántos ya tienen tarjetas, o por qué no se pudo contar.
class _CoverageLine extends StatelessWidget {
  const _CoverageLine({required this.coverage});

  final AsyncValue<Either<Failure, FlashcardCoverage>> coverage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final error = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.error,
    );
    final child = switch (coverage) {
      AsyncValue(hasValue: false, hasError: false) => const Padding(
        key: ValueKey('loading'),
        padding: EdgeInsets.symmetric(vertical: 18),
        child: LinearProgressIndicator(),
      ),
      AsyncValue(hasError: true) => Text(
        l10n.f43S21CoverageFailed,
        key: const ValueKey('error'),
        style: error,
      ),
      AsyncValue(:final value) => value!.match(
        (failure) => Text(
          failure.localizedMessage(l10n),
          key: const ValueKey('failure'),
          style: error,
        ),
        (coverage) => _CoverageCounts(coverage: coverage),
      ),
    };
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      child: child,
    );
  }
}

/// Los dos números, en una tarjeta tranquila, leídos juntos por el lector de
/// pantalla.
class _CoverageCounts extends StatelessWidget {
  const _CoverageCounts({required this.coverage});

  final FlashcardCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MergeSemantics(
      child: Container(
        key: const Key('deck-each-coverage'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.style_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.f43S21Coverage(coverage.eligible.length),
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (coverage.eligible.isNotEmpty)
                    Text(
                      l10n.reviewAiCoverageWithCards(coverage.withCards.length),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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

/// El botón de abajo, que dice qué va a pasar: «Crear tarjetas de 8
/// documentos». Sin ninguno que pedir, o sin el modelo, no se puede.
class DeckEachDocumentButton extends ConsumerWidget {
  const DeckEachDocumentButton({required this.each, super.key});

  final CreationEachDocumentContext each;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final coverage = ref
        .watch(
          deckEachDocumentCoverageProvider(CreationSourceIds(each.sourceIds)),
        )
        .valueOrNull
        ?.getRight()
        .toNullable();
    final ready =
        ref.watch(languageModelStatusProvider).valueOrNull?.isReady ?? false;
    final ids = coverage == null
        ? const <String>[]
        : _wanted(coverage, also: each.alsoExisting);
    return FilledButton.icon(
      key: const Key('deck-each-start'),
      style: creationSheetButtonStyle,
      onPressed: ready && ids.isNotEmpty
          ? () {
              ref
                  .read(aiOrganizeQueueProvider)
                  .makeFlashcards(
                    ids,
                    anotherBatch: each.alsoExisting,
                    style: deckEachDocumentStyle(
                      each.options,
                      languageCode: each.languageCode,
                      topic: each.topic(),
                    ),
                  );
              unawaited(each.finish(l10n.reviewAiStarted));
            }
          : null,
      icon: const Icon(Icons.auto_awesome),
      label: Text(l10n.f43S21Start(ids.length)),
    );
  }
}
