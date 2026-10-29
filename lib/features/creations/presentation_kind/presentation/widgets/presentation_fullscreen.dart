import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_pager.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/providers/presentation_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre la presentación [creationId] en pantalla completa, apaisada, en la
/// diapositiva que se estaba viendo.
Future<void> openPresentationFullscreen(
  BuildContext context, {
  required String creationId,
  required SlideDeck deck,
  required Set<String> illustrationFiles,
}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => PresentationFullscreen(
      creationId: creationId,
      deck: deck,
      illustrationFiles: illustrationFiles,
    ),
    transitionsBuilder: (context, animation, _, child) =>
        MediaQuery.disableAnimationsOf(context)
        ? child
        : FadeTransition(opacity: animation, child: child),
  ),
);

/// La presentación en pantalla completa (F43, punto 5): apaisada, sin las
/// barras del sistema, las diapositivas sobre negro y los controles que
/// aparecen al tocar —salir, anterior y siguiente, el número y las notas—.
///
/// Mientras está abierta la orientación queda apaisada; al salir vuelve la
/// de la app y las barras del sistema. Comparte con el visor qué diapositiva
/// se ve y si las notas están a la vista.
class PresentationFullscreen extends ConsumerStatefulWidget {
  const PresentationFullscreen({
    required this.creationId,
    required this.deck,
    required this.illustrationFiles,
    super.key,
  });

  final String creationId;
  final SlideDeck deck;
  final Set<String> illustrationFiles;

  /// Las orientaciones mientras está abierta.
  static const orientations = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  @override
  ConsumerState<PresentationFullscreen> createState() =>
      _PresentationFullscreenState();
}

class _PresentationFullscreenState
    extends ConsumerState<PresentationFullscreen> {
  var _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations(
        PresentationFullscreen.orientations,
      ),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleHide();
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    // Vuelve lo de la app: cualquier orientación que ella permita y las
    // barras del sistema.
    unawaited(SystemChrome.setPreferredOrientations(const []));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  /// Los controles se esconden solos al rato, para que se vea solo la
  /// diapositiva; con un lector de pantalla se quedan.
  void _scheduleHide() {
    _hide?.cancel();
    if (MediaQuery.maybeOf(context)?.accessibleNavigation ?? false) return;
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final id = widget.creationId;
    final state = ref.watch(presentationViewerProvider(id));
    final viewer = ref.read(presentationViewerProvider(id).notifier);
    final pager = viewer.pager;
    final illustrations = watchDeckIllustrations(ref, widget.illustrationFiles);
    final slides = widget.deck.slides;
    final still = MediaQuery.disableAnimationsOf(context);
    const scrim = Color(0xB3000000);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        key: const Key('presentation-fullscreen'),
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: state.design.aspect.ratio,
                    child: DeckPager(
                      key: const Key('presentation-fullscreen-pager'),
                      deck: widget.deck,
                      design: state.design,
                      controller: pager,
                      illustrations: illustrations,
                      showControls: false,
                      autofocus: true,
                    ),
                  ),
                ),
              ),
              if (state.notes)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: _controls ? 76 : 16,
                  child: ListenableBuilder(
                    listenable: pager,
                    builder: (context, _) {
                      final index = pager.index.clamp(0, slides.length - 1);
                      final notes = slides[index].speakerNotes.trim();
                      return ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scrim,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                            child: Text(
                              notes.isEmpty ? l10n.f43DeckPdfNoNotes : notes,
                              key: const Key('presentation-fullscreen-notes'),
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              AnimatedOpacity(
                opacity: _controls ? 1 : 0,
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controls,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 12,
                        right: 12,
                        child: SafeArea(
                          child: IconButton.filled(
                            key: const Key('presentation-fullscreen-exit'),
                            tooltip: l10n.f43PresFullscreenExit,
                            style: IconButton.styleFrom(
                              backgroundColor: scrim,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.fullscreen_exit_rounded),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: SafeArea(
                          child: Center(
                            child: _FullscreenBar(
                              pager: pager,
                              total: slides.length,
                              notes: state.notes,
                              onNotes: viewer.toggleNotes,
                              onInteract: _scheduleHide,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Abajo: anterior, «3 / 12», siguiente y las notas.
class _FullscreenBar extends StatelessWidget {
  const _FullscreenBar({
    required this.pager,
    required this.total,
    required this.notes,
    required this.onNotes,
    required this.onInteract,
  });

  final DeckPagerController pager;
  final int total;
  final bool notes;
  final VoidCallback onNotes;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: pager,
      builder: (context, _) {
        final index = pager.index.clamp(0, total - 1);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: IconTheme(
              data: const IconThemeData(color: Colors.white),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('presentation-fullscreen-previous'),
                    tooltip: l10n.f43DeckPrevious,
                    color: Colors.white,
                    onPressed: index > 0
                        ? () {
                            pager.goTo(index - 1);
                            onInteract();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(
                    l10n.f43DeckPageOf(index + 1, total),
                    key: const Key('presentation-fullscreen-counter'),
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: Colors.white),
                  ),
                  IconButton(
                    key: const Key('presentation-fullscreen-next'),
                    tooltip: l10n.f43DeckNext,
                    color: Colors.white,
                    onPressed: index < total - 1
                        ? () {
                            pager.goTo(index + 1);
                            onInteract();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('presentation-fullscreen-notes-toggle'),
                    tooltip: notes
                        ? l10n.f43PresNotesHide
                        : l10n.f43PresNotesShow,
                    isSelected: notes,
                    color: Colors.white,
                    selectedIcon: const Icon(Icons.speaker_notes_rounded),
                    onPressed: () {
                      onNotes();
                      onInteract();
                    },
                    icon: const Icon(Icons.speaker_notes_off_outlined),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
