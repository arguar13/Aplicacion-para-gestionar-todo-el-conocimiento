import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_part_tile.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las palabras clave de un documento procesado, **de las dos formas** que
/// eligió el dueño (F41):
///
/// - **arriba, la lista compacta**: cada palabra una vez, en el orden del
///   texto, y tocarla la abre en su lugar de la fuente;
/// - **plegables, las oraciones**, cada una con su clave marcada en el rosa de
///   estudiar, y editables como cualquier parte.
///
/// Las dos salen de las mismas partes —cada una es una oración con sus
/// palabras adentro (`ProcessedPart.spans`)—, pedidas de a tandas como las
/// demás secciones.
class ProcessedKeywordsView extends ConsumerStatefulWidget {
  const ProcessedKeywordsView({
    required this.documentId,
    required this.count,
    required this.sourceItemId,
    super.key,
  });

  final String documentId;

  /// Cuántas oraciones tiene la sección.
  final int count;

  /// La fuente, para llevar cada palabra a su lugar; `null` si no se puede
  /// abrir.
  final String? sourceItemId;

  /// Cuántas oraciones se piden por tanda.
  static const pageSize = 50;

  @override
  ConsumerState<ProcessedKeywordsView> createState() =>
      _ProcessedKeywordsViewState();
}

class _ProcessedKeywordsViewState extends ConsumerState<ProcessedKeywordsView> {
  var _limit = ProcessedKeywordsView.pageSize;
  List<ProcessedPart>? _shown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final parts = ref.watch(
      processedPartsProvider((
        documentId: widget.documentId,
        section: ProcessedSection.keywords,
        offset: 0,
        limit: _limit,
      )),
    );
    if (parts.valueOrNull case final loaded?) _shown = loaded;
    final list = _shown;
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final remaining = widget.count - list.length;
    final words = compactKeywords(list);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: l10n.processedKeywordsListLabel,
          child: Wrap(
            key: const Key('processed-keywords-compact'),
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final word in words)
                _KeywordChip(word: word, sourceItemId: widget.sourceItemId),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          key: const Key('processed-keywords-sentences'),
          expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
              ? AnimationStyle.noAnimation
              : null,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          title: Text(l10n.processedKeywordsSentences(widget.count)),
          children: [
            for (final (index, part) in list.indexed) ...[
              if (index > 0) const Divider(height: 1),
              ProcessedPartTile(
                key: ValueKey(part.id),
                part: part,
                sourceItemId: widget.sourceItemId,
              ),
            ],
            if (remaining > 0 && list.length >= _limit)
              Align(
                child: TextButton(
                  onPressed: () =>
                      setState(() => _limit += ProcessedKeywordsView.pageSize),
                  child: Text(l10n.libraryLoadMore),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Una palabra clave de la lista compacta, con dónde está en la fuente si se
/// sabe: la primera vez que aparece.
typedef CompactKeyword = ({String word, ProcessedAnchor? place});

/// Las palabras clave de [parts], cada una una vez —sin distinguir mayúsculas:
/// «Roma» y «roma» son la misma—, en el orden del texto, y
/// dónde está la primera. Una oración que se editó ya no sabe dónde estaba en
/// la fuente: su palabra se ve, sin lugar al que llevar.
List<CompactKeyword> compactKeywords(List<ProcessedPart> parts) {
  final seen = <String>{};
  final words = <CompactKeyword>[];
  for (final part in parts) {
    final anchor = part.anchor;
    for (final span in keywordSpansOf(part)) {
      final word = part.content.substring(span.start, span.end);
      if (!seen.add(word.toLowerCase())) continue;
      words.add((
        word: word,
        place: anchor == null || !part.isVerbatim
            ? null
            : ProcessedAnchor(
                renditionId: anchor.renditionId,
                start: anchor.start + span.start,
                end: anchor.start + span.end,
              ),
      ));
    }
  }
  return words;
}

/// Los tramos de las palabras clave de [part] que caen dentro de su texto:
/// una oración editada más corta no puede marcar fuera de sí.
List<ProcessedSpan> keywordSpansOf(ProcessedPart part) => [
  for (final span in part.spans)
    if (span.start >= 0 &&
        span.end <= part.content.length &&
        span.start < span.end)
      span,
];

/// Las palabras clave de [part] como capas, en el rosa de estudiar y en
/// negrita, como en el texto de la fuente.
List<PaintedRange> keywordPaintsOf(ProcessedPart part, StudyPalette palette) =>
    [
      for (final span in keywordSpansOf(part))
        PaintedRange(
          span.start,
          span.end,
          background: palette.keyword,
          foreground: StudyPalette.ink,
          bold: true,
          aboveHighlights: true,
        ),
    ];

class _KeywordChip extends StatelessWidget {
  const _KeywordChip({required this.word, required this.sourceItemId});

  final CompactKeyword word;
  final String? sourceItemId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = StudyPalette.of(Theme.of(context).brightness);
    final place = word.place;
    final sourceId = sourceItemId;
    final open = place == null || sourceId == null
        ? null
        : () => context.push(
            RoutePaths.reading(sourceId, start: place.start, end: place.end),
          );

    final chip = ActionChip(
      label: Text(word.word),
      labelStyle: const TextStyle(
        color: StudyPalette.ink,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: palette.keyword,
      side: BorderSide.none,
      onPressed: open,
      disabledColor: palette.keyword,
    );
    return open == null
        ? chip
        : Tooltip(message: l10n.processedKeywordOpen(word.word), child: chip);
  }
}
