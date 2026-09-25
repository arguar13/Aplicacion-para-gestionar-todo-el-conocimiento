import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/flashcards/domain/usecases/generate_quiz_usecase.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Revisar un quiz recién generado antes de guardar nada (F20, «revisión
/// obligatoria antes»): cada pregunta se puede incluir o descartar por
/// separado, nunca se guarda el lote entero a ciegas —mismo criterio que la
/// revisión de tarjetas comunes (`_FlashcardDraftReviewDialog`)—.
///
/// Sin edición de texto a propósito: ni esa revisión ni la de sugerencias de
/// propiedad (`PropertySuggestionsReviewScreen`) dejan tocar lo que propuso
/// el modelo, solo aceptar o descartar. Acá hay una razón más fuerte todavía
/// para no editar: el texto de cada opción tiene que seguir siendo
/// EXACTAMENTE el que su ancla (`sourceChunkId`/`sourceCharStart`/
/// `sourceCharEnd`) señala —editarlo dejaría la tarjeta citando un fragmento
/// que ya no dice eso—.
///
/// Una pantalla completa, no un diálogo (a diferencia de la revisión de
/// tarjetas comunes): una pregunta de quiz trae varias opciones con su
/// propia procedencia cada una, más contenido por pregunta del que entra
/// cómodo en un `AlertDialog`. Se llega por `Navigator.push` con el
/// resultado ya generado en la propia navegación —mismo patrón que
/// `BlockEditorScreen`—, no por una ruta de `GoRouter`: no tiene sentido
/// poder volver a entrar por URL a revisar un lote que, si no se guarda, deja
/// de existir.
class QuizReviewScreen extends ConsumerStatefulWidget {
  const QuizReviewScreen({
    required this.item,
    required this.questions,
    super.key,
  });

  final KnowledgeItem item;
  final List<QuizQuestionResult> questions;

  @override
  ConsumerState<QuizReviewScreen> createState() => _QuizReviewScreenState();
}

class _QuizReviewScreenState extends ConsumerState<QuizReviewScreen> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.questions.length; i++) i,
  };
  var _saving = false;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);

    final confirmed = [for (final index in _selected) widget.questions[index]];
    final result = await ref
        .read(generateQuizUseCaseProvider)
        .save(itemId: widget.item.id, confirmed: confirmed);
    if (!mounted) return;

    result.match((failure) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
    }, (saved) => Navigator.of(context).pop(saved));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.quizReviewTitle)),
      body: ListView.builder(
        itemCount: widget.questions.length,
        itemBuilder: (context, index) => _QuestionTile(
          key: Key('quiz-question-$index'),
          question: widget.questions[index],
          selected: _selected.contains(index),
          onChanged: (checked) => setState(() {
            if (checked) {
              _selected.add(index);
            } else {
              _selected.remove(index);
            }
          }),
        ),
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.quizReviewConfirm(_selected.length)),
                ),
              ),
            ),
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({
    required this.question,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final QuizQuestionResult question;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CheckboxListTile(
      value: selected,
      onChanged: (checked) => onChanged(checked ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      isThreeLine: false,
      title: Text(question.question),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question.correctAnswer,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final distractor in question.distractors)
              Text(
                distractor.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
