import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/help/presentation/help_document.dart';
import 'package:sinapsis/features/help/presentation/providers/help_providers.dart';
import 'package:sinapsis/features/help/presentation/widgets/help_block_view.dart';
import 'package:sinapsis/features/help/presentation/widgets/help_load_error.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La guía de uso dentro de la app (F47, paso 7): la `GUIA_DE_USO.md` de la
/// raíz, empaquetada con la app, con su índice y su búsqueda.
///
/// - **El índice** sale de los títulos de la guía: cada capítulo («##») con
///   sus secciones («###») debajo. Tocar uno abre su capítulo, y tocar una
///   sección abre el capítulo en ella.
/// - **Un capítulo por vez**, con «Anterior» y «Siguiente» al pie: la guía
///   entera son miles de renglones, y armarla de una vez para saltar a un
///   lugar haría esperar al abrir.
/// - **La búsqueda** encuentra sin mayúsculas ni acentos. Desde el índice,
///   lista cada lugar con su renglón; adentro de un capítulo, la barra de
///   buscar dice «3 de 17» y salta de uno a otro, cruzando capítulos. Lo
///   encontrado se pinta en el texto, y el resultado en el que se está, en
///   amarillo.
/// - «Atrás» desde un capítulo vuelve al índice, no a Ajustes.
class UserGuideScreen extends ConsumerWidget {
  const UserGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ref
        .watch(userGuideProvider)
        .when(
          data: (guide) => _GuideView(guide: guide),
          loading: () => Scaffold(
            appBar: AppBar(title: Text(l10n.f47P7Guide)),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Scaffold(
            appBar: AppBar(title: Text(l10n.f47P7Guide)),
            body: HelpLoadError(
              onRetry: () => ref.invalidate(userGuideProvider),
            ),
          ),
        );
  }
}

class _GuideView extends StatefulWidget {
  const _GuideView({required this.guide});

  final HelpDocument guide;

  @override
  State<_GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<_GuideView> {
  final _query = TextEditingController();
  final _findFocus = FocusNode();
  final _chapterScroll = ScrollController();

  /// El capítulo abierto, o `null` en el índice.
  int? _chapter;

  /// Una llave por bloque del capítulo abierto, para llevar la vista a uno.
  List<GlobalKey> _blockKeys = const [];

  /// Dónde está lo buscado, en toda la guía.
  List<HelpMatch> _matches = const [];

  /// El resultado en el que se está, en [_matches]; -1 si ninguno.
  int _current = -1;

  /// Si la barra de buscar está abierta en el capítulo.
  bool _finding = false;

  HelpDocument get _guide => widget.guide;

  HelpMatch? get _currentMatch =>
      _current >= 0 && _current < _matches.length ? _matches[_current] : null;

  @override
  void dispose() {
    _query.dispose();
    _findFocus.dispose();
    _chapterScroll.dispose();
    super.dispose();
  }

  void _search(String text) {
    final matches = _guide.search(text);
    var current = -1;
    if (_chapter != null && matches.isNotEmpty) {
      // Adentro de un capítulo, el primero de acá en adelante: se sigue
      // donde se está, como al buscar en una página.
      current = matches.indexWhere((m) => m.chapter >= _chapter!);
      if (current < 0) current = 0;
    }
    setState(() {
      _matches = matches;
      _current = current;
    });
    if (current >= 0) _reveal(matches[current]);
  }

  void _clearSearch() {
    _query.clear();
    setState(() {
      _matches = const [];
      _current = -1;
    });
  }

  void _openChapter(int index, {int? block}) {
    setState(() {
      _chapter = index;
      _blockKeys = List.generate(
        _guide.chapters[index].blocks.length,
        (_) => GlobalKey(),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (block == null || block == 0) {
        if (_chapterScroll.hasClients) _chapterScroll.jumpTo(0);
      } else {
        _scrollToBlock(block, animate: false);
      }
    });
  }

  /// Abre el resultado [index] desde la lista del índice, con la barra de
  /// buscar abierta para seguir con los demás.
  void _openMatch(int index) {
    setState(() {
      _current = index;
      _finding = true;
    });
    _reveal(_matches[index], animate: false);
  }

  void _closeChapter() {
    setState(() {
      _chapter = null;
      _finding = false;
      _current = -1;
    });
  }

  void _step(int delta) {
    if (_matches.isEmpty) return;
    final next = _current < 0
        ? (delta > 0 ? 0 : _matches.length - 1)
        : (_current + delta) % _matches.length;
    setState(() => _current = next);
    _reveal(_matches[next]);
  }

  /// Lleva la vista a [match], abriendo su capítulo si hace falta.
  void _reveal(HelpMatch match, {bool animate = true}) {
    if (match.chapter != _chapter) {
      _openChapter(match.chapter, block: match.block);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToBlock(match.block, animate: animate);
    });
  }

  void _scrollToBlock(int block, {required bool animate}) {
    final target = block < _blockKeys.length
        ? _blockKeys[block].currentContext
        : null;
    if (target == null) return;
    final instant = !animate || MediaQuery.disableAnimationsOf(context);
    unawaited(
      Scrollable.ensureVisible(
        target,
        alignment: 0.15,
        duration: instant ? Duration.zero : const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _openFind() {
    setState(() => _finding = true);
    _findFocus.requestFocus();
  }

  void _closeFind() {
    _clearSearch();
    setState(() => _finding = false);
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _chapter;
    return PopScope(
      // Desde un capítulo, «atrás» vuelve al índice.
      canPop: chapter == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeChapter();
      },
      child: chapter == null ? _buildContents(context) : _buildChapter(context),
    );
  }

  Widget _buildContents(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final searching = _query.text.trim().length >= kHelpSearchMinChars;

    final entries = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: TextField(
          key: const Key('guide-search-field'),
          controller: _query,
          onChanged: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.f47P7GuideSearchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.f47P7GuideClearSearch,
                    onPressed: _clearSearch,
                  ),
          ),
        ),
      ),
    ];

    if (searching) {
      entries.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _matches.isEmpty
                  ? l10n.f47P7GuideNoResults(_query.text.trim())
                  : l10n.f47P7GuideResultCount(_matches.length),
              key: const Key('guide-result-count'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    } else {
      final preface = _guide.preface;
      if (preface.isNotEmpty) {
        entries.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < preface.length; i++)
                  HelpBlockView(
                    raw: _guide.raw,
                    block: preface[i],
                    previous: i == 0 ? null : preface[i - 1],
                  ),
              ],
            ),
          ),
        );
      }
      entries.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Semantics(
            header: true,
            child: Text(
              l10n.f47P7GuideContents,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    // Las filas de abajo se arman a medida que se ven: el índice son más de
    // cien, y los resultados de una búsqueda corta pueden ser cientos.
    final rows = <Widget>[
      if (searching)
        for (var i = 0; i < _matches.length; i++)
          _MatchTile(
            key: Key('guide-match-$i'),
            chapter: _guide.chapters[_matches[i].chapter].title,
            match: _matches[i],
            onTap: () => _openMatch(i),
          )
      else
        for (final chapter in _guide.chapters) ...[
          ListTile(
            key: Key('guide-chapter-${chapter.index}'),
            leading: Text(
              '${chapter.index + 1}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            minLeadingWidth: 28,
            title: Text(chapter.title),
            onTap: () => _openChapter(chapter.index),
          ),
          for (final section in chapter.sections)
            ListTile(
              key: Key('guide-section-${chapter.index}-${section.blockIndex}'),
              dense: true,
              contentPadding: const EdgeInsetsDirectional.only(
                start: 60,
                end: 16,
              ),
              title: Text(
                section.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () =>
                  _openChapter(chapter.index, block: section.blockIndex),
            ),
        ],
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.f47P7Guide)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kHelpReadingWidth),
          child: ListView.builder(
            key: const Key('guide-contents'),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: entries.length + rows.length,
            itemBuilder: (context, index) => index < entries.length
                ? entries[index]
                : rows[index - entries.length],
          ),
        ),
      ),
    );
  }

  Widget _buildChapter(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chapter = _guide.chapters[_chapter!];
    final current = _currentMatch;
    final here = [
      for (final match in _matches)
        if (match.chapter == chapter.index) match,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: l10n.f47P7GuideBackToContents,
          onPressed: _closeChapter,
        ),
        title: Text(
          chapter.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!_finding)
            IconButton(
              key: const Key('guide-open-search'),
              icon: const Icon(Icons.search),
              tooltip: l10n.f47P7GuideSearchTooltip,
              onPressed: _openFind,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_finding)
            _FindBar(
              controller: _query,
              focusNode: _findFocus,
              position: current == null ? 0 : _current + 1,
              total: _matches.length,
              searching: _query.text.trim().length >= kHelpSearchMinChars,
              onChanged: _search,
              onPrevious: () => _step(-1),
              onNext: () => _step(1),
              onClose: _closeFind,
            ),
          Expanded(
            child: SingleChildScrollView(
              key: Key('guide-chapter-body-${chapter.index}'),
              controller: _chapterScroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kHelpReadingWidth,
                  ),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < chapter.blocks.length; i++)
                          KeyedSubtree(
                            key: _blockKeys[i],
                            child: HelpBlockView(
                              raw: _guide.raw,
                              block: chapter.blocks[i],
                              previous: i == 0 ? null : chapter.blocks[i - 1],
                              matches: [
                                for (final match in here)
                                  if (match.block == i) match,
                              ],
                              current:
                                  current?.chapter == chapter.index &&
                                      current?.block == i
                                  ? current
                                  : null,
                            ),
                          ),
                        const SizedBox(height: 32),
                        _ChapterNavigation(
                          guide: _guide,
                          chapter: chapter.index,
                          onOpen: _openChapter,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un resultado de la búsqueda en el índice: su capítulo y el renglón donde
/// está, con lo encontrado marcado.
class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.chapter,
    required this.match,
    required this.onTap,
    super.key,
  });

  final String chapter;
  final HelpMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snippet = match.snippet;
    return ListTile(
      onTap: onTap,
      title: Text(
        chapter,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: snippet.before),
            TextSpan(
              text: snippet.match,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                backgroundColor: theme.colorScheme.tertiaryContainer,
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            TextSpan(text: snippet.after),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// La barra de buscar de un capítulo: el campo arriba y, debajo, en qué
/// resultado se está con sus flechas. En dos renglones para que entre a
/// 360 dp con la letra al doble.
class _FindBar extends StatelessWidget {
  const _FindBar({
    required this.controller,
    required this.focusNode,
    required this.position,
    required this.total,
    required this.searching,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// En qué resultado se está, desde 1; 0 si en ninguno.
  final int position;
  final int total;

  /// Si lo escrito alcanza para buscar.
  final bool searching;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('guide-find-field'),
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => onNext(),
                    decoration: InputDecoration(
                      hintText: l10n.f47P7GuideSearchHint,
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('guide-find-close'),
                  icon: const Icon(Icons.close),
                  tooltip: l10n.f47P7GuideCloseSearch,
                  onPressed: onClose,
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      !searching
                          ? ''
                          : total == 0
                          ? l10n.f47P7GuideNoResults(controller.text.trim())
                          : l10n.f47P7GuideMatchPosition(position, total),
                      key: const Key('guide-find-position'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('guide-find-previous'),
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: l10n.f47P7GuidePreviousMatch,
                  onPressed: total == 0 ? null : onPrevious,
                ),
                IconButton(
                  key: const Key('guide-find-next'),
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: l10n.f47P7GuideNextMatch,
                  onPressed: total == 0 ? null : onNext,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Al pie de un capítulo: el anterior y el siguiente, con sus títulos.
class _ChapterNavigation extends StatelessWidget {
  const _ChapterNavigation({
    required this.guide,
    required this.chapter,
    required this.onOpen,
  });

  final HelpDocument guide;
  final int chapter;
  final void Function(int index) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final previous = chapter > 0 ? guide.chapters[chapter - 1] : null;
    final next = chapter + 1 < guide.chapters.length
        ? guide.chapters[chapter + 1]
        : null;

    Widget tile({
      required Key key,
      required String label,
      required HelpChapter target,
      required bool forward,
    }) => ListTile(
      key: key,
      leading: forward ? null : const Icon(Icons.arrow_back),
      trailing: forward ? const Icon(Icons.arrow_forward) : null,
      title: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(target.title, style: theme.textTheme.titleSmall),
      onTap: () => onOpen(target.index),
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (previous != null)
            tile(
              key: const Key('guide-previous-chapter'),
              label: l10n.f47P7GuidePreviousChapter,
              target: previous,
              forward: false,
            ),
          if (previous != null && next != null) const Divider(height: 1),
          if (next != null)
            tile(
              key: const Key('guide-next-chapter'),
              label: l10n.f47P7GuideNextChapter,
              target: next,
              forward: true,
            ),
        ],
      ),
    );
  }
}
