import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/features/transform/presentation/widgets/processing_status.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Si al texto de [item] se le puede pedir que se vuelva a extraer (F22):
/// un audio, un video, un documento o una foto con su archivo, o un video de
/// YouTube; y que no se esté procesando ya. Una página web o una
/// publicación no: volver a bajarlas no es volver a leer el mismo original
/// —la página pudo cambiar—.
bool canReextractText(KnowledgeItem item) {
  if (item.isBeingProcessed) return false;
  return switch (item.source.kind) {
    SourceKind.youtube => item.source.url != null,
    SourceKind.audio ||
    SourceKind.video ||
    SourceKind.document ||
    SourceKind.image => item.source.originalFilePath != null,
    _ => false,
  };
}

/// Los idiomas que se ofrecen para un audio, por su nombre en su propio
/// idioma —así los reconoce quien lo habla—.
const _languageNames = {
  'es': 'Español',
  'en': 'English',
  'pt': 'Português',
  'fr': 'Français',
  'it': 'Italiano',
  'de': 'Deutsch',
};

/// "Volver a extraer el texto" (F22): lee el original otra vez con la
/// versión de hoy de la app —la transcripción sin bucles, el PDF con sus
/// renglones— y el texto nuevo toma el lugar del viejo, con los subrayados
/// llevados a su lugar. En un audio o un video, se elige antes en qué idioma
/// se habla: es la única forma de que Whisper transcriba un audio en inglés
/// sin traducirlo.
class ReextractTextButton extends ConsumerWidget {
  const ReextractTextButton({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton.icon(
      icon: const Icon(Icons.refresh, size: 18),
      label: Text(l10n.detailReextract),
      onPressed: () => _reextract(context, ref),
    );
  }

  Future<void> _reextract(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final asksLanguage = isTranscriptSource(item.source);
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => _ReextractDialog(
        asksLanguage: asksLanguage,
        initialLanguage: item.source.language ?? defaultTranscriptionLanguage,
      ),
    );
    if (chosen == null) return;

    if (asksLanguage && chosen != item.source.language) {
      final repository = ref.read(libraryRepositoryProvider);
      final current = (await repository.findById(
        item.id,
      )).getRight().toNullable();
      if (current != null) {
        await repository.save(
          current.copyWith(source: current.source.copyWith(language: chosen)),
        );
      }
    }
    await ref.read(processingQueueProvider.notifier).reextract(item.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.detailReextractStarted)));
  }
}

/// Devuelve el idioma elegido —o `''` si no se pregunta—, o `null` si se
/// canceló.
class _ReextractDialog extends StatefulWidget {
  const _ReextractDialog({
    required this.asksLanguage,
    required this.initialLanguage,
  });

  final bool asksLanguage;
  final String initialLanguage;

  @override
  State<_ReextractDialog> createState() => _ReextractDialogState();
}

class _ReextractDialogState extends State<_ReextractDialog> {
  late var _language = widget.initialLanguage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.detailReextract),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.detailReextractBody),
          if (widget.asksLanguage) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: InputDecoration(
                labelText: l10n.detailReextractLanguage,
              ),
              items: [
                for (final code in {
                  ...transcriptionLanguages,
                  widget.initialLanguage,
                })
                  DropdownMenuItem(
                    value: code,
                    child: Text(_languageNames[code] ?? code),
                  ),
              ],
              onChanged: (code) {
                if (code != null) setState(() => _language = code);
              },
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(widget.asksLanguage ? _language : ''),
          child: Text(l10n.detailReextractConfirm),
        ),
      ],
    );
  }
}

/// Mientras se vuelve a extraer el texto de un elemento que ya tenía: la
/// barra de avance —"Transcribiendo… 40 %"— y, si falló, el motivo y
/// "Reintentar", que sigue siendo volver a extraer (F22). El texto de antes
/// sigue abajo mientras tanto: no se toca hasta que el nuevo está listo.
class ReextractionStatus extends ConsumerWidget {
  const ReextractionStatus({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Los dos se escuchan siempre: suscribirse según el estado dejaba
    // temporizadores colgados cuando el estado cambiaba en medio de un
    // cuadro.
    final progress = ref.watch(processingProgressProvider(item.id));
    final failure = ref.watch(processingFailureProvider(item.id)).valueOrNull;
    final failed = item.processingState == ProcessingState.failed;

    if (failed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                failureMessage(l10n, failure) ?? l10n.detailReextract,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(processingQueueProvider.notifier).retry(item.id),
              child: Text(l10n.detailRetry),
            ),
          ],
        ),
      );
    }
    if (progress == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ProcessingProgressBar(progress: progress, kind: item.source.kind),
    );
  }
}
