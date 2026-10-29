import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/reading_scroll_physics.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/domain/extract_text.dart';
import 'package:sinapsis/features/creations/extract/presentation/extract_marking.dart';
import 'package:sinapsis/features/creations/extract/presentation/providers/extract_providers.dart';
import 'package:sinapsis/features/creations/extract/presentation/widgets/extract_listen_player.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_dock.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_follow.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_bar.dart';
import 'package:sinapsis/features/study/presentation/providers/study_keywords_fill_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_document_card.dart';
import 'package:sinapsis/features/viewer/presentation/providers/reader_font_scale_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El visor de **Extraer texto completo**, **Extraer resumen** y **Extraer
/// síntesis** (F43, paso 7; punto 5 del plan; M8).
///
/// **Una vista viva, nunca una copia (decisión E).** Lo que se lee sale, cada
/// vez, del texto propio de cada documento procesado y de sus marcas de
/// estudiar —las del original (M5), con la clave `procesado:…`—: si se marca
/// algo en el original, si se edita una página, si se ocultan las palabras
/// clave allá, acá cambia solo. Con varios documentos van en el orden de la
/// creación, cada uno con su título arriba.
///
/// - **La lectura**: el texto limpio, con la letra del lector de libros
///   («Leer como libro», F35) y su tamaño, y las palabras clave en rosa en
///   todas las oraciones (decisión 85) si se resaltan —la preferencia de cada
///   documento, la misma que en el original—.
/// - **Lo que falta**: un documento sin resumen, sin síntesis o —en el texto
///   completo— sin palabras clave lo dice, y ofrece marcarlo con la IA en el
///   documento mismo (`markExtractWithAi`, la máquina de M5); mientras se
///   marca, la franja de siempre con su avance, y lo marcado aparece a medida
///   que llega.
/// - **El modo escuchar** (decisión 86): el reproductor grande de abajo
///   ([ExtractListenPlayer]), el amarillo en vivo sobre lo que suena —con el
///   rosa siempre encima— y la lista que acompaña sola. Si la persona se mueve
///   a mano la deja tranquila y ofrece «Volver a la lectura»; sin animaciones,
///   salta en vez de deslizarse.
///
/// Un libro entero son miles de bloques: la lista arma solo los que se ven, y
/// lo que suena reconstruye solo el bloque donde está.
class ExtractViewer extends ConsumerStatefulWidget {
  const ExtractViewer({required this.creation, super.key});

  final StudyCreation creation;

  @override
  ConsumerState<ExtractViewer> createState() => _ExtractViewerState();
}

/// Una fila de la lista del visor.
sealed class _Row {
  const _Row();
}

/// «A 2 documentos les falta el resumen», con «Marcar los 2 con IA».
final class _BannerRow extends _Row {
  const _BannerRow(this.missing);

  final List<ExtractSection> missing;
}

/// El título de un documento, arriba de su apartado.
final class _HeaderRow extends _Row {
  const _HeaderRow(this.section, {required this.last});

  final int section;
  final bool last;
}

/// Lo que hay que decir de un documento: que falta algo, que se está
/// marcando, que se borró.
final class _NoticeRow extends _Row {
  const _NoticeRow(this.section, {required this.last});

  final int section;
  final bool last;
}

/// Un bloque del texto de un documento.
final class _BlockRow extends _Row {
  const _BlockRow(this.section, this.block, {required this.last});

  final int section;
  final int block;
  final bool last;
}

/// Lo que se puede llevar a la vista mientras suena: un título, un bloque.
abstract interface class _Revealable {
  /// Lo que se dibuja, o `null` si todavía no se armó.
  RenderBox? get revealBox;

  /// Dónde está [segment] dentro de [revealBox].
  Rect revealRect(ReadableSegment segment);
}

class _ExtractViewerState extends ConsumerState<ExtractViewer> {
  final _scroll = ScrollController();

  /// Si la lista sigue la lectura o la persona se fue a otro lado.
  final _follow = ReadAloudFollow();

  /// Las filas armadas ahora, por su número: las únicas que se pueden medir.
  final _built = <int, _Revealable>{};

  List<_Row> _rows = const [];
  List<ExtractSection> _sections = const [];

  /// La fila del título y la del primer bloque de cada documento.
  final _headerRow = <int>[];
  final _firstBlockRow = <int>[];

  /// De qué documento es cada clave de texto.
  final _sectionOfKey = <String, int>{};

  /// Los textos ya completados con sus palabras clave en esta pantalla.
  final _filled = <String>{};

  ReadableDocument? _document;
  List<ReadableSegment>? _documentSegments;

  String get _readableId => extractReadableId(widget.creation.id);

  @override
  void initState() {
    super.initState();
    _follow.addListener(_onFollowChanged);
    ref.listenManual(
      readAloudControllerProvider.select(
        (s) => s.document?.id == _readableId && s.panel != ReadAloudPanel.hidden
            ? s.currentSegment
            : null,
      ),
      (previous, next) => _revealSoon(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _follow
      ..removeListener(_onFollowChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Lo que se escucha de esta extracción: el mismo objeto mientras no
  /// cambien sus pedazos.
  ReadableDocument? _readable(
    AppLocalizations l10n,
    List<ReadableSegment>? segments,
  ) {
    if (segments == null) return null;
    final cached = _document;
    if (cached != null && identical(_documentSegments, segments)) return cached;
    _documentSegments = segments;
    return _document = ReadableDocument(
      id: _readableId,
      title: studyCreationTitle(l10n, widget.creation),
      segments: segments,
    );
  }

  void _onFollowChanged() {
    if (!_follow.following) return;
    _revealSoon(_reading());
  }

  ReadableSegment? _reading() {
    final state = ref.read(readAloudControllerProvider);
    if (state.document?.id != _readableId ||
        state.panel == ReadAloudPanel.hidden) {
      return null;
    }
    return state.currentSegment;
  }

  void _revealSoon(ReadableSegment? segment) {
    if (segment == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(segment);
    });
  }

  /// La fila donde está [segment], o `null` si no es de acá.
  int? _rowOf(ReadableSegment segment) {
    final key = segment.sourceKey;
    for (var i = 0; i < _sections.length; i++) {
      if (key == extractTitleKey(_sections[i].documentId)) {
        return _headerRow[i];
      }
    }
    final section = _sectionOfKey[key];
    if (section == null) return null;
    final blocks = _sections[section].blocks;
    if (blocks.isEmpty) return null;
    // El primer bloque que termina después de donde empieza lo que suena.
    var low = 0;
    var high = blocks.length - 1;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (blocks[middle].end <= segment.start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return _firstBlockRow[section] + low;
  }

  /// Lleva lo que suena a la franja cómoda de la vista (`ReadAloudBand`), si
  /// la lista sigue la lectura y no está ya ahí. Si su fila todavía no se
  /// armó —está lejos—, salta a donde se calcula que está y vuelve a mirar
  /// en el cuadro siguiente, ya con ella armada.
  void _reveal(ReadableSegment segment, {int attempt = 0}) {
    if (!mounted || !_scroll.hasClients) return;
    final row = _rowOf(segment);
    if (row == null) return;
    final position = _scroll.position;
    final target = _built[row];
    final box = target?.revealBox;
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    if (target == null || box == null || viewport == null) {
      if (attempt >= 8 || !_follow.shouldMoveTo(comfortable: false)) return;
      position.jumpTo(
        _estimatedOffset(
          row,
        ).clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal(segment, attempt: attempt + 1);
      });
      return;
    }
    final line = target.revealRect(segment);
    final atTop = viewport.getOffsetToReveal(box, 0, rect: line).offset;
    final extent = position.viewportDimension;
    final view = Rect.fromLTWH(0, position.pixels, 1, extent);
    final shown = Rect.fromLTWH(0, atTop, 1, line.height);
    final comfortable = ReadAloudBand.contains(view, shown);
    if (!_follow.shouldMoveTo(comfortable: comfortable)) return;
    final destination = (atTop - extent * ReadAloudBand.landing).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((destination - position.pixels).abs() < 1) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(destination);
    } else {
      unawaited(
        position.animateTo(
          destination,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  /// Dónde se calcula que empieza la fila [row]: desde la fila armada más
  /// cercana, con el alto promedio de las filas.
  double _estimatedOffset(int row) {
    final position = _scroll.position;
    final average =
        (position.maxScrollExtent + position.viewportDimension) /
        math.max(1, _rows.length);
    int? nearest;
    double? nearestOffset;
    for (final entry in _built.entries) {
      final box = entry.value.revealBox;
      final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
      if (box == null || viewport == null) continue;
      if (nearest == null || (entry.key - row).abs() < (nearest - row).abs()) {
        nearest = entry.key;
        nearestOffset = viewport.getOffsetToReveal(box, 0).offset;
      }
    }
    if (nearest == null || nearestOffset == null) return row * average;
    return nearestOffset + (row - nearest) * average;
  }

  void _register(int row, _Revealable target) => _built[row] = target;

  void _unregister(int row, _Revealable target) {
    if (identical(_built[row], target)) _built.remove(row);
  }

  /// Arma las filas de [sections]: el aviso de arriba si a varios les falta
  /// lo mismo, y por cada documento su título, su aviso y sus bloques.
  void _layout(List<ExtractSection> sections) {
    _sections = sections;
    _headerRow.clear();
    _firstBlockRow.clear();
    _sectionOfKey.clear();
    final rows = <_Row>[];
    final missing = [
      for (final section in sections)
        if (section.status == ExtractSectionStatus.ready &&
            section.missing &&
            !_analyzing(section))
          section,
    ];
    if (missing.length > 1) rows.add(_BannerRow(missing));
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final key = section.sourceKey;
      if (key != null) _sectionOfKey[key] = i;
      final blocks = section.status == ExtractSectionStatus.ready
          ? section.blocks
          : const <ExtractBlock>[];
      _headerRow.add(rows.length);
      rows
        ..add(_HeaderRow(i, last: false))
        ..add(_NoticeRow(i, last: blocks.isEmpty));
      _firstBlockRow.add(rows.length);
      for (var b = 0; b < blocks.length; b++) {
        rows.add(_BlockRow(i, b, last: b == blocks.length - 1));
      }
    }
    _rows = rows;
  }

  bool _analyzing(ExtractSection section) {
    final key = section.sourceKey;
    return key != null &&
        ref.watch(studyAnalysisProvider(key)) is StudyAnalysisRunning;
  }

  /// Lo analizado antes de que cada oración llevara sus palabras clave se
  /// completa al mostrarlas (decisión 85), como en el original: una vez por
  /// texto, sin IA.
  void _fillKeywords(ExtractSection section) {
    final own = section.own;
    if (own == null || !section.keywordsShown || !section.study.started) {
      return;
    }
    if (!_filled.add('${own.key}:${own.content.length}')) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ensureStudyKeywords(ref, own.asStudyText));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final creation = widget.creation;
    final sections = [
      for (final id in creation.sourceIds)
        ref.watch(
          extractSectionProvider((kind: creation.kind, documentId: id)),
        ),
    ];
    for (final section in sections) {
      if (section.status == ExtractSectionStatus.ready) _fillKeywords(section);
    }
    _layout(sections);

    final document = _readable(
      l10n,
      ref.watch(extractSegmentsProvider(creation.id)),
    );
    // Lo que cambia mientras se escucha —se marcó algo, se editó— se le pasa
    // al lector: sigue donde iba, con lo nuevo.
    ref.listen(extractSegmentsProvider(creation.id), (previous, next) {
      final controller = ref.read(readAloudControllerProvider.notifier);
      if (ref.read(readAloudControllerProvider).document?.id != _readableId) {
        return;
      }
      final updated = _readable(l10n, next);
      if (updated == null) return;
      unawaited(
        updated.isEmpty ? controller.close() : controller.open(updated),
      );
    });
    _follow.resumeOnNewReadings(ref);
    final (listening, readingKey) = ref.watch(
      readAloudControllerProvider.select(
        (s) => s.document?.id == _readableId && s.panel != ReadAloudPanel.hidden
            ? (true, s.currentSegment?.sourceKey)
            : (false, null),
      ),
    );
    final spec = ref.watch(creationKindRegistryProvider).of(creation.kind);
    final accent = spec.accent.of(context);

    final list = NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.direction != ScrollDirection.idle &&
            listening) {
          _follow.release();
        }
        return false;
      },
      child: SelectionArea(
        child: ListView.builder(
          key: const Key('extract-viewer-list'),
          controller: _scroll,
          physics: const ReadingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
          itemCount: _rows.length,
          itemBuilder: (context, index) => _buildRow(context, index, accent),
        ),
      ),
    );

    return ReadAloudDock(
      documentId: _readableId,
      child: Column(
        key: Key('extract-viewer-${creation.kind.storageKey}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: list),
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ReadAloudBackToReading(
                      sourceKey: readingKey ?? _readableId,
                      follow: _follow,
                      onPressed: _follow.resume,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (listening && document != null)
            ExtractListenPlayer(
              accent: accent,
              titleOf: (key) {
                for (final section in _sections) {
                  if (key == section.sourceKey ||
                      key == extractTitleKey(section.documentId)) {
                    return section.title;
                  }
                }
                return document.title;
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, int index, Color accent) {
    final row = _rows[index];
    final kind = widget.creation.kind;
    final child = switch (row) {
      _BannerRow(:final missing) => _MissingBanner(
        kind: kind,
        sections: missing,
      ),
      _HeaderRow(:final section) => _SectionHeader(
        key: ValueKey('extract-header-${_sections[section].documentId}'),
        row: index,
        kind: kind,
        section: _sections[section],
        accent: accent,
        onBuilt: _register,
        onGone: _unregister,
      ),
      _NoticeRow(:final section) => _SectionNotice(
        kind: kind,
        section: _sections[section],
      ),
      _BlockRow(:final section, :final block) => _BlockView(
        key: ValueKey(
          'extract-block-${_sections[section].documentId}-'
          '${_sections[section].blocks[block].start}',
        ),
        row: index,
        section: _sections[section],
        block: _sections[section].blocks[block],
        onBuilt: _register,
        onGone: _unregister,
      ),
    };
    final (first, last) = switch (row) {
      _BannerRow() => (true, true),
      _HeaderRow(:final last) => (true, last),
      _NoticeRow(:final last) => (false, last),
      _BlockRow(:final last) => (false, last),
    };
    return _Paper(first: first, last: last, child: child);
  }
}

/// La hoja de papel de cada documento: un fondo apenas más claro que la
/// pantalla, de punta a punta de su apartado, con las esquinas muy redondas
/// arriba y abajo (como las tarjetas de NotebookLM). Cada fila pone su
/// pedazo; juntas se ven una sola hoja.
class _Paper extends StatelessWidget {
  const _Paper({required this.first, required this.last, required this.child});

  final bool first;
  final bool last;
  final Widget child;

  static const _radius = Radius.circular(28);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 480;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            narrow ? 10 : 16,
            0,
            narrow ? 10 : 16,
            last ? 16 : 0,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.vertical(
                top: first ? _radius : Radius.zero,
                bottom: last ? _radius : Radius.zero,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                narrow ? 18 : 28,
                first ? 22 : 0,
                narrow ? 18 : 28,
                last ? 24 : 0,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// El título de un documento: qué se extrae, en el color del tipo, el título
/// con la letra de libro y cuánto tiene. Mientras se dice —con varios
/// documentos, cada apartado empieza por su título—, en amarillo.
class _SectionHeader extends ConsumerStatefulWidget {
  const _SectionHeader({
    required this.row,
    required this.kind,
    required this.section,
    required this.accent,
    required this.onBuilt,
    required this.onGone,
    super.key,
  });

  final int row;
  final StudyCreationKind kind;
  final ExtractSection section;
  final Color accent;
  final void Function(int row, _Revealable target) onBuilt;
  final void Function(int row, _Revealable target) onGone;

  @override
  ConsumerState<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends ConsumerState<_SectionHeader>
    implements _Revealable {
  final _box = GlobalKey();

  @override
  RenderBox? get revealBox =>
      _box.currentContext?.findRenderObject() as RenderBox?;

  @override
  Rect revealRect(ReadableSegment segment) =>
      Offset.zero & (revealBox?.size ?? Size.zero);

  @override
  void initState() {
    super.initState();
    widget.onBuilt(widget.row, this);
  }

  @override
  void didUpdateWidget(_SectionHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row != widget.row) {
      widget
        ..onGone(oldWidget.row, this)
        ..onBuilt(widget.row, this);
    }
  }

  @override
  void dispose() {
    widget.onGone(widget.row, this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final section = widget.section;
    final reading =
        ref.watch(
          readAloudHighlightProvider(extractTitleKey(section.documentId)),
        ) !=
        null;
    final kicker = switch (widget.kind) {
      StudyCreationKind.fullText => l10n.f43TextKickerFullText,
      StudyCreationKind.summary => l10n.f43TextKickerSummary,
      _ => l10n.f43TextKickerSynthesis,
    };
    final needs = extractNeeds(widget.kind);
    final count = section.status == ExtractSectionStatus.ready
        ? originalStudyCount(l10n, needs, section.study.of(needs).length)
        : null;
    final title = section.status == ExtractSectionStatus.deleted
        ? l10n.f43StudioSourceDeleted
        : section.title.trim().isEmpty
        ? l10n.f43TextUntitled
        : section.title;
    final titleStyle = CreationFontPair.book.displayStyle(
      size: 24,
      color: reading ? StudyPalette.ink : scheme.onSurface,
    );
    return Column(
      key: _box,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count == null
              ? kicker.toUpperCase()
              : '${kicker.toUpperCase()} · $count',
          style: theme.textTheme.labelMedium?.copyWith(
            color: widget.accent,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          header: true,
          child: Text.rich(
            TextSpan(
              text: title,
              style: titleStyle.copyWith(
                backgroundColor: reading ? RenderedMarkdown.playingColor : null,
              ),
            ),
            key: Key('extract-title-${section.documentId}'),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// Un bloque del texto: los tramos de un párrafo con su formato, las palabras
/// clave en rosa y lo que suena en amarillo —con el rosa encima—.
class _BlockView extends ConsumerStatefulWidget {
  const _BlockView({
    required this.row,
    required this.section,
    required this.block,
    required this.onBuilt,
    required this.onGone,
    super.key,
  });

  final int row;
  final ExtractSection section;
  final ExtractBlock block;
  final void Function(int row, _Revealable target) onBuilt;
  final void Function(int row, _Revealable target) onGone;

  @override
  ConsumerState<_BlockView> createState() => _BlockViewState();
}

class _BlockViewState extends ConsumerState<_BlockView> implements _Revealable {
  final _text = GlobalKey();

  /// De la última vez que se armó: dónde empieza cada tramo en el texto que
  /// se ve, y su formato.
  List<int> _renderStarts = const [];
  List<RenderedMarkdown> _rendered = const [];

  @override
  RenderBox? get revealBox =>
      _text.currentContext?.findRenderObject() as RenderBox?;

  @override
  Rect revealRect(ReadableSegment segment) {
    final box = revealBox;
    if (box is! RenderParagraph) return Offset.zero & (box?.size ?? Size.zero);
    final block = widget.block;
    final start = math.max(segment.start, block.start);
    final end = math.min(segment.end, block.end);
    if (end <= start) return Offset.zero & box.size;
    final boxes = box.getBoxesForSelection(
      TextSelection(baseOffset: _toRender(start), extentOffset: _toRender(end)),
    );
    if (boxes.isEmpty) return Offset.zero & box.size;
    var line = boxes.first.toRect();
    for (final other in boxes.skip(1)) {
      line = line.expandToInclude(other.toRect());
    }
    return line;
  }

  /// Dónde se ve la posición [offset] del texto propio.
  int _toRender(int offset) {
    final pieces = widget.block.pieces;
    var index = 0;
    while (index < pieces.length - 1 && pieces[index + 1].start <= offset) {
      index++;
    }
    if (index >= _rendered.length) return 0;
    final piece = pieces[index];
    final within = (offset - piece.start).clamp(0, piece.end - piece.start);
    return _renderStarts[index] + _rendered[index].rawToRender(within);
  }

  @override
  void initState() {
    super.initState();
    widget.onBuilt(widget.row, this);
  }

  @override
  void didUpdateWidget(_BlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row != widget.row) {
      widget
        ..onGone(oldWidget.row, this)
        ..onBuilt(widget.row, this);
    }
  }

  @override
  void dispose() {
    widget.onGone(widget.row, this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = widget.section;
    final block = widget.block;
    final own = section.own!;
    final content = own.content;
    final reading = ref.watch(
      readAloudSpanProvider((
        sourceKey: own.key,
        from: block.start,
        to: block.end,
      )),
    );
    final scale = ref.watch(readerFontScaleNotifierProvider);
    final palette = StudyPalette.of(theme.brightness);
    final keywords = keywordsWithin(
      section.paintedKeywords,
      block.start,
      block.end,
    );
    final baseSize = theme.textTheme.bodyLarge?.fontSize ?? 16;
    final base = theme.textTheme.bodyLarge?.copyWith(
      height: 1.65,
      fontSize: baseSize * 1.06 * scale,
      color: theme.colorScheme.onSurface,
    );

    final starts = <int>[];
    final rendered = <RenderedMarkdown>[];
    final children = <InlineSpan>[];
    var at = 0;
    for (var i = 0; i < block.pieces.length; i++) {
      final piece = block.pieces[i];
      if (i > 0) {
        children.add(const TextSpan(text: ' '));
        at += 1;
      }
      final raw = content.substring(piece.start, piece.end);
      final markdown = own.markdown
          ? RenderedMarkdown.parse(raw)
          : RenderedMarkdown.plain(raw);
      // De abajo hacia arriba: lo que suena y, encima, las palabras clave
      // —el rosa siempre encima del amarillo—.
      final paints = <PaintedRange>[
        if (reading case (final from, final to))
          if (_clip(block.start + from, block.start + to, piece) case (
            final s,
            final e,
          ))
            PaintedRange(
              s,
              e,
              background: RenderedMarkdown.playingColor,
              foreground: StudyPalette.ink,
              aboveHighlights: true,
            ),
        for (final mark in keywords)
          if (_clip(mark.start, mark.end, piece) case (final s, final e))
            PaintedRange(
              s,
              e,
              background: palette.keyword,
              foreground: StudyPalette.ink,
              bold: true,
              aboveHighlights: true,
            ),
      ];
      children.add(
        markdown.buildSpans(theme, const [], baseStyle: base, paints: paints),
      );
      starts.add(at);
      rendered.add(markdown);
      at += markdown.displayText.length;
    }
    _renderStarts = starts;
    _rendered = rendered;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text.rich(
        TextSpan(style: base, children: children),
        key: _text,
      ),
    );
  }

  /// `[start, end)` recortado a [piece] y contado desde su comienzo, o
  /// `null` si no lo toca.
  static (int, int)? _clip(int start, int end, ExtractPiece piece) {
    final s = math.max(start, piece.start);
    final e = math.min(end, piece.end);
    return e > s ? (s - piece.start, e - piece.start) : null;
  }
}

/// Lo que hay que decir de un documento, debajo de su título: que se borró,
/// que no tiene texto, que todavía se lee, que se está marcando —con su
/// avance y «Parar»—, o que le falta lo que esta extracción muestra, con
/// «Marcar con IA» y «Abrir el documento».
class _SectionNotice extends ConsumerWidget {
  const _SectionNotice({required this.kind, required this.section});

  final StudyCreationKind kind;
  final ExtractSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final own = section.own;
    switch (section.status) {
      case ExtractSectionStatus.loading:
        return _NoticeLine(
          key: Key('extract-loading-${section.documentId}'),
          icon: Icons.hourglass_empty_rounded,
          text: l10n.f43TextLoading,
        );
      case ExtractSectionStatus.deleted:
        return _NoticeLine(
          key: Key('extract-deleted-${section.documentId}'),
          icon: Icons.link_off_rounded,
          text: l10n.f43TextDeletedHint,
        );
      case ExtractSectionStatus.noText:
        return _NoticeLine(
          key: Key('extract-no-text-${section.documentId}'),
          icon: Icons.notes_rounded,
          text: l10n.f43TextNoText,
        );
      case ExtractSectionStatus.ready:
        break;
    }
    final analysis = ref.watch(studyAnalysisProvider(own!.key));
    if (analysis is! StudyAnalysisIdle) {
      // La franja de siempre: la parte que va y «Parar»; si se cortó,
      // «Reintentar». Lo marcado aparece arriba a medida que llega.
      return Padding(
        key: Key('extract-progress-${section.documentId}'),
        padding: const EdgeInsets.only(bottom: 16),
        child: StudyProgressStrip(text: own.asStudyText),
      );
    }
    if (!section.missing) return const SizedBox.shrink();
    return _MissingCard(kind: kind, section: section);
  }
}

/// Una línea tenue con su ícono.
class _NoticeLine extends StatelessWidget {
  const _NoticeLine({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Todavía no tiene resumen»: qué falta, que se marca en el documento mismo
/// —con la IA o a mano— y los dos caminos.
class _MissingCard extends ConsumerWidget {
  const _MissingCard({required this.kind, required this.section});

  final StudyCreationKind kind;
  final ExtractSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final needs = extractNeeds(kind);
    final color = originalStudyColor(StudyPalette.of(theme.brightness), needs);
    final title = switch (needs) {
      StudyMarkKind.summary => l10n.f43TextMissingSummary,
      StudyMarkKind.synthesis => l10n.f43TextMissingSynthesis,
      StudyMarkKind.keyword => l10n.f43TextMissingKeywords,
    };
    return Container(
      key: Key('extract-missing-${section.documentId}'),
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(
                  originalStudyIcon(needs),
                  size: 20,
                  color: StudyPalette.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.f43TextMissingBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: Key('extract-mark-${section.documentId}'),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(l10n.f43TextMarkWithAi),
                onPressed: () =>
                    unawaited(_mark(context, ref, kind, [section])),
              ),
              OutlinedButton.icon(
                key: Key('extract-open-${section.documentId}'),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(l10n.f43TextOpenDocument),
                onPressed: () => unawaited(
                  context.push(
                    RoutePaths.processedDocument(section.documentId),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// «A 2 documentos les falta el resumen», arriba de todo, con «Marcar los 2
/// con IA»: uno por uno, en orden.
class _MissingBanner extends ConsumerWidget {
  const _MissingBanner({required this.kind, required this.sections});

  final StudyCreationKind kind;
  final List<ExtractSection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final needs = extractNeeds(kind);
    final count = sections.length;
    final text = switch (needs) {
      StudyMarkKind.summary => l10n.f43TextMissingSeveralSummary(count),
      StudyMarkKind.synthesis => l10n.f43TextMissingSeveralSynthesis(count),
      StudyMarkKind.keyword => l10n.f43TextMissingSeveralKeywords(count),
    };
    return Column(
      key: const Key('extract-missing-banner'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              originalStudyIcon(needs),
              color: originalStudyColor(
                StudyPalette.of(theme.brightness),
                needs,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: theme.textTheme.titleMedium)),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('extract-mark-all'),
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: Text(l10n.f43TextMarkAll(count)),
          onPressed: () => unawaited(_mark(context, ref, kind, sections)),
        ),
      ],
    );
  }
}

/// Pregunta con «Con tu IA actual» y, si se confirma, marca [sections] con la
/// IA en el documento mismo (M8): lo que necesita la extracción de [kind].
Future<void> _mark(
  BuildContext context,
  WidgetRef ref,
  StudyCreationKind kind,
  List<ExtractSection> sections,
) async {
  final needs = extractNeeds(kind);
  final confirmed = await showExtractMarkSheet(
    context,
    kind: needs,
    sections: sections,
  );
  if (!confirmed || !context.mounted) return;
  await markExtractWithAi(ref, context, kind: needs, sections: sections);
}
