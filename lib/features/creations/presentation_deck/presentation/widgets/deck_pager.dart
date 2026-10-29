import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Qué diapositiva se ve, compartido entre el visor ([DeckPager]) y la tira
/// de miniaturas (`DeckThumbnails`): tocar una miniatura mueve el visor, y
/// deslizar el visor marca la miniatura.
class DeckPagerController extends ChangeNotifier {
  DeckPagerController({int initialIndex = 0}) : _index = initialIndex;

  int _index;

  int get index => _index;

  /// Pide ir a la diapositiva [index]. El visor la muestra con la
  /// transición elegida (o de golpe, sin animaciones).
  void goTo(int index) {
    if (index == _index || index < 0) return;
    _index = index;
    notifyListeners();
  }
}

/// Las diapositivas de a una, deslizando con la transición del diseño
/// (F43, punto 5): fundido, deslizar, zoom suave o ninguna.
///
/// Con «sin animaciones» del sistema o la transición «Ninguna», el cambio es
/// de golpe —también al deslizar con el dedo: la diapositiva no se arrastra,
/// cambia—. En la computadora se pasa con las flechas, Avanzar y Retroceder
/// página, la barra espaciadora, Inicio y Fin.
class DeckPager extends StatefulWidget {
  const DeckPager({
    required this.deck,
    required this.design,
    this.controller,
    this.illustrations,
    this.onIndexChanged,
    this.showControls = true,
    this.autofocus = false,
    super.key,
  });

  final SlideDeck deck;
  final DeckDesign design;
  final DeckPagerController? controller;
  final SlideIllustrationResolver? illustrations;
  final ValueChanged<int>? onIndexChanged;

  /// Abajo, anterior, «3 / 12» y siguiente.
  final bool showControls;
  final bool autofocus;

  static const Duration duration = Duration(milliseconds: 420);

  @override
  State<DeckPager> createState() => _DeckPagerState();
}

class _DeckPagerState extends State<DeckPager> {
  late DeckPagerController _controller;
  late PageController _pages;
  double _dragDistance = 0;

  int get _count => widget.deck.slides.length;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DeckPagerController();
    _controller.addListener(_onRequested);
    _pages = PageController(initialPage: _controller.index);
  }

  @override
  void didUpdateWidget(DeckPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_onRequested);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? DeckPagerController();
      _controller.addListener(_onRequested);
    }
    if (_controller.index >= _count && _count > 0) {
      _controller.goTo(_count - 1);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onRequested);
    if (widget.controller == null) _controller.dispose();
    _pages.dispose();
    super.dispose();
  }

  bool get _still =>
      MediaQuery.disableAnimationsOf(context) ||
      widget.design.transition == DeckTransition.none;

  /// Alguien (la tira, una tecla, un botón) pidió otra diapositiva.
  void _onRequested() {
    final target = _controller.index.clamp(0, _count == 0 ? 0 : _count - 1);
    widget.onIndexChanged?.call(target);
    if (!mounted) return;
    setState(() {});
    if (!_pages.hasClients) return;
    final current = _pages.page?.round() ?? target;
    if (current == target) return;
    if (_still || (target - current).abs() > 1) {
      // Lejos o sin animaciones: de golpe, sin pasar por las del medio.
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(
        target,
        duration: DeckPager.duration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _go(int delta) {
    if (_count == 0) return;
    _controller.goTo((_controller.index + delta).clamp(0, _count - 1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      _go(1);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _go(-1);
    } else if (key == LogicalKeyboardKey.home) {
      _controller.goTo(0);
    } else if (key == LogicalKeyboardKey.end) {
      _controller.goTo(_count - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _slide(int index) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: SlideView(
      key: ValueKey('deck-pager-slide-$index'),
      slide: widget.deck.slides[index],
      design: widget.design,
      deck: widget.deck,
      index: index,
      illustrations: widget.illustrations,
      borderRadius: BorderRadius.circular(14),
      shadow: true,
    ),
  );

  Widget _animated() => PageView.builder(
    controller: _pages,
    itemCount: _count,
    onPageChanged: (index) {
      if (index != _controller.index) _controller.goTo(index);
    },
    itemBuilder: (context, index) => AnimatedBuilder(
      animation: _pages,
      child: _slide(index),
      builder: (context, child) {
        final page = _pages.hasClients && _pages.position.haveDimensions
            ? _pages.page!
            : _controller.index.toDouble();
        final delta = (index - page).clamp(-1.0, 1.0);
        switch (widget.design.transition) {
          case DeckTransition.slide:
          case DeckTransition.none:
            return child!;
          case DeckTransition.fade:
            // Las dos quedan en su lugar y una se funde en la otra.
            return LayoutBuilder(
              builder: (context, constraints) => Transform.translate(
                offset: Offset(-delta * constraints.maxWidth, 0),
                child: Opacity(opacity: 1 - delta.abs(), child: child),
              ),
            );
          case DeckTransition.zoom:
            return LayoutBuilder(
              builder: (context, constraints) => Transform.translate(
                offset: Offset(-delta * constraints.maxWidth, 0),
                child: Opacity(
                  opacity: 1 - delta.abs(),
                  child: Transform.scale(
                    scale: delta < 0
                        ? 1 + 0.06 * delta.abs()
                        : 1 - 0.08 * delta.abs(),
                    child: child,
                  ),
                ),
              ),
            );
        }
      },
    ),
  );

  /// Sin animaciones: una sola diapositiva, y el gesto de deslizar la cambia.
  Widget _stillViewer() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragStart: (_) => _dragDistance = 0,
    onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
    onHorizontalDragEnd: (details) {
      final velocity = details.primaryVelocity ?? 0;
      if (_dragDistance < -48 || velocity < -300) {
        _go(1);
      } else if (_dragDistance > 48 || velocity > 300) {
        _go(-1);
      }
    },
    child: KeyedSubtree(
      key: ValueKey('deck-pager-still-${_controller.index}'),
      child: _slide(_controller.index.clamp(0, _count - 1)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_count == 0) return const SizedBox.shrink();
    final index = _controller.index.clamp(0, _count - 1);
    final viewer = _still ? _stillViewer() : _animated();
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          Expanded(child: viewer),
          if (widget.showControls)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const Key('deck-pager-previous'),
                    tooltip: l10n.f43DeckPrevious,
                    onPressed: index > 0 ? () => _go(-1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        l10n.f43DeckPageOf(index + 1, _count),
                        key: const Key('deck-pager-counter'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('deck-pager-next'),
                    tooltip: l10n.f43DeckNext,
                    onPressed: index < _count - 1 ? () => _go(1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// La tira de miniaturas de abajo del visor: la que se ve, marcada; tocar
/// otra la muestra.
class DeckThumbnails extends StatefulWidget {
  const DeckThumbnails({
    required this.deck,
    required this.design,
    required this.controller,
    this.illustrations,
    this.height = 76,
    super.key,
  });

  final SlideDeck deck;
  final DeckDesign design;
  final DeckPagerController controller;
  final SlideIllustrationResolver? illustrations;

  /// El alto de cada miniatura (el ancho sale del formato).
  final double height;

  @override
  State<DeckThumbnails> createState() => _DeckThumbnailsState();
}

class _DeckThumbnailsState extends State<DeckThumbnails> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onIndex);
  }

  @override
  void didUpdateWidget(DeckThumbnails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onIndex);
      widget.controller.addListener(_onIndex);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onIndex);
    _scroll.dispose();
    super.dispose();
  }

  double get _itemExtent =>
      widget.height * widget.design.aspect.ratio + _spacing;

  static const _spacing = 10.0;

  /// Que la miniatura de la que se ve quede a la vista.
  void _onIndex() {
    if (!mounted) return;
    setState(() {});
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target =
        (widget.controller.index * _itemExtent -
                (position.viewportDimension - _itemExtent) / 2)
            .clamp(0.0, position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final width = widget.height * widget.design.aspect.ratio;
    return SizedBox(
      height: widget.height + 12,
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemExtent: _itemExtent,
        itemCount: widget.deck.slides.length,
        itemBuilder: (context, index) {
          final selected = index == widget.controller.index;
          final slide = widget.deck.slides[index];
          return Padding(
            padding: const EdgeInsets.only(right: _spacing),
            child: Semantics(
              button: true,
              selected: selected,
              label: l10n.f43DeckThumbnail(index + 1, slide.headline),
              child: GestureDetector(
                key: ValueKey('deck-thumbnail-$index'),
                onTap: () => widget.controller.goTo(index),
                child: Container(
                  width: width,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? scheme.primary : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: SlideView(
                    slide: slide,
                    design: widget.design,
                    deck: widget.deck,
                    index: index,
                    illustrations: widget.illustrations,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
