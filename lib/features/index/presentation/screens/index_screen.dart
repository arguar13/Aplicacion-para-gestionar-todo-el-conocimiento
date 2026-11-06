import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/presentation/index_download.dart';
import 'package:sinapsis/features/index/presentation/index_opening.dart';
import 'package:sinapsis/features/index/presentation/providers/index_providers.dart';
import 'package:sinapsis/features/index/presentation/providers/index_view.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_panels.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_search_view.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_tree_slivers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Desde qué ancho el Índice va con el documento al costado: el de una
/// tableta apaisada o una ventana de computadora (la clase «expandida» de
/// Material).
const kIndexTwoPanesWidth = 840.0;

/// **El Índice** (F46): todo lo procesado con sus capítulos, como el índice
/// automático de Word, que se arma y se corrige solo.
///
/// - Arriba, **«Buscá un capítulo»**: filtra mientras se escribe, sin acentos
///   ni mayúsculas, y lo encontrado se ve en su lugar del árbol.
/// - **«Por tema · Por documento»** y **«Niveles: 1 · 2 · 3 · Todo»**.
/// - El árbol: cada tema con sus documentos, y cada documento desplegado con
///   sus capítulos en sus niveles, los puntos y la página; el tema y el
///   documento quedan fijos arriba mientras se recorren.
/// - Mientras el relleno indexa lo que ya estaba, **una línea** dice cuánto
///   falta; lo que llega aparece en su lugar con un brillo suave, sin perder
///   lo desplegado ni la posición.
/// - En una pantalla ancha, **dos paneles**: el Índice a la izquierda y el
///   documento a la derecha. Tocar un capítulo lo abre al lado.
class IndexScreen extends StatefulWidget {
  const IndexScreen({super.key});

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  /// El mismo Índice con uno o con dos paneles: agrandar o achicar la
  /// ventana no pierde lo escrito en el buscador ni el lugar del árbol.
  final _browser = GlobalKey(debugLabel: 'index-browser');

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final browser = _IndexBrowser(key: _browser);
      if (width < kIndexTwoPanesWidth) {
        return IndexBeside(beside: false, child: browser);
      }
      final left = (width * 0.42).clamp(340.0, 480.0);
      return IndexBeside(
        beside: true,
        child: Row(
          children: [
            SizedBox(width: left, child: browser),
            const VerticalDivider(width: 1, thickness: 1),
            const Expanded(child: IndexDocumentPane()),
          ],
        ),
      );
    },
  );
}

/// El Índice en sí: la barra, el buscador, la línea de avance y el árbol o
/// lo encontrado.
class _IndexBrowser extends ConsumerStatefulWidget {
  const _IndexBrowser({super.key});

  @override
  ConsumerState<_IndexBrowser> createState() => _IndexBrowserState();
}

class _IndexBrowserState extends ConsumerState<_IndexBrowser> {
  late final _search = TextEditingController(
    text: ref.read(indexViewProvider).query,
  );
  final _searchFocus = FocusNode(debugLabel: 'index-search');
  Timer? _debounce;

  /// Cuánto se espera después de la última letra para buscar: escribir
  /// «Nicea» no hace cinco búsquedas.
  static const _typingPause = Duration(milliseconds: 220);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _typed(String text) {
    setState(() {}); // El ✕ aparece o se va.
    _debounce?.cancel();
    _debounce = Timer(_typingPause, () => _searchNow(text));
  }

  void _searchNow(String text) {
    _debounce?.cancel();
    ref.read(indexViewProvider.notifier).search(text);
  }

  void _clear() {
    _search.clear();
    _searchNow('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final searching = ref.watch(indexViewProvider.select((v) => v.searching));
    final query = ref.watch(indexViewProvider.select((v) => v.query));
    final arrangement = ref.watch(
      indexViewProvider.select((v) => v.arrangement),
    );

    // Ctrl+F (⌘F) va al buscador desde cualquier lugar del Índice. El foco
    // arranca en el Índice mismo, sin teclado en pantalla: así el atajo anda
    // de entrada, y Tab sigue por el buscador, los controles y las filas.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _searchFocus.requestFocus,
      },
      child: Focus(
        autofocus: true,
        debugLabel: 'index',
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.f46P3Title),
            actions: [
              if (arrangement == IndexArrangement.byDocument && !searching)
                const _SortButton(),
              const _MoreButton(),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): _clear,
                  },
                  child: TextField(
                    key: const Key('index-search'),
                    controller: _search,
                    focusNode: _searchFocus,
                    onChanged: _typed,
                    onSubmitted: _searchNow,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l10n.f46P3SearchHint,
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              key: const Key('index-search-clear'),
                              icon: const Icon(Icons.close),
                              tooltip: l10n.f46P3SearchClear,
                              onPressed: _clear,
                            ),
                    ),
                  ),
                ),
              ),
              const IndexProgressLine(),
              Expanded(
                child: searching
                    ? IndexSearchView(query: query)
                    : const _IndexTree(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El árbol, o lo que se ve sin él: el Índice vacío, la carga, un error.
class _IndexTree extends ConsumerWidget {
  const _IndexTree();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final topics = ref.watch(indexTopicsProvider);
    final arrangement = ref.watch(
      indexViewProvider.select((v) => v.arrangement),
    );
    final order = ref.watch(indexViewProvider.select((v) => v.order));

    final list = topics.valueOrNull;
    if (list == null) {
      if (topics.error case final error?) {
        return EmptyStateView(
          icon: Icons.error_outline,
          title: error is Failure
              ? error.localizedMessage(l10n)
              : l10n.globalErrorUnexpected,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return EmptyStateView(
        key: const Key('index-empty'),
        icon: Icons.format_list_numbered,
        title: l10n.f46P3EmptyTitle,
        message: l10n.f46P3EmptyMessage,
        actionLabel: l10n.f46P3EmptyAction,
        onAction: () => context.go(RoutePaths.processed),
      );
    }

    return CustomScrollView(
      // Cada forma de armarlo recuerda dónde estaba: buscar algo y volver, o
      // pasar a «Por documento» y volver, deja todo como estaba.
      key: PageStorageKey('index-tree-${arrangement.name}'),
      slivers: [
        const SliverToBoxAdapter(child: IndexControls()),
        if (arrangement == IndexArrangement.byTopic)
          ...indexTopicSlivers(list)
        else
          IndexAllDocuments(key: ValueKey(order), order: order),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

/// El orden de «Por documento».
class _SortButton extends ConsumerWidget {
  const _SortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final order = ref.watch(indexViewProvider.select((v) => v.order));
    return PopupMenuButton<IndexDocumentOrder>(
      key: const Key('index-sort'),
      icon: const Icon(Icons.sort),
      tooltip: l10n.f46P3SortTooltip,
      initialValue: order,
      onSelected: ref.read(indexViewProvider.notifier).sortBy,
      itemBuilder: (context) => [
        for (final (value, label) in [
          (IndexDocumentOrder.title, l10n.f46P3SortTitle),
          (IndexDocumentOrder.recent, l10n.f46P3SortRecent),
        ])
          CheckedPopupMenuItem(
            value: value,
            checked: value == order,
            child: Text(label),
          ),
      ],
    );
  }
}

/// ⋮: la numeración de los capítulos y «Descargar el índice» (F46, paso 4).
class _MoreButton extends ConsumerWidget {
  const _MoreButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final numbered = ref.watch(indexViewProvider.select((v) => v.numbered));
    return PopupMenuButton<void>(
      key: const Key('index-more'),
      tooltip: l10n.f46P3MoreTooltip,
      itemBuilder: (context) => [
        CheckedPopupMenuItem<void>(
          key: const Key('index-numbering'),
          checked: numbered,
          onTap: ref.read(indexViewProvider.notifier).toggleNumbering,
          child: Text(l10n.f46P3Numbering),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          key: const Key('index-download'),
          // Después de cerrarse el menú: la hoja se abre desde la barra.
          onTap: () => unawaited(showIndexDownload(context, ref)),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.f46P4Download),
          ),
        ),
      ],
    );
  }
}
