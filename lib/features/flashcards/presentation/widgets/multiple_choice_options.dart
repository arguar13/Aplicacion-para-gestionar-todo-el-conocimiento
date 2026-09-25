import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/flashcard_option.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/open_flashcard_source.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las opciones de una pregunta de opción múltiple (F20): mezcladas una vez
/// por pregunta —el orden guardado siempre trae la correcta primero
/// (`GenerateQuizUseCase.save`), mostrarlas tal cual volvería trivial la
/// pregunta—, tocar una la elige y revela de una vez cuál era la correcta,
/// con la procedencia de cada una (la correcta y las incorrectas).
///
/// Compartido entre la tarjeta de opción múltiple del repaso normal
/// (`ReviewScreen`, sigue tocando la programación SM-2 igual que cualquier
/// tarjeta) y la sesión suelta (F20, commit siguiente, no toca la
/// programación): la presentación es la misma en los dos casos, lo único
/// que cambia es qué hace quien la usa con [onAnswered].
class MultipleChoiceOptions extends StatefulWidget {
  const MultipleChoiceOptions({
    required this.options,
    required this.onAnswered,
    super.key,
  });

  final List<FlashcardOption> options;

  /// Se llama UNA vez, la primera vez que se toca una opción.
  final ValueChanged<FlashcardOption> onAnswered;

  @override
  State<MultipleChoiceOptions> createState() => _MultipleChoiceOptionsState();
}

class _MultipleChoiceOptionsState extends State<MultipleChoiceOptions> {
  late final List<FlashcardOption> _shuffled = List.of(widget.options)
    ..shuffle();
  FlashcardOption? _picked;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in _shuffled)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionTile(
              key: Key('quiz-option-${option.id}'),
              option: option,
              picked: _picked,
              onTap: _picked == null ? () => _pick(option) : null,
            ),
          ),
      ],
    );
  }

  void _pick(FlashcardOption option) {
    setState(() => _picked = option);
    widget.onAnswered(option);
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.picked,
    required this.onTap,
    super.key,
  });

  final FlashcardOption option;

  /// La opción elegida, o `null` si todavía no se contestó.
  final FlashcardOption? picked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final revealed = picked != null;

    final Color background;
    final Color border;
    final IconData? icon;
    if (!revealed) {
      background = theme.colorScheme.surfaceContainerLow;
      border = theme.colorScheme.outlineVariant.withValues(alpha: 0.6);
      icon = null;
    } else if (option.isCorrect) {
      background = theme.colorScheme.primaryContainer;
      border = theme.colorScheme.primary;
      icon = Icons.check_circle_outline;
    } else if (option.id == picked!.id) {
      background = theme.colorScheme.errorContainer;
      border = theme.colorScheme.error;
      icon = Icons.cancel_outlined;
    } else {
      background = theme.colorScheme.surfaceContainerLow;
      border = theme.colorScheme.outlineVariant.withValues(alpha: 0.3);
      icon = null;
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(child: Text(option.content)),
              if (icon != null) Icon(icon, color: border, size: 20),
              if (revealed && option.hasSourceRange)
                IconButton(
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  tooltip: l10n.flashcardsViewSource,
                  onPressed: () => openFlashcardOptionSource(context, option),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
