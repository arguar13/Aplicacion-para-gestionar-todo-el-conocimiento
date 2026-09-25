import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/quiz_review_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/quiz_session_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El botón «Generar quiz» (F20), en el detalle de un elemento: mismo
/// criterio que `GenerateDerivedNoteButton` para el modelo —sin él
/// descargado no hay nada que generar, así que se avisa y se ofrece ir a
/// descargarlo ANTES de generar nada—.
///
/// Solo la entrada desde UN elemento (F20, commit 6/N): `GenerateQuizUseCase`
/// genera y guarda para un único elemento por llamada —a diferencia de
/// `GenerateDerivedNoteUseCase`, que ya sabe resolver un cuaderno entero a
/// varias fuentes—, así que las entradas desde una rama del Atlas, un
/// cuaderno, una vista guardada o la pantalla de Repaso (todas resuelven a
/// VARIOS elementos) necesitan una orquestación que hoy no existe todavía;
/// quedan señaladas para un commit aparte en vez de forzarlas acá con un
/// bucle a medio probar.
class GenerateQuizButton extends ConsumerStatefulWidget {
  const GenerateQuizButton({required this.item, super.key});

  final KnowledgeItem item;

  @override
  ConsumerState<GenerateQuizButton> createState() => _GenerateQuizButtonState();
}

class _GenerateQuizButtonState extends ConsumerState<GenerateQuizButton> {
  var _loading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return IconButton(
      icon: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.quiz_outlined),
      tooltip: l10n.quizGenerateTooltip,
      onPressed: _loading ? null : _start,
    );
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context)!;
    final ready = await ref.read(chatModelManagerProvider).isReady();
    if (!mounted) return;

    if (!ready) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.quizModelRequired),
            action: SnackBarAction(
              label: l10n.derivedNoteDownloadAction,
              onPressed: () => context.push(RoutePaths.chatModel),
            ),
          ),
        );
      return;
    }

    setState(() => _loading = true);
    final result = await ref
        .read(generateQuizUseCaseProvider)
        .generate(item: widget.item);
    if (!mounted) return;
    setState(() => _loading = false);

    final questions = result.getRight().toNullable();
    if (questions == null) {
      final failure = result.getLeft().toNullable()!;
      _showMessage(failure.localizedMessage(l10n));
      return;
    }
    if (questions.isEmpty) {
      _showMessage(l10n.quizGenerationFailed);
      return;
    }

    final saved = await Navigator.of(context).push<List<Flashcard>>(
      MaterialPageRoute(
        builder: (context) =>
            QuizReviewScreen(item: widget.item, questions: questions),
      ),
    );
    if (saved == null || saved.isEmpty || !mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.quizSaved(saved.length)),
          action: SnackBarAction(
            label: l10n.quizSessionPracticeNow,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (context) => QuizSessionScreen(cards: saved),
              ),
            ),
          ),
        ),
      );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
