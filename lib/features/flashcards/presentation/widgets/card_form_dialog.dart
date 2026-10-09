import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_form.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer_alternatives.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_form_cloze_preview.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las formas de tarjeta que se pueden armar a mano (F31, decisión 73).
enum CardFormKind {
  /// Pregunta y respuesta.
  qa,

  /// Las dos direcciones: dos tarjetas hermanas.
  bothDirections,

  /// Huecos para completar.
  cloze,

  /// «Escribí la respuesta».
  typed,

  /// Opción múltiple, con una respuesta correcta y opciones incorrectas.
  multipleChoice,

  /// Huecos que propone el modelo de lenguaje: no se llena nada acá, la
  /// pantalla que abrió el formulario sigue con la generación.
  clozeAi,
}

/// Lo que devuelve [showCardFormDialog].
sealed class CardFormDialogResult {
  const CardFormDialogResult();
}

/// La persona llenó una forma y la guardó.
class CardFormSubmitted extends CardFormDialogResult {
  const CardFormSubmitted(this.form);

  final CardForm form;
}

/// La persona pidió que el modelo proponga frases con huecos.
class CardFormAiRequested extends CardFormDialogResult {
  const CardFormAiRequested();
}

/// El formulario de una tarjeta: elegir la forma (pregunta y respuesta, dos
/// direcciones, huecos, «escribí la respuesta», opción múltiple o huecos con
/// IA), llenarla, y verla antes de guardar (F31, decisión 73).
///
/// No guarda nada: devuelve lo que se llenó (o `null` si se cancela) y quien
/// lo abrió lo guarda.
///
/// [initialBack] pone algo escrito en la respuesta —el fragmento que se
/// seleccionó al crear la tarjeta desde la lectura—. [aiAvailable] ofrece la
/// forma «Huecos con IA».
///
/// Con [card] edita una que ya existe y **vuelve a mostrar su forma**: una de
/// huecos se edita como huecos y una de «escribí la respuesta» como tal, no
/// como pregunta y respuesta. [siblingNumbers] son los números de hueco que
/// ya tiene el texto en sus hermanas, para avisar cuáles tarjetas se borrarían
/// si se saca un hueco. Una de opción múltiple no se edita acá.
Future<CardFormDialogResult?> showCardFormDialog(
  BuildContext context, {
  String? initialBack,
  bool aiAvailable = false,
  Flashcard? card,
  List<int> siblingNumbers = const [],
}) {
  assert(
    card == null || card.kind != FlashcardKind.multipleChoice,
    'Una tarjeta de opción múltiple no se edita en este formulario.',
  );
  return showDialog<CardFormDialogResult>(
    context: context,
    builder: (context) => CardFormDialog(
      initialBack: initialBack,
      aiAvailable: aiAvailable,
      card: card,
      siblingNumbers: siblingNumbers,
    ),
  );
}

class CardFormDialog extends StatefulWidget {
  const CardFormDialog({
    this.initialBack,
    this.aiAvailable = false,
    this.card,
    this.siblingNumbers = const [],
    super.key,
  });

  final String? initialBack;
  final bool aiAvailable;
  final Flashcard? card;
  final List<int> siblingNumbers;

  @override
  State<CardFormDialog> createState() => _CardFormDialogState();
}

class _CardFormDialogState extends State<CardFormDialog> {
  static const _distractorFields = 3;

  late CardFormKind _kind = _kindOf(widget.card);

  // Compartidos entre pregunta y respuesta, dos direcciones y «escribí la
  // respuesta»: lo escrito sobrevive a cambiar de forma.
  late final _front = TextEditingController(text: widget.card?.front);
  late final _back = TextEditingController(text: _initialBack());
  late final _alternatives = TextEditingController(
    text: _initialAlternatives(),
  );

  late final _clozeText = TextEditingController(
    text: widget.card?.kind == FlashcardKind.cloze ? widget.card!.front : null,
  );
  late final _clozeExtra = TextEditingController(
    text: widget.card?.kind == FlashcardKind.cloze ? widget.card!.back : null,
  );

  final _correct = TextEditingController();
  final _distractors = [
    for (var i = 0; i < _distractorFields; i++) TextEditingController(),
  ];

  List<TextEditingController> get _all => [
    _front,
    _back,
    _alternatives,
    _clozeText,
    _clozeExtra,
    _correct,
    ..._distractors,
  ];

  bool get _editing => widget.card != null;

  static CardFormKind _kindOf(Flashcard? card) => switch (card?.kind) {
    FlashcardKind.cloze => CardFormKind.cloze,
    FlashcardKind.typedAnswer => CardFormKind.typed,
    _ => CardFormKind.qa,
  };

  String? _initialBack() {
    final card = widget.card;
    if (card == null) return widget.initialBack;
    return card.kind == FlashcardKind.typedAnswer
        ? TypedAnswerSpec.parse(card.back).answer
        : card.back;
  }

  String? _initialAlternatives() {
    final card = widget.card;
    if (card == null || card.kind != FlashcardKind.typedAnswer) return null;
    return TypedAnswerSpec.parse(card.back).alternatives.join('\n');
  }

  @override
  void initState() {
    super.initState();
    for (final controller in _all) {
      controller.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final controller in _all) {
      controller
        ..removeListener(_changed)
        ..dispose();
    }
    super.dispose();
  }

  String _text(TextEditingController c) => c.text.trim();

  List<String> get _alternativeLines => [
    for (final line in _alternatives.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  List<String> get _filledDistractors => [
    for (final c in _distractors)
      if (c.text.trim().isNotEmpty) c.text.trim(),
  ];

  /// Lo que se llenó, como forma; `null` si falta algo para guardarla.
  CardForm? get _form => switch (_kind) {
    // Pregunta y respuesta no se valida acá: lo hace quien la crea, como
    // siempre.
    CardFormKind.qa => QaCardForm(front: _front.text, back: _back.text),
    CardFormKind.bothDirections =>
      _text(_front).isEmpty || _text(_back).isEmpty
          ? null
          : BothDirectionsCardForm(front: _front.text, back: _back.text),
    CardFormKind.typed =>
      _text(_front).isEmpty || _text(_back).isEmpty
          ? null
          : TypedCardForm(
              front: _front.text,
              answer: _back.text,
              alternatives: _alternativeLines,
            ),
    CardFormKind.cloze =>
      validateCloze(_clozeText.text.trim()).isNotEmpty
          ? null
          : ClozeCardForm(text: _clozeText.text, extra: _clozeExtra.text),
    CardFormKind.multipleChoice =>
      _text(_front).isEmpty ||
              _text(_correct).isEmpty ||
              _filledDistractors.isEmpty
          ? null
          : MultipleChoiceCardForm(
              question: _front.text,
              correct: _correct.text,
              distractors: _filledDistractors,
            ),
    CardFormKind.clozeAi => null,
  };

  bool get _canSubmit =>
      _kind == CardFormKind.clozeAi ? !_editing : _form != null;

  void _submit() {
    if (_kind == CardFormKind.clozeAi) {
      Navigator.of(context).pop(const CardFormAiRequested());
      return;
    }
    final form = _form;
    if (form == null) return;
    Navigator.of(context).pop(CardFormSubmitted(form));
  }

  /// Envuelve lo seleccionado en el siguiente hueco libre (`{{c3::…}}`).
  void _coverSelection() {
    final selection = _clozeText.selection;
    final text = _clozeText.text;
    if (!selection.isValid || selection.isCollapsed) return;
    final number = nextClozeNumber(text);
    final wrapped = wrapAsCloze(
      text,
      selection.start,
      selection.end,
      number: number,
    );
    if (wrapped == text) return;
    // El cursor queda justo después del hueco: sumó `{{cN::` antes y `}}`
    // después de lo seleccionado.
    final opening = '{{c$number::'.length;
    _clozeText.value = TextEditingValue(
      text: wrapped,
      selection: TextSelection.collapsed(offset: selection.end + opening + 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(
        _editing ? l10n.flashcardsEditAction : l10n.flashcardsAddAction,
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_editing) ...[_kindChips(l10n), const SizedBox(height: 12)],
              ..._body(l10n),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(
            _kind == CardFormKind.clozeAi
                ? l10n.cardFormAiGenerate
                : l10n.detailSave,
          ),
        ),
      ],
    );
  }

  Widget _kindChips(AppLocalizations l10n) {
    final labels = {
      CardFormKind.qa: l10n.cardFormKindQa,
      CardFormKind.bothDirections: l10n.cardFormKindBoth,
      CardFormKind.cloze: l10n.cardFormKindCloze,
      CardFormKind.typed: l10n.cardFormKindTyped,
      CardFormKind.multipleChoice: l10n.cardFormKindChoice,
      if (widget.aiAvailable) CardFormKind.clozeAi: l10n.cardFormKindClozeAi,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final entry in labels.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: _kind == entry.key,
            onSelected: (_) => setState(() => _kind = entry.key),
          ),
      ],
    );
  }

  List<Widget> _body(AppLocalizations l10n) => switch (_kind) {
    CardFormKind.qa => _qaFields(l10n),
    CardFormKind.bothDirections => _bothFields(l10n),
    CardFormKind.cloze => _clozeFields(l10n),
    CardFormKind.typed => _typedFields(l10n),
    CardFormKind.multipleChoice => _choiceFields(l10n),
    CardFormKind.clozeAi => [
      Text(l10n.cardFormAiHelp, style: Theme.of(context).textTheme.bodyMedium),
    ],
  };

  Widget _field(
    TextEditingController controller,
    String hint, {
    bool autofocus = false,
    int maxLines = 4,
    Key? key,
  }) => TextField(
    key: key,
    controller: controller,
    autofocus: autofocus,
    minLines: 1,
    maxLines: maxLines,
    decoration: InputDecoration(hintText: hint),
  );

  Widget _help(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  List<Widget> _qaFields(AppLocalizations l10n) => [
    _field(_front, l10n.flashcardsFrontHint, autofocus: true),
    const SizedBox(height: 12),
    _field(_back, l10n.flashcardsBackHint, maxLines: 6),
  ];

  List<Widget> _bothFields(AppLocalizations l10n) {
    final front = _text(_front);
    final back = _text(_back);
    return [
      _help(l10n.cardFormBothHelp),
      ..._qaFields(l10n),
      if (front.isNotEmpty && back.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          l10n.cardFormPreviewTitle,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        _PreviewCard(label: l10n.cardFormBothForward, front: front, back: back),
        const SizedBox(height: 6),
        _PreviewCard(
          label: l10n.cardFormBothBackward,
          front: back,
          back: front,
        ),
      ],
    ];
  }

  List<Widget> _typedFields(AppLocalizations l10n) => [
    _help(l10n.cardFormTypedHelp),
    _field(_front, l10n.flashcardsFrontHint, autofocus: true),
    const SizedBox(height: 12),
    _field(_back, l10n.cardFormTypedAnswerHint),
    const SizedBox(height: 12),
    _field(
      _alternatives,
      l10n.cardFormTypedAlternativesHint,
      key: const ValueKey('cardFormAlternatives'),
    ),
  ];

  List<Widget> _choiceFields(AppLocalizations l10n) => [
    _help(l10n.cardFormChoiceHelp),
    _field(_front, l10n.cardFormChoiceQuestionHint, autofocus: true),
    const SizedBox(height: 12),
    _field(_correct, l10n.cardFormChoiceCorrectHint),
    for (var i = 0; i < _distractorFields; i++) ...[
      const SizedBox(height: 12),
      _field(_distractors[i], l10n.cardFormChoiceDistractorHint(i + 1)),
    ],
  ];

  List<Widget> _clozeFields(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final text = _clozeText.text.trim();
    final problems = text.isEmpty
        ? const <ClozeProblem>[]
        : validateCloze(text);
    final parsedNumbers = text.isEmpty
        ? const <int>[]
        : parseCloze(text).numbers;
    final removed = _editing
        ? [
            for (final number in widget.siblingNumbers)
              if (!parsedNumbers.contains(number)) number,
          ]
        : const <int>[];

    return [
      _help(l10n.cardFormClozeHelp),
      _field(
        _clozeText,
        l10n.cardFormClozeTextHint,
        autofocus: true,
        maxLines: 8,
        key: const ValueKey('cardFormClozeText'),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed:
              _clozeText.selection.isValid && !_clozeText.selection.isCollapsed
              ? _coverSelection
              : null,
          icon: const Icon(Icons.format_color_fill, size: 18),
          label: Text(l10n.cardFormClozeCover),
        ),
      ),
      const SizedBox(height: 12),
      _field(_clozeExtra, l10n.cardFormClozeExtraHint),
      const SizedBox(height: 12),
      for (final problem in problems)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            clozeProblemMessage(problem),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      if (problems.isEmpty) ClozeCardsPreview(text: text),
      if (removed.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.cardFormClozeRemovesCards(removed.length),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
    ];
  }
}

/// Una de las tarjetas de «dos direcciones», como se va a ver: de qué lado
/// sale la pregunta y de cuál la respuesta.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.label,
    required this.front,
    required this.back,
  });

  final String label;
  final String front;
  final String back;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(front, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(
              back,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
