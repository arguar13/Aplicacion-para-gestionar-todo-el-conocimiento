import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/flashcards_kind.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/widgets/study_viewer_parts.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_flip_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El visor de «Tarjetas didácticas» (F43, paso 8): **la misma tarjeta de
/// Repasar** (`ReviewFlipCard`), que se da vuelta al tocarla, adaptada a
/// hojear el mazo —se desliza a la anterior o a la siguiente—, con «3 / 20»,
/// anterior y siguiente, barajar y «Sumar a mi repaso».
///
/// Hojear no califica nada: el calendario de las tarjetas no cambia. Lo que se
/// repasa de verdad es lo de «Para hoy», con las mismas tarjetas si el mazo
/// está sumado.
class FlashcardDeckViewer extends ConsumerStatefulWidget {
  const FlashcardDeckViewer({required this.creation, super.key});

  final StudyCreation creation;

  @override
  ConsumerState<FlashcardDeckViewer> createState() =>
      _FlashcardDeckViewerState();
}

class _FlashcardDeckViewerState extends ConsumerState<FlashcardDeckViewer> {
  late FlashcardDeck _deck = _decode(widget.creation);
  late List<int> _order = _identity(_deck.cards.length);
  final _pages = PageController();
  var _index = 0;
  var _flipped = false;
  var _shuffled = false;

  /// Mientras se suma o se saca del repaso: el interruptor espera.
  var _saving = false;

  static FlashcardDeck _decode(StudyCreation creation) =>
      FlashcardDeckJson.decode(creation.decodedContent);

  static List<int> _identity(int length) => [
    for (var i = 0; i < length; i++) i,
  ];

  @override
  void didUpdateWidget(FlashcardDeckViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.creation.content == widget.creation.content) return;
    final deck = _decode(widget.creation);
    // Lo que cambia sin volver a generar (sumar o sacar del repaso) conserva
    // dónde se estaba; un mazo distinto empieza de nuevo.
    final sameCards = deck.cards.length == _deck.cards.length;
    setState(() {
      _deck = deck;
      if (!sameCards) {
        _order = _identity(deck.cards.length);
        _index = 0;
        _flipped = false;
        _shuffled = false;
        if (_pages.hasClients) _pages.jumpToPage(0);
      }
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _goTo(int index) {
    if (index < 0 || index >= _order.length || index == _index) return;
    if (_reduceMotion) {
      _pages.jumpToPage(index);
    } else {
      unawaited(
        _pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _onPageChanged(int index) => setState(() {
    _index = index;
    _flipped = false;
  });

  /// Barajar, o volver al orden del mazo, sin perder la tarjeta de ahora.
  void _toggleShuffle() {
    final current = _order[_index];
    final order = _shuffled
        ? _identity(_order.length)
        : (_identity(_order.length)..shuffle(math.Random()));
    // La de ahora queda primera al barajar, para que barajar no la saque de
    // la vista; al volver al orden, en su lugar.
    if (!_shuffled) {
      order
        ..remove(current)
        ..insert(0, current);
    }
    final index = order.indexOf(current);
    setState(() {
      _order = order;
      _shuffled = !_shuffled;
      _index = index;
      _flipped = false;
    });
    _pages.jumpToPage(index);
  }

  Future<void> _setInReview(bool value) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final review = ref.read(deckReviewProvider);
    final repository = ref.read(studyCreationRepositoryProvider);
    setState(() => _saving = true);
    final changed = value
        ? await review.add(
            _deck,
            fallbackDocument: widget.creation.sourceIds.firstOrNull,
          )
        : await review.remove(_deck);
    final saved = await changed.match(
      (_) async => false,
      (deck) async => (await repository.amend(
        widget.creation.id,
        content: FlashcardDeckJson.encodeString(deck),
      )).isRight(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(AppSnackBar(content: Text(l10n.f43CardsInReviewFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final deck = _deck;
    if (deck.isEmpty) {
      return Center(
        key: const Key('deck-viewer-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.f43CardsEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    final accent = ref
        .watch(creationKindRegistryProvider)
        .of(widget.creation.kind)
        .accent
        .of(context);
    final wantsImages = studyCreationWantsImages(widget.creation);
    final total = _order.length;
    final failure = deck.illustrationFailure;

    final notice = wantsImages && failure != null
        ? StudyIllustrationNotice(
            failure: failure,
            account: deck.illustrationAccount,
            message: l10n.f43CardsIllustrationsMissing,
          )
        : null;
    final header = _DeckHeader(
      index: _index,
      total: total,
      accent: accent,
      shuffled: _shuffled,
      onShuffle: total > 1 ? _toggleShuffle : null,
    );
    final pages = PageView.builder(
      key: const Key('deck-pages'),
      controller: _pages,
      itemCount: total,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, page) {
        final position = _order[page];
        final card = deck.cards[position];
        return _DeckPage(
          key: ValueKey('deck-page-${card.id}'),
          card: card,
          number: page + 1,
          total: total,
          flipped: page == _index && _flipped,
          onFlip: () => setState(() => _flipped = !_flipped),
          picture: wantsImages || card.illustrationRef != null
              ? StudyItemPicture(
                  reference: card.illustrationRef,
                  icon: card.icon,
                  seed: position,
                  accent: accent,
                  semanticLabel: l10n.f43CardsPictureSemantics,
                )
              : null,
        );
      },
    );
    final controls = _DeckControls(
      canGoBack: _index > 0,
      canGoOn: _index < total - 1,
      onPrevious: () => _goTo(_index - 1),
      onNext: () => _goTo(_index + 1),
      onFlip: () => setState(() => _flipped = !_flipped),
    );
    final review = _ReviewSwitch(
      inReview: deck.inReview,
      saving: _saving,
      onChanged: (value) => unawaited(_setInReview(value)),
    );

    return LayoutBuilder(
      key: const Key('deck-viewer'),
      builder: (context, constraints) {
        // Con la letra grande o una pantalla baja, lo de arriba y lo de abajo
        // no dejan lugar para la tarjeta: todo se desplaza junto, y la
        // tarjeta conserva un alto en el que se lee.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final tight = constraints.maxHeight < 420 * scale.clamp(1, 3);
        if (!tight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?notice,
              header,
              Expanded(child: pages),
              controls,
              review,
            ],
          );
        }
        return SingleChildScrollView(
          key: const Key('deck-viewer-scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?notice,
              header,
              SizedBox(
                height: math.max(360, constraints.maxHeight * 0.75),
                child: pages,
              ),
              controls,
              review,
            ],
          ),
        );
      },
    );
  }
}

/// «3 / 20», la barra de avance y barajar.
class _DeckHeader extends StatelessWidget {
  const _DeckHeader({
    required this.index,
    required this.total,
    required this.accent,
    required this.shuffled,
    required this.onShuffle,
  });

  final int index;
  final int total;
  final Color accent;
  final bool shuffled;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: l10n.f43CardsProgressSemantics(index + 1, total),
                  excludeSemantics: true,
                  child: Text(
                    l10n.f43CardsProgress(index + 1, total),
                    key: const Key('deck-progress'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('deck-shuffle'),
                tooltip: shuffled
                    ? l10n.f43CardsUnshuffle
                    : l10n.f43CardsShuffle,
                isSelected: shuffled,
                onPressed: onShuffle,
                icon: const Icon(Icons.shuffle),
                selectedIcon: Icon(Icons.shuffle_on_outlined, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (index + 1) / total,
                minHeight: 4,
                color: accent,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una tarjeta del mazo, en su página: la de Repasar, que se da vuelta.
class _DeckPage extends StatefulWidget {
  const _DeckPage({
    required this.card,
    required this.number,
    required this.total,
    required this.flipped,
    required this.onFlip,
    required this.picture,
    super.key,
  });

  final DeckCard card;
  final int number;
  final int total;
  final bool flipped;
  final VoidCallback onFlip;
  final Widget? picture;

  @override
  State<_DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<_DeckPage> {
  var _showHint = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final card = widget.card;
    final flipped = widget.flipped;

    Widget label(String text) => Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: scheme.onSurfaceVariant,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );

    final front = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.picture case final picture?) ...[
          picture,
          const SizedBox(height: 16),
        ],
        label(l10n.f43CardsQuestion),
        const SizedBox(height: 10),
        Text(
          card.front,
          key: const Key('deck-card-front'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        if (card.hint.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (_showHint)
            Text(
              l10n.f43CardsHint(card.hint),
              key: const Key('deck-card-hint'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            TextButton.icon(
              key: const Key('deck-show-hint'),
              onPressed: () => setState(() => _showHint = true),
              icon: const Icon(Icons.lightbulb_outline, size: 18),
              label: Text(l10n.f43CardsShowHint),
            ),
        ],
      ],
    );
    final back = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        label(l10n.f43CardsAnswer),
        const SizedBox(height: 10),
        Text(
          card.back,
          key: const Key('deck-card-back'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18),
        ),
      ],
    );

    final side = flipped ? l10n.f43CardsAnswer : l10n.f43CardsQuestion;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - 28),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Semantics(
                button: true,
                label: [
                  l10n.f43CardsCardSemantics(
                    widget.number,
                    widget.total,
                    side,
                    flipped ? card.back : card.front,
                  ),
                  if (!flipped && _showHint) l10n.f43CardsHint(card.hint),
                ].join('. '),
                // Lo de adentro va en la etiqueta: la pista, como acción.
                customSemanticsActions: {
                  if (!flipped && card.hint.isNotEmpty && !_showHint)
                    CustomSemanticsAction(label: l10n.f43CardsShowHint): () =>
                        setState(() => _showHint = true),
                },
                onTap: widget.onFlip,
                onTapHint: l10n.f43CardsFlip,
                excludeSemantics: true,
                child: ReviewFlipCard(
                  key: const Key('deck-card'),
                  showBack: flipped,
                  onTap: widget.onFlip,
                  front: front,
                  back: back,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anterior, dar vuelta y siguiente.
class _DeckControls extends StatelessWidget {
  const _DeckControls({
    required this.canGoBack,
    required this.canGoOn,
    required this.onPrevious,
    required this.onNext,
    required this.onFlip,
  });

  final bool canGoBack;
  final bool canGoOn;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          IconButton.filledTonal(
            key: const Key('deck-previous'),
            tooltip: l10n.f43CardsPrevious,
            onPressed: canGoBack ? onPrevious : null,
            icon: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              key: const Key('deck-flip'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: onFlip,
              icon: const Icon(Icons.flip),
              label: Text(
                l10n.f43CardsFlip,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            key: const Key('deck-next'),
            tooltip: l10n.f43CardsNext,
            onPressed: canGoOn ? onNext : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// «Sumar a mi repaso»: prendido, las tarjetas están en «Para hoy»; apagado,
/// el mazo es solo para hojear.
class _ReviewSwitch extends StatelessWidget {
  const _ReviewSwitch({
    required this.inReview,
    required this.saving,
    required this.onChanged,
  });

  final bool inReview;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            key: const Key('deck-in-review'),
            value: inReview,
            onChanged: saving ? null : onChanged,
            secondary: saving
                ? SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      // Sin animaciones, la rueda queda quieta.
                      value: MediaQuery.disableAnimationsOf(context)
                          ? 0.66
                          : null,
                    ),
                  )
                : Icon(
                    inReview ? Icons.event_available : Icons.event_busy,
                    color: inReview ? scheme.primary : scheme.onSurfaceVariant,
                  ),
            title: Text(l10n.f43CardsInReview),
            subtitle: Text(
              inReview ? l10n.f43CardsInReviewOn : l10n.f43CardsInReviewOff,
            ),
          ),
        ),
      ),
    );
  }
}
