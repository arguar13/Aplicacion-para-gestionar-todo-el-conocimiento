import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_library_progress.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/features/dev_seed/presentation/providers/sample_library_providers.dart';
import 'package:sinapsis/features/dev_seed/presentation/providers/sample_library_state.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La fila de Ajustes que carga la biblioteca de ejemplo (solo en dev y
/// staging): un toque, una confirmación con cuánto se baja, y el resto en
/// segundo plano, con su avance acá mismo y la opción de cancelar.
///
/// Al terminar avisa con un mensaje abajo, aunque se haya salido de
/// Ajustes y vuelto; y si algo falló, la lista de qué y por qué queda a un
/// toque, en la misma fila.
class SampleLibraryTile extends ConsumerWidget {
  const SampleLibraryTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(sampleLibraryProvider);

    ref.listen<SampleLibraryState>(sampleLibraryProvider, (previous, next) {
      if (previous is! SampleLibraryLoading || next is! SampleLibraryFinished) {
        return;
      }
      final report = next.report;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l10n.sampleLibraryDoneSnack(
                report.loaded,
                report.failures.length,
              ),
            ),
            action: report.failures.isEmpty
                ? null
                : SnackBarAction(
                    label: l10n.sampleLibraryShowFailures,
                    onPressed: () => _showFailures(context, report.failures),
                  ),
          ),
        );
    });

    return switch (state) {
      SampleLibraryLoading(:final progress, :final cancelling) => ListTile(
        key: const Key('sample-library-tile'),
        leading: const Icon(Icons.cloud_download_outlined),
        title: Text(
          cancelling
              ? l10n.sampleLibraryCancellingTitle
              : l10n.sampleLibraryLoadingTitle,
        ),
        subtitle: _ProgressSubtitle(progress: progress),
        trailing: TextButton(
          key: const Key('sample-library-cancel'),
          onPressed: cancelling
              ? null
              : () => ref.read(sampleLibraryProvider.notifier).cancel(),
          child: Text(l10n.commonCancel),
        ),
      ),
      _ => _IdleTile(state: state),
    };
  }
}

/// La fila cuando no se está cargando: lo que falta, o cómo terminó la
/// última pasada.
class _IdleTile extends ConsumerWidget {
  const _IdleTile({required this.state});

  final SampleLibraryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Se recalcula con cada cambio de estado —esta fila lo observa—: al
    // terminar una pasada, lo que falta es menos.
    final pending = ref.watch(loadSampleLibraryUseCaseProvider).pending();
    final total = ref.watch(sampleLibraryResourcesProvider).length;
    final failures = switch (state) {
      SampleLibraryFinished(:final report) => report.failures,
      _ => const <SampleLoadFailure>[],
    };

    final subtitle = switch (state) {
      SampleLibraryFinished(:final report) when report.cancelled =>
        l10n.sampleLibraryLastRunCancelled(
          report.loaded,
          report.failures.length,
        ),
      SampleLibraryFinished(:final report) => l10n.sampleLibraryLastRun(
        report.loaded,
        report.failures.length,
        report.alreadyLoaded,
      ),
      SampleLibraryFailed(:final message) => l10n.sampleLibraryFailed(message),
      _ when pending.isEmpty => l10n.sampleLibraryAllLoaded(total),
      _ => l10n.sampleLibrarySubtitle(
        pending.length,
        formatFileSize(_bytes(pending)),
      ),
    };

    return ListTile(
      key: const Key('sample-library-tile'),
      leading: const Icon(Icons.library_add_outlined),
      title: Text(l10n.sampleLibraryTitle),
      subtitle: Text(subtitle),
      trailing: failures.isEmpty
          ? null
          : IconButton(
              key: const Key('sample-library-failures'),
              icon: const Icon(Icons.error_outline),
              tooltip: l10n.sampleLibraryShowFailures,
              onPressed: () => _showFailures(context, failures),
            ),
      enabled: pending.isNotEmpty,
      onTap: () => _confirmAndStart(context, ref, pending),
    );
  }

  Future<void> _confirmAndStart(
    BuildContext context,
    WidgetRef ref,
    List<SampleResource> pending,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final files = pending.whereType<SampleFile>();
    final links = pending.whereType<SampleLink>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sampleLibraryConfirmTitle),
        content: Text(
          l10n.sampleLibraryConfirmBody(
            pending.length,
            formatFileSize(_bytes(files)),
            formatFileSize(_bytes(links)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('sample-library-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.sampleLibraryConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Sin esperar: la carga sigue aunque se salga de Ajustes.
    ref.read(sampleLibraryProvider.notifier).start().ignore();
  }

  static int _bytes(Iterable<SampleResource> resources) =>
      resources.fold(0, (sum, resource) => sum + resource.approxBytes);
}

/// Cuánto va, con una barra: «23 de 80 · tanda 3 de 8» y lo que se está
/// cargando ahora.
class _ProgressSubtitle extends StatelessWidget {
  const _ProgressSubtitle({required this.progress});

  final SampleLoadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = this.progress;
    final current = progress?.current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          progress == null
              ? l10n.sampleLibraryStarting
              : l10n.sampleLibraryProgress(
                  progress.done,
                  progress.total,
                  progress.batch,
                  progress.batches,
                ),
        ),
        if (current != null)
          Text(current, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progress == null || progress.total == 0
              ? null
              : progress.done / progress.total,
        ),
      ],
    );
  }
}

/// La lista de lo que no se pudo cargar, con el motivo de cada uno.
Future<void> _showFailures(
  BuildContext context,
  List<SampleLoadFailure> failures,
) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.sampleLibraryFailuresTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final failure in failures)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(failure.title),
                subtitle: Text(failure.reason),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    ),
  );
}
