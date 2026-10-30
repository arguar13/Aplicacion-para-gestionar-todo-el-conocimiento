import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/features/processed/domain/services/processed_tidy_queue.dart';
import 'package:sinapsis/features/processed/domain/services/tidy_check.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_tidy_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que dice el aviso de cómo terminó ordenar con la IA el texto de un
/// documento (F45, decisión B), o `null` si no hay nada que decir: no había
/// ninguna página que siguiera siendo de la fuente.
///
/// - Todo ordenado: que se ordenó, palabra por palabra igual.
/// - Una parte: cuánto se ordenó, y por qué lo demás quedó como se extrajo.
/// - Nada: que quedó como se extrajo, y por qué.
String? tidyOutcomeMessage(
  AppLocalizations l10n,
  ProcessedTidyOutcome outcome,
) {
  final title = outcome.title;
  if (outcome.end == ProcessedTidyEnd.unavailable) {
    return l10n.f45S2TidyUnavailable(title);
  }
  if (outcome.total == 0) return null;
  if (outcome.keptCount == 0) return l10n.f45S2TidyDone(title);
  final problem = switch (outcome.mainProblem) {
    TidyProblem.rewritten => l10n.f45S2ProblemRewritten,
    TidyProblem.invented => l10n.f45S2ProblemInvented,
    TidyProblem.missing => l10n.f45S2ProblemMissing,
    TidyProblem.reordered => l10n.f45S2ProblemReordered,
    null => l10n.f45S2ProblemNoReply,
  };
  if (outcome.tidied == 0) return l10n.f45S2TidyKept(title, problem);
  return l10n.f45S2TidyPartly(outcome.tidied, outcome.total, title, problem);
}

/// Muestra el aviso de cómo terminó ordenar el texto de lo que se trió (F45,
/// decisión B), esté en la pantalla que esté: la IA trabaja en segundo plano y
/// la persona ya puede estar en otro lado. Va en el `builder` de
/// `MaterialApp`, como `AiNoticeListener`.
///
/// Con «Ver», que abre el documento procesado.
class ProcessedTidyNoticeListener extends ConsumerStatefulWidget {
  const ProcessedTidyNoticeListener({
    required this.child,
    required this.onOpen,
    super.key,
  });

  final Widget child;

  /// Abre el documento procesado.
  final ValueChanged<String> onOpen;

  @override
  ConsumerState<ProcessedTidyNoticeListener> createState() =>
      _ProcessedTidyNoticeListenerState();
}

class _ProcessedTidyNoticeListenerState
    extends ConsumerState<ProcessedTidyNoticeListener> {
  StreamSubscription<ProcessedTidyOutcome>? _outcomes;

  @override
  void initState() {
    super.initState();
    _outcomes = ref.read(processedTidyQueueProvider).outcomes.listen(_show);
  }

  @override
  void dispose() {
    unawaited(_outcomes?.cancel());
    super.dispose();
  }

  void _show(ProcessedTidyOutcome outcome) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final message = tidyOutcomeMessage(l10n, outcome);
    if (message == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      AppSnackBar(
        key: const Key('tidy-snack'),
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: l10n.inboxView,
          onPressed: () {
            messenger.hideCurrentSnackBar();
            widget.onOpen(outcome.documentId);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
