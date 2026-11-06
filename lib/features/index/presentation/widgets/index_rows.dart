import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/services/index_match.dart';
import 'package:sinapsis/features/index/domain/services/index_outline.dart';
import 'package:sinapsis/features/index/presentation/index_opening.dart';
import 'package:sinapsis/features/index/presentation/providers/index_providers.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_leader_line.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/document_colors.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

// Las filas del Índice (F46), con la tipografía de un índice de libro: el
// tema en versalitas y con su color, el documento en serif y cada capítulo
// con su sangría, su línea guía y los puntos hasta la página.

/// Cuánto se corre cada nivel de capítulo.
const kIndexLevelIndent = 18.0;

/// Dónde empiezan los capítulos de un documento: debajo de su título, después
/// de su ícono.
const kIndexEntryInset = 30.0;

/// El alto mínimo de una fila que se toca: el que pide Material para un
/// dedo.
const kIndexRowMinHeight = 44.0;

/// Cuántos días un documento recién procesado lleva «Nuevo».
const kIndexNewFor = Duration(days: 7);

/// El color de un tema: el mismo siempre —sale de su clave, no del orden—,
/// ajustado al tema de la app para que contraste, como el de cada documento
/// en la línea de tiempo. «Sin tema» no tiene color propio.
Color indexTopicColor(BuildContext context, String? spaceId) {
  final theme = Theme.of(context);
  if (spaceId == null) return theme.colorScheme.onSurfaceVariant;
  final colors = _topicColors[theme] ??= DocumentColors(theme);
  return colors.of(spaceId);
}

final _topicColors = Expando<DocumentColors>('index-topic-colors');

/// El nombre de un tema, con «Sin tema» para el que no lo tiene.
String indexTopicName(AppLocalizations l10n, IndexTopic topic) =>
    topic.isUntopiced ? l10n.f46P3Untopiced : topic.name;

/// El título que se lee de una entrada: el suyo, «Texto completo», o
/// «Imagen 3» para una imagen que la fuente no nombró.
String indexEntryTitle(AppLocalizations l10n, IndexEntry entry) =>
    switch (entry.origin) {
      IndexEntryOrigin.wholeText => l10n.f46P3WholeText,
      IndexEntryOrigin.image when entry.title.isEmpty =>
        l10n.f46P3UntitledImage(entry.position + 1),
      _ => entry.title,
    };

/// Lo que va a la derecha de los puntos (decisión C): la página real del PDF,
/// la del texto procesado o el lugar en la galería. `null` en «Texto
/// completo» y en un marcador que no se pudo ubicar ni tiene página.
String? indexEntryPage(AppLocalizations l10n, IndexEntry entry) {
  if (entry.isWholeText) return null;
  if (entry.isImage) return l10n.f46P3ImagePlace(entry.position + 1);
  if (entry.pdfPage case final page?) return l10n.f46P3PdfPage(page);
  if (entry.textPage case final page?) return l10n.f46P3TextPage(page);
  return null;
}

/// Lo que lee el lector de pantalla en la fila de [entry].
String indexEntrySemantics(
  AppLocalizations l10n,
  IndexEntry entry, {
  String? number,
}) {
  final title = indexEntryTitle(l10n, entry);
  if (entry.isWholeText) return l10n.f46P3SemWholeText;
  if (entry.isImage) return l10n.f46P3SemImage(title, entry.position + 1);
  final page = switch ((entry.pdfPage, entry.textPage)) {
    (final pdf?, _) => l10n.f46P3SemPdfPage(pdf),
    (null, final text?) => l10n.f46P3SemTextPage(text),
    _ => null,
  };
  final chapter = l10n.f46P3SemChapter(
    entry.level,
    number == null ? title : '$number $title',
  );
  return page == null ? chapter : '$chapter, $page';
}

/// [text] con lo buscado resaltado: el comienzo de cada palabra que empieza
/// con una de las de [query].
InlineSpan indexHighlighted(
  BuildContext context,
  String text,
  String query, {
  TextStyle? style,
}) {
  final ranges = query.isEmpty
      ? const <IndexMatchRange>[]
      : indexMatchRanges(text, query);
  if (ranges.isEmpty) return TextSpan(text: text, style: style);
  final colors = Theme.of(context).colorScheme;
  final mark = TextStyle(
    backgroundColor: colors.tertiaryContainer,
    color: colors.onTertiaryContainer,
    fontWeight: FontWeight.w700,
  );
  final spans = <InlineSpan>[];
  var at = 0;
  for (final range in ranges) {
    if (range.start > at) {
      spans.add(TextSpan(text: text.substring(at, range.start)));
    }
    spans.add(
      TextSpan(text: text.substring(range.start, range.end), style: mark),
    );
    at = range.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: spans);
}

/// El ⌄ que pliega y despliega, girado según cómo está.
class IndexFoldChevron extends StatelessWidget {
  const IndexFoldChevron({
    required this.unfolded,
    this.color,
    this.size = 20,
    super.key,
  });

  final bool unfolded;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: unfolded ? 0 : -0.25,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160),
    child: Icon(Icons.expand_more, size: size, color: color),
  );
}

/// Las flechas del teclado sobre una fila que se pliega: → la despliega y ←
/// la pliega, como en el árbol de un explorador de archivos.
class _FoldKeys extends StatelessWidget {
  const _FoldKeys({
    required this.unfolded,
    required this.onToggle,
    required this.child,
  });

  final bool unfolded;
  final VoidCallback? onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final toggle = onToggle;
    if (toggle == null) return child;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (!unfolded) toggle();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (unfolded) toggle();
        },
      },
      child: child,
    );
  }
}

/// Un tema: su color, su nombre en versalitas y cuántos documentos tiene. Se
/// pliega y se despliega con un toque, y queda fijo arriba mientras se
/// recorren sus documentos.
class IndexTopicHeader extends StatelessWidget {
  const IndexTopicHeader({
    required this.topic,
    required this.unfolded,
    required this.onToggle,
    super.key,
  });

  final IndexTopic topic;
  final bool unfolded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = indexTopicColor(context, topic.spaceId);
    final name = indexTopicName(l10n, topic);

    // Una franja apenas teñida con su color, opaca: lo que pasa por debajo
    // mientras está fija no se lee a través.
    return Material(
      color: Color.alphaBlend(
        color.withValues(alpha: 0.07),
        theme.scaffoldBackgroundColor,
      ),
      child: _FoldKeys(
        unfolded: unfolded,
        onToggle: onToggle,
        child: Semantics(
          container: true,
          button: true,
          headingLevel: 2,
          expanded: unfolded,
          label: l10n.f46P3SemTopic(name, topic.documentCount),
          onTap: onToggle,
          excludeSemantics: true,
          child: InkWell(
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kIndexRowMinHeight + 4,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      // Versalitas: las mayúsculas de un tamaño menor, con
                      // aire entre letra y letra, como el encabezado de un
                      // índice impreso.
                      child: Text(
                        name.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IndexCount(
                      count: topic.documentCount,
                      tooltip: l10n.f46P3TopicDocuments(topic.documentCount),
                    ),
                    const SizedBox(width: 4),
                    IndexFoldChevron(
                      unfolded: unfolded,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cuántos documentos tiene un tema o cuántos capítulos un documento: la
/// cifra sola, en una cápsula tenue, para que no se confunda con la página de
/// un capítulo —que va sin cápsula, después de los puntos— y para que entre
/// con la letra al doble. Lo dice entero [tooltip], que también lee el lector
/// de pantalla en la fila.
class IndexCount extends StatelessWidget {
  const IndexCount({required this.count, required this.tooltip, super.key});

  final int count;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$count',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Dónde se muestra un documento: bajo un tema —y entonces dice en qué
/// otros está también— o en una lista sin temas —y dice en cuáles está—.
@immutable
class IndexDocumentPlace {
  const IndexDocumentPlace.underTopic(this.spaceId) : listed = false;
  const IndexDocumentPlace.listed() : spaceId = null, listed = true;

  /// El tema bajo el que está; `null` es «Sin tema». No dice nada si
  /// [listed].
  final String? spaceId;

  /// Si está en una lista sin temas: «Por documento» o la búsqueda.
  final bool listed;

  /// Los temas que nombra su fila.
  List<String> topicsOf(IndexDocument document) =>
      listed ? document.spaceIds : document.alsoIn(spaceId);

  @override
  bool operator ==(Object other) =>
      other is IndexDocumentPlace &&
      other.spaceId == spaceId &&
      other.listed == listed;

  @override
  int get hashCode => Object.hash(spaceId, listed);
}

/// Un documento: su ícono de tipo, el título en serif y, a la derecha,
/// cuántos capítulos tiene. Debajo, en chico, «Nuevo», si todavía se está
/// indexando y en qué otros temas está (decisión D).
///
/// [unfolded] `null` es una fila que no se pliega —la de un documento que
/// coincide con lo buscado—: tocarla hace [onTap] y no muestra ⌄.
class IndexDocumentRow extends ConsumerWidget {
  const IndexDocumentRow({
    required this.document,
    required this.place,
    required this.onTap,
    this.unfolded,
    this.pinned = false,
    this.query = '',
    this.arrivedAt,
    this.showsCount = true,
    super.key,
  });

  final IndexDocument document;
  final IndexDocumentPlace place;
  final VoidCallback onTap;
  final bool? unfolded;

  /// Si es el encabezado fijo de un documento desplegado: con fondo y un
  /// filete abajo, para que lo que pasa por debajo no se lea a través.
  final bool pinned;

  /// Lo buscado, que se resalta en el título.
  final String query;

  /// Cuándo llegó, si fue recién: brilla un momento.
  final DateTime? arrivedAt;

  /// Si dice cuántos capítulos tiene: no, si todavía no se sabe.
  final bool showsCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final names = ref.watch(indexTopicNamesProvider);
    final now = ref.watch(clockProvider)();
    final isNew = now.difference(document.createdAt) < kIndexNewFor;
    final selected = ref.watch(
      indexSelectionProvider.select((s) => s?.documentId == document.id),
    );

    final topics = [
      for (final id in place.topicsOf(document))
        if (names[id] case final name?) name,
    ];
    final topicsLine = topics.isEmpty
        ? null
        : place.listed
        ? l10n.f46P3InTopics(topics.join(', '))
        : l10n.f46P3AlsoIn(topics.join(', '));
    final pending = document.hasText && !document.indexed;
    final byImages = document.chapterCount == 0 && document.imageCount > 0;
    final counted = byImages ? document.imageCount : document.chapterCount;
    final count = byImages
        ? l10n.f46P3DocumentImages(document.imageCount)
        : l10n.f46P3DocumentChapters(document.chapterCount);
    final subtle = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    final semantics = [
      l10n.f46P3SemDocument(document.title),
      document.sourceKind.label(l10n),
      if (showsCount) count,
      if (isNew) l10n.f46P3SemNew,
      if (pending) l10n.f46P3Indexing,
      ?topicsLine,
    ].join(', ');

    final row = Semantics(
      container: true,
      button: true,
      headingLevel: unfolded == null ? null : 3,
      expanded: unfolded,
      selected: selected,
      label: semantics,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kIndexRowMinHeight + 8),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Centrado sobre el ⌄ de sus capítulos de nivel 1.
                SizedBox(
                  width: 2 * (kIndexEntryInset - 16),
                  child: Icon(
                    document.sourceKind.icon,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        indexHighlighted(context, document.title, query),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: ReadingFont.lora.family,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      if (isNew || pending || topicsLine != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (isNew) ...[
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsetsDirectional.only(
                                        end: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: l10n.f46P3New,
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                if (pending) ...[
                                  if (isNew) const TextSpan(text: ' · '),
                                  TextSpan(
                                    text: l10n.f46P3Indexing,
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                                if (topicsLine != null) ...[
                                  if (isNew || pending)
                                    const TextSpan(text: ' · '),
                                  TextSpan(text: topicsLine),
                                ],
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: subtle,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Sin capítulos ni imágenes no hay qué contar: su única
                // entrada es «Texto completo». El lector de pantalla igual
                // oye «sin capítulos».
                if (showsCount && counted > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: IndexCount(count: counted, tooltip: count),
                  ),
                if (unfolded case final unfolded?)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 2),
                    child: IndexFoldChevron(
                      unfolded: unfolded,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // Fijo, con el fondo de la pantalla —opaco, y del mismo tono que los
    // plegados— y un filete abajo que lo separa de sus capítulos.
    final ground = theme.scaffoldBackgroundColor;
    return IndexGlow(
      arrivedAt: arrivedAt,
      child: Material(
        color: selected
            ? Color.alphaBlend(
                colors.secondaryContainer.withValues(alpha: 0.55),
                ground,
              )
            : pinned
            ? ground
            : Colors.transparent,
        shape: pinned
            ? Border(bottom: BorderSide(color: colors.outlineVariant))
            : null,
        child: _FoldKeys(
          unfolded: unfolded ?? true,
          onToggle: unfolded == null ? null : onTap,
          child: row,
        ),
      ),
    );
  }
}

/// Una entrada: un capítulo con su sangría por nivel, su línea guía, su
/// numeración si está prendida y los puntos hasta su página; «Texto
/// completo»; o una imagen con su título y su lugar en la galería.
///
/// Tocarla la abre ([onOpen]); su ⌄, si tiene capítulos adentro, la pliega o
/// la despliega ([onToggle]), y también las flechas ← y → del teclado.
///
/// [matched] es para la búsqueda: `true` en lo que coincide —resaltado—,
/// `false` en un capítulo que se ve porque contiene a una coincidencia, más
/// tenue; `null` en el árbol.
class IndexEntryRow extends ConsumerWidget {
  const IndexEntryRow({
    required this.row,
    required this.onOpen,
    this.onToggle,
    this.matched,
    this.query = '',
    this.arrivedAt,
    super.key,
  });

  final IndexOutlineRow row;
  final VoidCallback onOpen;
  final VoidCallback? onToggle;
  final bool? matched;
  final String query;
  final DateTime? arrivedAt;

  IndexEntry get entry => row.entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = ref.watch(
      indexSelectionProvider.select((s) => s?.entry?.key == entry.key),
    );
    final level = entry.level;
    final title = indexEntryTitle(l10n, entry);
    // Un padre de lo encontrado, en la búsqueda: más tenue.
    final ancestor = !(matched ?? true);

    final base = switch (entry.origin) {
      IndexEntryOrigin.wholeText => theme.textTheme.bodyMedium?.copyWith(
        fontStyle: FontStyle.italic,
      ),
      IndexEntryOrigin.image => theme.textTheme.bodyMedium,
      _ when level == 1 => theme.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      _ => theme.textTheme.bodyMedium?.copyWith(height: 1.3),
    };
    final color = ancestor || level >= 3
        ? colors.onSurfaceVariant
        : colors.onSurface;
    final titleStyle = (base ?? const TextStyle()).copyWith(color: color);
    final pageStyle = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final indent = kIndexEntryInset + (level - 1) * kIndexLevelIndent;
    final toggle = onToggle;

    final content = Row(
      children: [
        // El lugar de ⌄, aunque no lo tenga: los títulos de un mismo nivel
        // empiezan todos en la misma columna.
        SizedBox.square(
          dimension: 28,
          child: row.hasChildren && toggle != null
              ? Tooltip(
                  message: row.unfolded ? l10n.f46P3Fold : l10n.f46P3Unfold,
                  child: InkResponse(
                    key: ValueKey('index-fold-${entry.key}'),
                    onTap: toggle,
                    radius: 18,
                    // El ⌄ no es una parada más del teclado: la fila ya
                    // pliega con ← y →.
                    canRequestFocus: false,
                    child: IndexFoldChevron(
                      unfolded: row.unfolded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : entry.isImage
              ? Icon(
                  Icons.image_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                )
              : null,
        ),
        if (row.number case final number?)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Text(
              number,
              style: titleStyle.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        Expanded(
          child: IndexLeaderLine(
            key: ValueKey('index-entry-title-${entry.key}'),
            title: indexHighlighted(
              context,
              title,
              (matched ?? false) ? query : '',
            ),
            titleStyle: titleStyle,
            page: indexEntryPage(l10n, entry),
            pageStyle: pageStyle,
          ),
        ),
      ],
    );

    return IndexGlow(
      arrivedAt: arrivedAt,
      child: Material(
        color: selected
            ? Color.alphaBlend(
                colors.secondaryContainer.withValues(alpha: 0.7),
                theme.scaffoldBackgroundColor,
              )
            : Colors.transparent,
        child: _FoldKeys(
          unfolded: row.unfolded,
          onToggle: row.hasChildren ? toggle : null,
          child: Semantics(
            container: true,
            button: true,
            selected: selected,
            expanded: row.hasChildren && toggle != null ? row.unfolded : null,
            label: indexEntrySemantics(l10n, entry, number: row.number),
            onTap: onOpen,
            customSemanticsActions: row.hasChildren && toggle != null
                ? {
                    CustomSemanticsAction(
                      label: row.unfolded ? l10n.f46P3Fold : l10n.f46P3Unfold,
                    ): toggle,
                  }
                : null,
            excludeSemantics: true,
            child: InkWell(
              onTap: onOpen,
              child: CustomPaint(
                painter: _LevelGuides(
                  levels: level - 1,
                  color: colors.outlineVariant,
                  textDirection: Directionality.of(context),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: kIndexRowMinHeight,
                  ),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      indent - 14,
                      6,
                      16,
                      6,
                    ),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Las líneas guía de un capítulo: una vertical, fina, por cada nivel que lo
/// contiene, a la altura del ⌄ de ese nivel. Una tras otra, las filas de un
/// mismo padre arman una línea continua que une a los hermanos, y se corta
/// en el padre siguiente.
class _LevelGuides extends CustomPainter {
  const _LevelGuides({
    required this.levels,
    required this.color,
    required this.textDirection,
  });

  /// Cuántos niveles lo contienen.
  final int levels;
  final Color color;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var level = 1; level <= levels; level++) {
      // El centro del ⌄ del nivel [level]: su sangría, menos lo que se
      // corre la fila, más la mitad del lugar del ⌄.
      final x = kIndexEntryInset + (level - 1) * kIndexLevelIndent;
      final dx = textDirection == TextDirection.rtl ? size.width - x : x;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_LevelGuides old) =>
      old.levels != levels ||
      old.color != color ||
      old.textDirection != textDirection;
}

/// Una línea en el lugar de las entradas de un documento desplegado: que se
/// están cargando, que todavía no se leyeron o que no tiene.
class IndexEntriesNote extends StatelessWidget {
  const IndexEntriesNote({required this.text, this.loading = false, super.key});

  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      liveRegion: loading,
      label: text,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          kIndexEntryInset + 12,
          8,
          16,
          12,
        ),
        child: loading
            ? Align(
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              )
            : Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
      ),
    );
  }
}

/// Un brillo suave sobre lo que acaba de llegar (F46: «lo que llega aparece
/// en su lugar, con un brillo suave»), que se apaga solo. Con «sin
/// animaciones», nada.
class IndexGlow extends StatefulWidget {
  const IndexGlow({required this.arrivedAt, required this.child, super.key});

  /// Cuándo llegó; `null` si no es nuevo.
  final DateTime? arrivedAt;
  final Widget child;

  @override
  State<IndexGlow> createState() => _IndexGlowState();
}

class _IndexGlowState extends State<IndexGlow>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    value: 1,
  );

  /// La llegada que ya brilló: cada una, una sola vez.
  DateTime? _shown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeGlow();
  }

  @override
  void didUpdateWidget(IndexGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeGlow();
  }

  void _maybeGlow() {
    final at = widget.arrivedAt;
    if (at == null || at == _shown) return;
    _shown = at;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final strength = 1 - Curves.easeOut.transform(_controller.value);
        if (strength <= 0) return child!;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: glow.withValues(alpha: 0.2 * strength),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
