import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_progress.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_result.dart';
import 'package:sinapsis/features/vault/presentation/providers/compaction_state.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_compaction_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Devolver al dispositivo el espacio que la bóveda ya no usa (F12).
///
/// Lo que se borra de la bóveda no siempre libera espacio: SQLite deja los
/// huecos dentro del archivo para reusarlos. Esta pantalla dice cuánto se
/// puede recuperar, si hay disco para hacerlo, y lo hace —comprobando al final
/// que no se perdió nada—.
///
/// Mientras compacta no se puede salir: la conexión de la bóveda está ocupada y
/// cualquier otra pantalla que la use se quedaría esperando. Para las fases que
/// se pueden parar hay un botón; para la que no —reescribir la bóveda entera la
/// primera vez—, el aviso lo dice antes de empezar.
class VaultCompactionScreen extends ConsumerWidget {
  const VaultCompactionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(compactionNotifierProvider);
    final running = state is CompactionRunning;

    // Lo que se devolvió cambia lo que dice la ficha de Ajustes.
    ref.listen(compactionNotifierProvider, (previous, next) {
      if (next is CompactionFinished) {
        ref.invalidate(compactionAssessmentProvider);
      }
    });

    return PopScope(
      canPop: !running,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.vaultCompactionTitle),
          automaticallyImplyLeading: !running,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: switch (state) {
                  CompactionIdle() => const _Idle(),
                  CompactionRunning(:final progress) => _Running(
                    progress: progress,
                  ),
                  CompactionFinished(:final result) => _Finished(
                    result: result,
                  ),
                  CompactionNoSpace(:final assessment) => _Problem(
                    message: l10n.vaultCompactionNoSpace(
                      formatFileSize(assessment.requiredBytes),
                      formatFileSize(assessment.freeSpaceBytes ?? 0),
                      formatFileSize(assessment.missingBytes),
                    ),
                  ),
                  CompactionFailed() => _Problem(
                    message: l10n.vaultCompactionFailed,
                  ),
                  CompactionVerificationFailed(:final problem) => _Problem(
                    message: l10n.vaultCompactionVerificationFailed(problem),
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Antes de empezar: cuánto ocupa la bóveda, cuánto se puede recuperar y si hay
/// disco para hacerlo.
class _Idle extends ConsumerWidget {
  const _Idle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final assessment = ref.watch(compactionAssessmentProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.storage_outlined,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.vaultCompactionExplanation,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        assessment.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Text(l10n.vaultCompactionMeasureFailed),
          data: (measured) => _Assessment(assessment: measured),
        ),
      ],
    );
  }
}

class _Assessment extends ConsumerWidget {
  const _Assessment({required this.assessment});

  final CompactionAssessment assessment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final nothing = assessment.verdict == CompactionVerdict.nothingToReclaim;

    void start() => ref.read(compactionNotifierProvider.notifier).start();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.vaultCompactionSizeLine(formatFileSize(assessment.fileBytes)),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          nothing
              ? l10n.vaultCompactionNothingLine
              : l10n.vaultCompactionReclaimableLine(
                  formatFileSize(assessment.reclaimableBytes),
                ),
          style: theme.textTheme.titleSmall,
        ),
        if (!nothing) ...[
          const SizedBox(height: 16),
          Text(
            assessment.needsFullRewrite
                ? l10n.vaultCompactionFirstTimeNote(
                    formatFileSize(assessment.requiredBytes),
                  )
                : l10n.vaultCompactionStepsNote,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          switch (assessment.verdict) {
            CompactionVerdict.notEnoughSpace => Text(
              l10n.vaultCompactionNoSpace(
                formatFileSize(assessment.requiredBytes),
                formatFileSize(assessment.freeSpaceBytes ?? 0),
                formatFileSize(assessment.missingBytes),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            CompactionVerdict.spaceUnknown => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.vaultCompactionSpaceUnknown,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: l10n.vaultCompactionActionAnyway,
                  onPressed: start,
                ),
              ],
            ),
            CompactionVerdict.ready => PrimaryButton(
              label: l10n.vaultCompactionAction,
              onPressed: start,
            ),
            CompactionVerdict.nothingToReclaim => const SizedBox.shrink(),
          },
        ],
      ],
    );
  }
}

/// Compactando: la fase, cuánto lleva y —si la fase lo admite— cómo parar.
class _Running extends ConsumerStatefulWidget {
  const _Running({required this.progress});

  final CompactionProgress progress;

  @override
  ConsumerState<_Running> createState() => _RunningState();
}

class _RunningState extends ConsumerState<_Running> {
  var _stopRequested = false;

  String _label(AppLocalizations l10n, CompactionProgress progress) =>
      switch (progress.phase) {
        CompactionPhase.checking => l10n.vaultCompactionPhaseChecking,
        CompactionPhase.rewriting => l10n.vaultCompactionPhaseRewriting,
        CompactionPhase.returning => l10n.vaultCompactionPhaseReturning(
          progress.done,
          progress.total,
        ),
        CompactionPhase.verifying =>
          progress.total > 0
              ? l10n.vaultCompactionPhaseVerifyingCount(
                  progress.done,
                  progress.total,
                )
              : l10n.vaultCompactionPhaseVerifying,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = widget.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _label(l10n, progress),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 16),
        // Sin avance que informar —medir, reescribir— el indicador no tiene
        // fin: no se inventa un porcentaje.
        LinearProgressIndicator(value: progress.fraction),
        const SizedBox(height: 16),
        Text(
          l10n.vaultCompactionKeepOpen,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (progress.phase.isCancellable) ...[
          const SizedBox(height: 24),
          OutlinedButton(
            // Pedirlo una vez alcanza: se atiende entre dos tramos.
            onPressed: _stopRequested
                ? null
                : () {
                    setState(() => _stopRequested = true);
                    ref.read(compactionNotifierProvider.notifier).cancel();
                  },
            child: Text(l10n.vaultCompactionStop),
          ),
        ],
      ],
    );
  }
}

/// Terminó, o se paró entre dos tramos.
class _Finished extends ConsumerWidget {
  const _Finished({required this.result});

  final CompactionResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final freed = formatFileSize(result.freedBytes);
    final headline = result.wasCancelled
        ? l10n.vaultCompactionStopped(freed)
        : result.freedBytes == 0
        ? l10n.vaultCompactionNothingReturned
        : l10n.vaultCompactionDone(
            freed,
            formatFileSize(result.bytesBefore),
            formatFileSize(result.bytesAfter),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          result.wasCancelled
              ? Icons.pause_circle_outline
              : Icons.check_circle_outline,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          headline,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        // La comprobación larga solo se hizo si se compactó de verdad.
        if (!result.wasCancelled && result.freedBytes > 0) ...[
          const SizedBox(height: 8),
          Text(
            l10n.vaultCompactionVerified(result.sourcesVerified),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 24),
        PrimaryButton(
          label: l10n.vaultCompactionDoneAction,
          onPressed: () {
            ref.read(compactionNotifierProvider.notifier).reset();
            Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }
}

/// Lo que impidió compactar, con cómo volver a intentarlo.
class _Problem extends ConsumerWidget {
  const _Problem({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: l10n.vaultCompactionDoneAction,
          onPressed: () {
            // De vuelta a la medición: lo que pasó puede haber cambiado lo que
            // hay para recuperar.
            ref.invalidate(compactionAssessmentProvider);
            ref.read(compactionNotifierProvider.notifier).reset();
          },
        ),
      ],
    );
  }
}
