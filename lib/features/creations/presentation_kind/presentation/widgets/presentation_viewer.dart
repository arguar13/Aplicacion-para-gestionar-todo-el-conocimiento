import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/creation_actions.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_design_sheet.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_pager.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/providers/presentation_providers.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/widgets/presentation_fullscreen.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/widgets/presentation_illustration_sheet.dart';
import 'package:sinapsis/features/creations/presentation_kind/presentation/widgets/presentation_options_section.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El contenido de [creation], leído una vez por versión: el visor, la barra
/// y la pantalla completa lo piden muchas veces.
PresentationContent presentationContentOf(StudyCreation creation) {
  final cached = _contents[creation.id];
  if (cached != null && cached.$1 == creation.content) return cached.$2;
  final content = PresentationContent.decode(creation.content);
  _contents[creation.id] = (creation.content, content);
  if (_contents.length > 8) _contents.remove(_contents.keys.first);
  return content;
}

final _contents = <String, (String?, PresentationContent)>{};

/// El visor de una Presentación (F43, punto 5), debajo de la barra común:
///
/// - las diapositivas en su formato, de a una, deslizando con la transición
///   del diseño (de golpe con «sin animaciones»), y en la computadora con
///   las flechas;
/// - lo que no salió de las ilustraciones, con su porqué, y «Completar
///   ilustraciones»;
/// - las notas del presentador, que se muestran u ocultan; volver a dibujar
///   la ilustración de la que se ve, con lo que cuesta primero; el PDF;
/// - la tira de miniaturas.
///
/// La plantilla y el diseño se cambian desde la barra de arriba
/// ([presentationViewerActions]), sin volver a generar (decisión G).
class PresentationViewer extends ConsumerStatefulWidget {
  const PresentationViewer({required this.creation, super.key});

  final StudyCreation creation;

  @override
  ConsumerState<PresentationViewer> createState() => _PresentationViewerState();
}

class _PresentationViewerState extends ConsumerState<PresentationViewer> {
  late final DeckPagerController _pager = ref
      .read(presentationViewerProvider(widget.creation.id).notifier)
      .pager;

  @override
  void initState() {
    super.initState();
    _pager.addListener(_onSlide);
  }

  @override
  void dispose() {
    _pager.removeListener(_onSlide);
    super.dispose();
  }

  void _onSlide() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final creation = widget.creation;
    final content = presentationContentOf(creation);
    final deck = content.deck;
    final state = ref.watch(presentationViewerProvider(creation.id));
    final illustrations = watchDeckIllustrations(ref, content.files);

    if (deck.slides.isEmpty) {
      return Center(
        key: const Key('presentation-unreadable'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.f43PresUnreadable,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final index = _pager.index.clamp(0, deck.slides.length - 1);
    final slide = deck.slides[index];
    final miss = content.missOf(index);
    final ratio = state.design.aspect.ratio;

    return LayoutBuilder(
      builder: (context, constraints) {
        // La diapositiva lo más grande que entre a lo ancho, sin pasar de
        // dos tercios del alto: abajo tienen que verse las miniaturas.
        final scaler = MediaQuery.textScalerOf(context);
        final controls = math.max(56, scaler.scale(20) + 32).toDouble();
        final slideHeight = math.min(
          (constraints.maxWidth - 24) / ratio + 16,
          constraints.maxHeight * 0.66,
        );
        return ListView(
          key: const Key('presentation-viewer'),
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            SizedBox(
              height: slideHeight + controls,
              child: DeckPager(
                key: const Key('presentation-pager'),
                deck: deck,
                design: state.design,
                controller: _pager,
                illustrations: illustrations,
                autofocus: true,
              ),
            ),
            if (miss != null)
              _SlideMissLine(
                text: l10n.f43PresSlideMiss(
                  illustrationReason(
                    l10n,
                    miss.failure,
                    account: content.illustrationAccount,
                  ),
                ),
              ),
            if (content.misses.isNotEmpty)
              _MissesBanner(
                count: content.misses.length,
                reason: l10n.f43PresMissesReason(
                  illustrationReason(
                    l10n,
                    mainFailureOf(content.misses)!,
                    account: content.illustrationAccount,
                  ),
                ),
                onComplete: () => _complete(content),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    key: const Key('presentation-notes-toggle'),
                    avatar: Icon(
                      state.notes
                          ? Icons.speaker_notes_rounded
                          : Icons.speaker_notes_off_outlined,
                      size: 18,
                    ),
                    showCheckmark: false,
                    label: Text(l10n.f43PresNotes),
                    tooltip: state.notes
                        ? l10n.f43PresNotesHide
                        : l10n.f43PresNotesShow,
                    selected: state.notes,
                    shape: const StadiumBorder(),
                    onSelected: (_) => ref
                        .read(presentationViewerProvider(creation.id).notifier)
                        .toggleNotes(),
                  ),
                  if (slide.wantsIllustration)
                    ActionChip(
                      key: const Key('presentation-redraw'),
                      avatar: const Icon(Icons.brush_outlined, size: 18),
                      label: Text(
                        slide.illustrationRef == null
                            ? l10n.f43PresDrawIllustration
                            : l10n.f43PresRedrawIllustration,
                      ),
                      shape: const StadiumBorder(),
                      onPressed: () => _drawOne(content, index, illustrations),
                    ),
                  if (_completable(content, index))
                    ActionChip(
                      key: const Key('presentation-complete'),
                      avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: Text(
                        l10n.f43PresCompleteIllustrations(
                          content.missing.length,
                        ),
                      ),
                      shape: const StadiumBorder(),
                      onPressed: () => _complete(content),
                    ),
                  ActionChip(
                    key: const Key('presentation-pdf'),
                    avatar: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: Text(l10n.f43PresExportPdf),
                    shape: const StadiumBorder(),
                    onPressed: () => unawaited(
                      runCreationAction(
                        context,
                        ref,
                        creation,
                        CreationAction.download,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            DeckThumbnails(
              key: const Key('presentation-thumbnails'),
              deck: deck,
              design: state.design,
              controller: _pager,
              illustrations: illustrations,
            ),
            if (state.notes)
              _NotesCard(
                number: index + 1,
                total: deck.slides.length,
                notes: slide.speakerNotes,
              ),
          ],
        );
      },
    );
  }

  /// «Completar ilustraciones» se ofrece aparte de la de esta diapositiva
  /// solo si falta alguna más.
  bool _completable(PresentationContent content, int index) {
    final missing = content.missing;
    if (missing.isEmpty) return false;
    return !(missing.length == 1 && missing.single == index);
  }

  void _drawOne(
    PresentationContent content,
    int index,
    SlideIllustrationResolver illustrations,
  ) {
    final creation = widget.creation;
    final design = ref.read(presentationViewerProvider(creation.id)).design;
    final slide = content.deck.slides[index];
    unawaited(
      showPresentationIllustrationSheet(
        context,
        creationId: creation.id,
        deck: content.deck,
        design: design,
        slides: [index],
        mode: slide.illustrationRef == null
            ? IllustrationSheetMode.draw
            : IllustrationSheetMode.redraw,
        accountId: PresentationOptions.of(creation.options).imageAccountId,
        illustrations: illustrations,
      ),
    );
  }

  void _complete(PresentationContent content) {
    final creation = widget.creation;
    final design = ref.read(presentationViewerProvider(creation.id)).design;
    unawaited(
      showPresentationIllustrationSheet(
        context,
        creationId: creation.id,
        deck: content.deck,
        design: design,
        slides: content.missing,
        mode: IllustrationSheetMode.complete,
        accountId: PresentationOptions.of(creation.options).imageAccountId,
      ),
    );
  }
}

/// Los botones propios de la Presentación en la barra común del visor: la
/// plantilla y el diseño, y la pantalla completa.
List<Widget> presentationViewerActions(
  BuildContext context,
  StudyCreation creation,
) => [_DesignButton(creation: creation), _FullscreenButton(creation: creation)];

class _DesignButton extends ConsumerWidget {
  const _DesignButton({required this.creation});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final content = presentationContentOf(creation);
    return IconButton(
      key: const Key('presentation-design'),
      tooltip: l10n.f43PresDesign,
      onPressed: content.deck.slides.isEmpty
          ? null
          : () => unawaited(
              showPresentationDesignSheet(context, creation, content),
            ),
      icon: const Icon(Icons.palette_outlined),
    );
  }
}

class _FullscreenButton extends StatelessWidget {
  const _FullscreenButton({required this.creation});

  final StudyCreation creation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final content = presentationContentOf(creation);
    return IconButton(
      key: const Key('presentation-fullscreen-open'),
      tooltip: l10n.f43PresFullscreen,
      onPressed: content.deck.slides.isEmpty
          ? null
          : () => unawaited(
              openPresentationFullscreen(
                context,
                creationId: creation.id,
                deck: content.deck,
                illustrationFiles: content.files,
              ),
            ),
      icon: const Icon(Icons.fullscreen_rounded),
    );
  }
}

/// La hoja de diseño del mazo (`DeckDesignSheet`) con la galería de
/// plantillas: cada cambio se ve en el acto en el visor y se guarda aparte
/// del contenido. Nada le pide algo a la IA.
Future<void> showPresentationDesignSheet(
  BuildContext context,
  StudyCreation creation,
  PresentationContent content,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) => Consumer(
    builder: (context, ref, _) {
      final id = creation.id;
      final state = ref.watch(presentationViewerProvider(id));
      final viewer = ref.read(presentationViewerProvider(id).notifier);
      final illustrations = watchDeckIllustrations(ref, content.files);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: DeckDesignSheet(
          key: const Key('presentation-design-sheet'),
          deck: content.deck,
          design: state.design,
          slideIndex: viewer.pager.index,
          illustrations: illustrations,
          onChanged: viewer.setDesign,
          onChangeTemplate: () => unawaited(
            showTemplateGallerySheet(
              context,
              deck: content.deck,
              design: state.design,
              illustrations: illustrations,
              onChanged: viewer.setDesign,
            ),
          ),
        ),
      );
    },
  ),
);

/// Por qué la ilustración de esta diapositiva no está.
class _SlideMissLine extends StatelessWidget {
  const _SlideMissLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: const Key('presentation-slide-miss'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 18,
            color: scheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Las ilustraciones que no salieron al generarla: cuántas, por qué, y
/// «Completar ilustraciones».
class _MissesBanner extends StatelessWidget {
  const _MissesBanner({
    required this.count,
    required this.reason,
    required this.onComplete,
  });

  final int count;
  final String reason;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        key: const Key('presentation-misses'),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.hide_image_outlined, color: scheme.tertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.f43PresMissesTitle(count),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reason,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.f43PresMissesHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const Key('presentation-misses-complete'),
                onPressed: onComplete,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(l10n.f43PresCompleteTitle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Las notas del presentador de la diapositiva que se ve.
class _NotesCard extends StatelessWidget {
  const _NotesCard({
    required this.number,
    required this.total,
    required this.notes,
  });

  final int number;
  final int total;
  final String notes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = notes.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        key: const Key('presentation-notes'),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.record_voice_over_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.f43DeckPdfNotesTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              l10n.f43DeckPdfSlideOf(number, total),
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              text.isEmpty ? l10n.f43DeckPdfNoNotes : text,
              key: const Key('presentation-notes-text'),
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.5,
                color: text.isEmpty ? scheme.onSurfaceVariant : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
