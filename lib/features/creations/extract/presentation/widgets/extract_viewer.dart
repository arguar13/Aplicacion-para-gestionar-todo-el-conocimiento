import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/domain/extract_text.dart';
import 'package:sinapsis/features/creations/extract/presentation/extract_marking.dart';
import 'package:sinapsis/features/creations/extract/presentation/providers/extract_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_follow.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_bar.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/study/presentation/providers/study_keywords_fill_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_progress_strip.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/domain/services/text_note_placement.dart';
import 'package:sinapsis/features/text_notes/presentation/providers/text_note_providers.dart';
import 'package:sinapsis/features/text_notes/presentation/text_note_actions.dart';
import 'package:sinapsis/features/text_notes/presentation/widgets/text_note_margin.dart';
import 'package:sinapsis/features/text_notes/presentation/widgets/text_notes_list_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El cuerpo de texto de corrido del marco de lectura (F47, paso 1): el de
/// **Extraer texto completo**, **Extraer resumen** y **Extraer síntesis** de
/// «Lo creado» (F43, paso 7; M8) y el de **«Texto», «Resumen» y «Síntesis»
/// de un documento procesado**, que se abren en este mismo lector (F45,
/// mejora 12) sin crear nada: [read] dice qué se lee.
///
/// **Una vista viva, nunca una copia (decisión E).** Lo que se lee sale, cada
/// vez, del texto propio de cada documento procesado y de sus marcas de
/// estudiar —las del original (M5), con la clave `procesado:…`—: si se marca
/// algo en el original, si se edita una página, si se ocultan las palabras
/// clave allá, acá cambia solo. Con varios documentos van en el orden de la
/// creación, cada uno con su título arriba, y «Contenido» lleva a cada uno.
///
/// - **La lectura**: el texto limpio —los enlaces como palabras, sin su
///   dirección, y sin `![](…)`—, en **una columna de ancho cómodo** con los
///   márgenes de un libro, con la letra y el tamaño de «Apariencia», y las
///   palabras clave en rosa en todas las oraciones (decisión 85) si se
///   resaltan —la preferencia de cada documento, la misma que en el
///   original—. Sin la tarjeta de papel de antes: el marco es la página.
/// - **Lo que falta**: un documento sin resumen, sin síntesis o —en el texto
///   completo— sin palabras clave lo dice, y ofrece marcarlo con la IA en el
///   documento mismo (`markExtractWithAi`, la máquina de M5); mientras se
///   marca, la franja de siempre con su avance, y lo marcado aparece a medida
///   que llega.
/// - **Escuchar**: ofrece lo que se ve, en su orden, al lugar del reproductor
///   del marco; lo que suena va con el color de «Resaltado de lectura» —con
///   el rosa siempre encima— y la lista acompaña sola. Si la persona se mueve
///   a mano la deja tranquila y ofrece «Volver a la lectura»; sin
///   animaciones, salta en vez de deslizarse.
/// - **El desplazamiento de la plataforma** (F45, mejora 13): el impulso
///   extra de `ReadingScrollPhysics` es para pasar hojas de un PDF; en un
///   texto de corrido, un arrastre corto bajaba muchísimo de una vez.
///
/// Un libro entero son miles de bloques: la lista arma solo los que se ven, y
/// lo que suena reconstruye solo el bloque donde está.
class ExtractViewer extends ConsumerStatefulWidget {
  const ExtractViewer({
    required this.read,
    required this.title,
    this.kicker,
    super.key,
  });

  final ExtractRead read;

  /// El nombre de lo que se lee: el que dice el reproductor.
  final String title;

  /// Lo que va arriba del título de cada documento —«TEXTO · 6 PÁGINAS»—;
  /// sin esto, el tipo y cuánto tiene lo marcado, como en «Lo creado».
  final String Function(ExtractSection section)? kicker;

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
  const _HeaderRow(this.section);

  final int section;
}

/// Lo que hay que decir de un documento: que falta algo, que se está
/// marcando, que se borró.
final class _NoticeRow extends _Row {
  const _NoticeRow(this.section);

  final int section;
}

/// Un bloque del texto de un documento.
final class _BlockRow extends _Row {
  const _BlockRow(this.section, this.block);

  final int section;
  final int block;
}

/// Lo que se puede llevar a la vista mientras suena: un título, un bloque.
abstract interface class _Revealable {
  /// Lo que se dibuja, o `null` si todavía no se armó.
  RenderBox? get revealBox;

  /// Dónde está [segment] dentro de [revealBox].
  Rect revealRect(ReadableSegment segment);

  /// Dónde está `[start, end)` del texto propio dentro de [revealBox].
  Rect rangeRect(int start, int end);

  /// Lo elegido en este pedazo, en posiciones del texto propio, o `null`.
  ({int start, int end})? get selectedRange;
}

/// Las notas en el texto de un documento (F45, paso 8b): todas, en sus
/// lugares del texto propio, y cuáles llevan su globito en cada bloque —en
/// el primero que muestra algo de su pedazo—.
@immutable
class _SectionNotes {
  const _SectionNotes(this.target, this.placed, this.bubblesByBlock);

  static const none = _SectionNotes(null, [], {});

  final TextNoteTarget? target;
  final List<PlacedTextNote> placed;
  final Map<int, List<PlacedTextNote>> bubblesByBlock;

  /// Las que tocan [block], para su punteado y para tocarlas.
  List<PlacedTextNote> touching(ExtractBlock block) => [
    for (final note in placed)
      if (note.placed && note.start! < block.end && note.end! > block.start)
        note,
  ];
}

/// Si `[start, end)` toca lo que se ve de [block]: alguno de sus tramos.
bool _blockShows(ExtractBlock block, int start, int end) =>
    block.pieces.any((piece) => piece.start < end && piece.end > start);

/// El primer bloque de [blocks] que termina después de [offset].
int _firstBlockEndingAfter(List<ExtractBlock> blocks, int offset) {
  var low = 0;
  var high = blocks.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (blocks[middle].end <= offset) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// El primer bloque de [blocks] que muestra algo de `[start, end)`, o
/// `null`: en el resumen, lo que no es del resumen no se ve.
int? _blockShowing(List<ExtractBlock> blocks, int start, int end) {
  for (
    var b = _firstBlockEndingAfter(blocks, start);
    b < blocks.length && blocks[b].start < end;
    b++
  ) {
    if (_blockShows(blocks[b], start, end)) return b;
  }
  return null;
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

  /// El marco de arriba, para darle el índice: los títulos de los documentos.
  ReadingFrameController? _frame;
  List<String> _outlined = const [];

  /// Las notas en el texto de cada documento (F45, paso 8b).
  List<_SectionNotes> _notes = const [];

  /// La nota a la que se fue desde «Notas (N)», marcada un momento: de qué
  /// documento y su tramo.
  ({int section, int start, int end})? _noteFlash;
  Timer? _noteFlashTimer;

  String get _readableId => widget.read.readableId;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frame = ReadingFrameController.maybeOf(context);
  }

  @override
  void dispose() {
    _noteFlashTimer?.cancel();
    _follow
      ..removeListener(_onFollowChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Las notas de cada documento listo, con el globito de cada una en el
  /// primer bloque que muestra su pedazo.
  List<_SectionNotes> _watchNotes(List<ExtractSection> sections) => [
    for (final section in sections)
      switch (section.own) {
        final own? when section.status == ExtractSectionStatus.ready => () {
          final target = textNoteTargetOf(own.asStudyText);
          final placed =
              ref
                  .watch(
                    placedTextNotesProvider((
                      target: target,
                      content: own.content,
                    )),
                  )
                  .valueOrNull ??
              const <PlacedTextNote>[];
          final bubbles = <int, List<PlacedTextNote>>{};
          for (final note in placed) {
            if (!note.placed) continue;
            final block = _blockShowing(section.blocks, note.start!, note.end!);
            if (block != null) (bubbles[block] ??= []).add(note);
          }
          return _SectionNotes(target, placed, bubbles);
        }(),
        _ => _SectionNotes.none,
      },
  ];

  /// Lo que se le da al marco para «Notas (N)»: un texto por documento listo.
  List<TextNoteSource> _noteSources(AppLocalizations l10n) => [
    for (var i = 0; i < _sections.length; i++)
      if (_notes[i].target case final target?)
        TextNoteSource(
          target: target,
          content: _sections[i].own!.content,
          title: _sections[i].title.trim().isEmpty
              ? l10n.f43TextUntitled
              : _sections[i].title,
          reveal: (start, end) => _revealNote(i, start, end),
        ),
  ];

  /// Lleva la vista a `[start, end)` del documento [section] y lo marca un
  /// momento: lo que hace tocar una nota en «Notas (N)». `false` si lo que
  /// se ve no lo muestra —en el resumen, una oración que no es del resumen—.
  bool _revealNote(int section, int start, int end) {
    if (section >= _sections.length) return false;
    final block = _blockShowing(_sections[section].blocks, start, end);
    if (block == null) return false;
    _noteFlashTimer?.cancel();
    setState(() => _noteFlash = (section: section, start: start, end: end));
    _noteFlashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _noteFlash = null);
    });
    _follow.release();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _goToRange(_firstBlockRow[section] + block, start, end),
    );
    return true;
  }

  /// Deja `[start, end)` de la fila [row] en la franja cómoda de la vista,
  /// de un salto. Si la fila todavía no se armó —está lejos—, salta a donde
  /// se calcula que está y vuelve a mirar en el cuadro siguiente.
  void _goToRange(int row, int start, int end, {int attempt = 0}) {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final target = _built[row];
    final box = target?.revealBox;
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    if (target == null || box == null || viewport == null) {
      if (attempt >= 8) return;
      position.jumpTo(
        _estimatedOffset(
          row,
        ).clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _goToRange(row, start, end, attempt: attempt + 1),
      );
      return;
    }
    final line = target.rangeRect(start, end);
    final atTop = viewport.getOffsetToReveal(box, 0, rect: line).offset;
    position.jumpTo(
      (atTop - position.viewportDimension * ReadAloudBand.landing).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  /// Lo elegido, para «Nota»: el documento del primer bloque con algo
  /// elegido y, en él, de la primera letra elegida a la última. `null` sin
  /// nada elegido en el texto de un documento.
  ({int section, int start, int end})? _selectedForNote() {
    int? section;
    int? start;
    int? end;
    final rows = _built.keys.toList()..sort();
    for (final row in rows) {
      final kind = row < _rows.length ? _rows[row] : null;
      if (kind is! _BlockRow) continue;
      final range = _built[row]?.selectedRange;
      if (range == null) continue;
      if (section != null && kind.section != section) break;
      section ??= kind.section;
      start ??= range.start;
      end = range.end;
    }
    if (section == null || start == null || end == null || end <= start) {
      return null;
    }
    return (section: section, start: start, end: end);
  }

  /// El menú de lo elegido: el de siempre y, sobre el texto de un documento,
  /// «Nota» (F45, paso 8b).
  Widget _selectionMenu(BuildContext context, SelectableRegionState region) {
    final l10n = AppLocalizations.of(context)!;
    final chosen = _selectedForNote();
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: region.contextMenuAnchors,
      buttonItems: [
        ...region.contextMenuButtonItems,
        if (chosen != null && _notes[chosen.section].target != null)
          ContextMenuButtonItem(
            label: l10n.highlightAddNote,
            onPressed: () {
              ContextMenuController.removeAny();
              region.clearSelection();
              final content = _sections[chosen.section].own!.content;
              unawaited(
                writeTextNote(
                  this.context,
                  ref,
                  target: _notes[chosen.section].target!,
                  start: chosen.start,
                  end: chosen.end,
                  excerpt: content.substring(chosen.start, chosen.end),
                ),
              );
            },
          ),
      ],
    );
  }

  /// Lo que se escucha de esta extracción: el mismo objeto mientras no
  /// cambien sus pedazos.
  ReadableDocument? _readable(List<ReadableSegment>? segments) {
    if (segments == null) return null;
    final cached = _document;
    if (cached != null && identical(_documentSegments, segments)) return cached;
    _documentSegments = segments;
    return _document = ReadableDocument(
      id: _readableId,
      title: widget.title,
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

  /// Lleva el título del documento [section] arriba de la vista: lo que hace
  /// «Contenido». Si todavía no se armó —está lejos—, salta a donde se
  /// calcula que está y vuelve a mirar en el cuadro siguiente.
  void _goToSection(int section, {int attempt = 0}) {
    if (!mounted || !_scroll.hasClients || section >= _headerRow.length) {
      return;
    }
    final row = _headerRow[section];
    final position = _scroll.position;
    final box = _built[row]?.revealBox;
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    if (box == null || viewport == null) {
      if (attempt >= 8) return;
      position.jumpTo(
        _estimatedOffset(
          row,
        ).clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _goToSection(section, attempt: attempt + 1),
      );
      return;
    }
    position.jumpTo(
      viewport
          .getOffsetToReveal(box, 0)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  /// Dónde se calcula que empieza la fila [row]: desde la fila armada más
  /// cercana, con el alto promedio de las filas. Hacia abajo se cuenta desde
  /// donde **termina** esa fila, que se sabe: un bloque de un libro puede ser
  /// mucho más alto que el promedio —más con una letra grande o ancha—, y
  /// contar desde su comienzo dejaría la fila buscada adentro de él, sin
  /// armarse nunca.
  double _estimatedOffset(int row) {
    final position = _scroll.position;
    final average =
        (position.maxScrollExtent + position.viewportDimension) /
        math.max(1, _rows.length);
    int? nearest;
    double? nearestTop;
    double? nearestHeight;
    for (final entry in _built.entries) {
      final box = entry.value.revealBox;
      final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
      if (box == null || viewport == null || !box.hasSize) continue;
      if (nearest == null || (entry.key - row).abs() < (nearest - row).abs()) {
        nearest = entry.key;
        nearestTop = viewport.getOffsetToReveal(box, 0).offset;
        nearestHeight = box.size.height;
      }
    }
    if (nearest == null || nearestTop == null || nearestHeight == null) {
      return row * average;
    }
    if (row <= nearest) return nearestTop - (nearest - row) * average;
    return nearestTop + nearestHeight + (row - nearest - 1) * average;
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
        ..add(_HeaderRow(i))
        ..add(_NoticeRow(i));
      _firstBlockRow.add(rows.length);
      for (var b = 0; b < blocks.length; b++) {
        rows.add(_BlockRow(i, b));
      }
    }
    _rows = rows;
  }

  /// Con varios documentos, «Contenido» lleva a cada uno por su título. Se
  /// le pasa al marco después del cuadro, y solo si cambió.
  void _outline(AppLocalizations l10n) {
    final frame = _frame;
    if (frame == null) return;
    final titles = [
      if (_sections.length > 1)
        for (final section in _sections)
          if (section.title.trim().isEmpty)
            l10n.f43TextUntitled
          else
            section.title,
    ];
    if (_sameTitles(titles, _outlined)) return;
    _outlined = titles;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      frame.outline = [
        for (final (index, title) in titles.indexed)
          ReadingOutlineEntry(
            key: Key('extract-outline-$index'),
            label: title,
            onSelected: () => _goToSection(index),
          ),
      ];
    });
  }

  static bool _sameTitles(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
    final read = widget.read;
    final sections = [
      for (final id in read.documentIds)
        ref.watch(
          extractSectionProvider((
            kind: read.kind,
            documentId: id,
            readsTrashed: read.readsTrashed,
          )),
        ),
    ];
    for (final section in sections) {
      if (section.status == ExtractSectionStatus.ready) _fillKeywords(section);
    }
    _layout(sections);
    _outline(l10n);
    _notes = _watchNotes(sections);

    final document = _readable(ref.watch(extractSegmentsProvider(read)));
    // Lo que cambia mientras se escucha —se marcó algo, se editó— se le pasa
    // al lector: sigue donde iba, con lo nuevo.
    ref.listen(extractSegmentsProvider(read), (previous, next) {
      final controller = ref.read(readAloudControllerProvider.notifier);
      if (ref.read(readAloudControllerProvider).document?.id != _readableId) {
        return;
      }
      final updated = _readable(next);
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
    final spec = ref.watch(creationKindRegistryProvider).of(read.kind);
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
        contextMenuBuilder: _selectionMenu,
        // La física de la plataforma: el texto se lee de corrido, no se pasan
        // hojas (F45, mejora 13).
        child: ListView.builder(
          key: const Key('extract-viewer-list'),
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          itemCount: _rows.length,
          itemBuilder: (context, index) => _buildRow(context, index, accent),
        ),
      ),
    );

    return ReadableRegion(
      document: document,
      child: Stack(
        key: Key('extract-viewer-${read.kind.storageKey}'),
        children: [
          Positioned.fill(
            child: ReadingNotesOffer(sources: _noteSources(l10n), child: list),
          ),
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
    );
  }

  Widget _buildRow(BuildContext context, int index, Color accent) {
    final row = _rows[index];
    final kind = widget.read.kind;
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
        kicker: widget.kicker,
        first: section == 0,
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
        notes: _notes[section],
        bubbles: _notes[section].bubblesByBlock[block] ?? const [],
        flash: switch (_noteFlash) {
          final flash? when flash.section == section => (
            flash.start,
            flash.end,
          ),
          _ => null,
        },
        onBuilt: _register,
        onGone: _unregister,
      ),
    };
    // El texto de un documento con notas lleva en el margen derecho sus
    // globitos: el bloque lo pone él mismo, con el mismo ancho.
    return _Column(
      noteMargin: row is _BlockRow && _notes[row.section].target != null,
      child: child,
    );
  }
}

/// La columna de lectura: de ancho cómodo, centrada, con los márgenes
/// generosos de un libro. Sin la tarjeta de papel de antes (F47, paso 1): el
/// marco es la página, con los colores del modo de lectura. Con
/// [noteMargin], el margen derecho lo pone el bloque, con los globitos de
/// sus notas (F45, paso 8b).
class _Column extends StatelessWidget {
  const _Column({required this.child, this.noteMargin = false});

  final Widget child;
  final bool noteMargin;

  @override
  Widget build(BuildContext context) {
    final padding = readingColumnPadding(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: readingColumnWidth),
        child: Padding(
          padding: noteMargin ? padding.copyWith(right: 0) : padding,
          child: child,
        ),
      ),
    );
  }
}

/// El título de un documento: qué se lee, en el color del tipo, el título
/// grande con la letra de lectura y cuánto tiene. Mientras se dice —con
/// varios documentos, cada apartado empieza por su título—, con el color de
/// «Resaltado de lectura».
class _SectionHeader extends ConsumerStatefulWidget {
  const _SectionHeader({
    required this.row,
    required this.kind,
    required this.section,
    required this.accent,
    required this.kicker,
    required this.first,
    required this.onBuilt,
    required this.onGone,
    super.key,
  });

  final int row;
  final StudyCreationKind kind;
  final ExtractSection section;
  final Color accent;
  final String Function(ExtractSection section)? kicker;

  /// Si es el primero: los demás llevan aire arriba, que los separa del
  /// documento de antes.
  final bool first;
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
  Rect rangeRect(int start, int end) =>
      Offset.zero & (revealBox?.size ?? Size.zero);

  /// El título no es del texto: no lleva notas.
  @override
  ({int start, int end})? get selectedRange => null;

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
    final kind = switch (widget.kind) {
      StudyCreationKind.fullText => l10n.f43TextKickerFullText,
      StudyCreationKind.summary => l10n.f43TextKickerSummary,
      _ => l10n.f43TextKickerSynthesis,
    };
    final needs = extractNeeds(widget.kind);
    final count = section.status == ExtractSectionStatus.ready
        ? originalStudyCount(l10n, needs, section.study.of(needs).length)
        : null;
    final kicker =
        widget.kicker?.call(section) ??
        (count == null ? kind : '$kind · $count');
    final title = section.status == ExtractSectionStatus.deleted
        ? l10n.f43StudioSourceDeleted
        : section.title.trim().isEmpty
        ? l10n.f43TextUntitled
        : section.title;
    final appearance = ref.watch(readingAppearanceProvider);
    final titleStyle = appearance
        .titleStyle(theme)
        .copyWith(color: reading ? StudyPalette.ink : scheme.onSurface);
    return Column(
      key: _box,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.first) const SizedBox(height: 28),
        Text(
          kicker.toUpperCase(),
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
                backgroundColor: reading ? appearance.highlight.color : null,
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
/// clave en rosa y lo que suena con el color de «Resaltado de lectura» —con
/// el rosa encima—.
class _BlockView extends ConsumerStatefulWidget {
  const _BlockView({
    required this.row,
    required this.section,
    required this.block,
    required this.onBuilt,
    required this.onGone,
    this.notes = _SectionNotes.none,
    this.bubbles = const [],
    this.flash,
    super.key,
  });

  final int row;
  final ExtractSection section;
  final ExtractBlock block;
  final void Function(int row, _Revealable target) onBuilt;
  final void Function(int row, _Revealable target) onGone;

  /// Las notas en el texto del documento (F45, paso 8b): se pinta el
  /// punteado de las que tocan este bloque.
  final _SectionNotes notes;

  /// Las notas cuyo globito va en este bloque.
  final List<PlacedTextNote> bubbles;

  /// La nota a la que se fue, marcada un momento, en posiciones del texto
  /// propio.
  final (int, int)? flash;

  @override
  ConsumerState<_BlockView> createState() => _BlockViewState();
}

class _BlockViewState extends ConsumerState<_BlockView> implements _Revealable {
  final _text = GlobalKey();

  /// De la última vez que se armó: dónde empieza cada tramo en el texto que
  /// se ve, y su formato.
  List<int> _renderStarts = const [];
  List<RenderedMarkdown> _rendered = const [];

  /// El párrafo que se dibuja. Dentro de una `SelectionArea`, un `Text`
  /// envuelve su párrafo —con el cursor de texto, por ejemplo—, así que se lo
  /// busca adentro: lo de arriba no sabe dónde está cada letra.
  @override
  RenderBox? get revealBox {
    RenderParagraph? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderParagraph) {
        found = object;
      } else {
        object.visitChildren(visit);
      }
    }

    final root = _text.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found ?? root as RenderBox?;
  }

  @override
  Rect revealRect(ReadableSegment segment) =>
      rangeRect(segment.start, segment.end);

  /// Lo elegido en este bloque, que la selección de la lista le cuenta.
  final _selection = SelectionListenerNotifier();

  @override
  ({int start, int end})? get selectedRange {
    if (!_selection.registered) return null;
    final details = _selection.selection;
    final range = details.range;
    if (details.status != SelectionStatus.uncollapsed || range == null) {
      return null;
    }
    final start = math.min(range.startOffset, range.endOffset);
    final end = math.max(range.startOffset, range.endOffset);
    final rawStart = _toRaw(start);
    final rawEnd = _toRaw(end, isEnd: true);
    return rawEnd > rawStart ? (start: rawStart, end: rawEnd) : null;
  }

  /// La posición del texto propio que se ve en [renderOffset]: la inversa de
  /// [_toRender]. Entre dos tramos —el espacio que los une— cae al final del
  /// de antes o al comienzo del de después, según [isEnd].
  int _toRaw(int renderOffset, {bool isEnd = false}) {
    final pieces = widget.block.pieces;
    for (var i = 0; i < _rendered.length && i < pieces.length; i++) {
      final from = _renderStarts[i];
      final to = from + _rendered[i].displayText.length;
      final inside = isEnd
          ? renderOffset > from && renderOffset <= to
          : renderOffset >= from && renderOffset < to;
      if (inside) {
        return pieces[i].start +
            _rendered[i].renderToRaw(renderOffset - from, isEnd: isEnd);
      }
      if (renderOffset < from) return pieces[i].start;
    }
    return pieces.last.end;
  }

  @override
  Rect rangeRect(int segmentStart, int segmentEnd) {
    final box = revealBox;
    if (box is! RenderParagraph) return Offset.zero & (box?.size ?? Size.zero);
    final block = widget.block;
    final start = math.max(segmentStart, block.start);
    final end = math.min(segmentEnd, block.end);
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
    _selection.dispose();
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
    final appearance = ref.watch(readingAppearanceProvider);
    final palette = StudyPalette.of(theme.brightness);
    final keywords = keywordsWithin(
      section.paintedKeywords,
      block.start,
      block.end,
    );
    final base = appearance.bodyStyle(theme);
    final touching = widget.notes.touching(block);
    final flash = widget.flash;

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
      // —el rosa siempre encima del resaltado de lectura—.
      final paints = <PaintedRange>[
        if (reading case (final from, final to))
          if (_clip(block.start + from, block.start + to, piece) case (
            final s,
            final e,
          ))
            PaintedRange(
              s,
              e,
              background: appearance.highlight.color,
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
        markdown.buildSpans(
          theme,
          [
            // La nota a la que se fue desde «Notas (N)», un momento.
            if (flash != null)
              if (_clip(flash.$1, flash.$2, piece) case (final s, final e))
                (s, e),
          ],
          baseStyle: base,
          paints: paints,
          notes: textNoteMarks(
            context,
            touching,
            from: piece.start,
            to: piece.end,
          ),
        ),
      );
      starts.add(at);
      rendered.add(markdown);
      at += markdown.displayText.length;
    }
    _renderStarts = starts;
    _rendered = rendered;

    // Lo elegido de este bloque, para «Nota» del menú de la selección.
    Widget text = SelectionListener(
      selectionNotifier: _selection,
      child: Text.rich(
        TextSpan(style: base, children: children),
        key: _text,
      ),
    );
    // Tocar un pedazo con nota la abre (F45, paso 8b). Solo en un bloque que
    // tiene alguna: en los demás, un toque es de la selección. El envoltorio
    // está siempre —sin nada que hacer, no compite por el toque—: que
    // aparezca con la primera nota cambiaría el árbol y la selección del
    // bloque se armaría de nuevo.
    text = GestureDetector(
      onTapUp: touching.isEmpty
          ? null
          : (details) => _openNotesAt(details.globalPosition, touching),
      child: text,
    );
    if (widget.notes.target != null) {
      text = TextNoteMargin(
        gutter: readingColumnPadding(context).right,
        notes: widget.bubbles,
        lineOf: (placed) {
          // Desde lo primero que se ve de su pedazo en este bloque.
          final first = block.pieces.firstWhere(
            (piece) => piece.end > placed.start!,
            orElse: () => block.pieces.last,
          );
          return firstLineOf(
            revealBox,
            _toRender(math.max(placed.start!, first.start)),
            _toRender(math.min(placed.end!, block.end)),
          );
        },
        onOpen: (notes) => unawaited(openTextNotes(context, ref, notes)),
        child: text,
      );
    }

    return Padding(padding: const EdgeInsets.only(bottom: 16), child: text);
  }

  /// Abre las notas cuyo pedazo está donde se tocó, si hay.
  void _openNotesAt(Offset global, List<PlacedTextNote> touching) {
    final box = revealBox;
    if (box is! RenderParagraph) return;
    final position = box.getPositionForOffset(box.globalToLocal(global));
    final noted = textNotesAt(touching, _toRaw(position.offset));
    if (noted.isNotEmpty) unawaited(openTextNotes(context, ref, noted));
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
