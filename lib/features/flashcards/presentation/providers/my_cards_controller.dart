import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_row.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/card_browser_providers.dart';

/// Cuántas tarjetas trae cada página.
const kMyCardsPageSize = 50;

/// Cuántas páginas guarda a la vez como mucho: con más, descarta la que hace
/// más que no se mira. Es lo que mantiene la memoria acotada con 10.000
/// tarjetas: nunca hay más de `kMyCardsPageSize * kMyCardsMaxCachedPages`
/// renglones cargados, se recorra lo que se recorra.
const kMyCardsMaxCachedPages = 6;

/// Cuánto espera tras un cambio en la base antes de releer: una ráfaga de
/// escrituras (pausar cien tarjetas) es una sola lectura.
const kMyCardsRefreshDelay = Duration(milliseconds: 120);

/// Lo que la pantalla «Mis tarjetas» muestra y cambia (F31, ola 2, decisión
/// 72). Los renglones NO están acá: se piden con [MyCardsController.rowAt], que
/// los trae de a páginas; el estado trae solo lo chico y el número de versión
/// que avisa que hay que volver a mirar.
@immutable
class MyCardsState {
  const MyCardsState({
    required this.query,
    this.total,
    this.statusCounts,
    this.selected = const {},
    this.selecting = false,
    this.failed = false,
    this.version = 0,
  });

  final CardBrowserQuery query;

  /// Cuántas tarjetas cumplen [query]; `null` mientras se lee la primera vez.
  final int? total;

  /// Cuántas hay en cada estado dentro del recorte y el texto; `null` hasta la
  /// primera lectura.
  final Map<CardBrowserStatus, int>? statusCounts;

  /// Las elegidas para una acción en lote.
  final Set<String> selected;

  /// Si se está eligiendo (aunque no haya ninguna elegida todavía).
  final bool selecting;

  /// Si la última lectura falló.
  final bool failed;

  /// Sube cada vez que cambian los renglones guardados, para que la lista se
  /// vuelva a armar.
  final int version;

  MyCardsState copyWith({
    CardBrowserQuery? query,
    int? Function()? total,
    Map<CardBrowserStatus, int>? Function()? statusCounts,
    Set<String>? selected,
    bool? selecting,
    bool? failed,
    int? version,
  }) => MyCardsState(
    query: query ?? this.query,
    total: total != null ? total() : this.total,
    statusCounts: statusCounts != null ? statusCounts() : this.statusCounts,
    selected: selected ?? this.selected,
    selecting: selecting ?? this.selecting,
    failed: failed ?? this.failed,
    version: version ?? this.version,
  );
}

class _CachedPage {
  _CachedPage(this.rows, this.dataEpoch);
  final List<CardBrowserRow> rows;
  final int dataEpoch;
}

/// El control de «Mis tarjetas»: lee de a páginas, guarda pocas, y se entera
/// de los cambios en la base.
///
/// Cada vez que cambia el PEDIDO (otro filtro, otro texto, otro orden) se
/// descarta todo lo cargado; cuando cambian los DATOS (se pausó una tarjeta, se
/// creó otra) las páginas quedan como están —no se ve un parpadeo— y cada una
/// se vuelve a leer la próxima vez que se mira.
class MyCardsController extends AutoDisposeNotifier<MyCardsState> {
  final LinkedHashMap<int, _CachedPage> _pages = LinkedHashMap();
  final Set<int> _loading = {};
  int _queryEpoch = 0;
  int _dataEpoch = 0;
  Timer? _refreshTimer;
  bool _disposed = false;
  StreamSubscription<void>? _changes;

  /// Cuántos renglones hay cargados ahora: lo que las pruebas miran para
  /// comprobar que la memoria está acotada.
  @visibleForTesting
  int get cachedRows =>
      _pages.values.fold(0, (sum, page) => sum + page.rows.length);

  @override
  MyCardsState build() {
    final repository = ref.watch(cardBrowserRepositoryProvider);
    _disposed = false;
    _pages.clear();
    _loading.clear();
    _changes = repository.changes().listen((_) => _scheduleRefresh());
    ref.onDispose(() {
      _disposed = true;
      _refreshTimer?.cancel();
      unawaited(_changes?.cancel());
    });
    // La primera lectura va fuera de `build`: leer escribe el estado.
    scheduleMicrotask(() => unawaited(_reload()));
    return const MyCardsState(query: CardBrowserQuery());
  }

  /// El renglón de la posición [index] de la lista, o `null` si todavía no
  /// llegó: pide su página y la lista se vuelve a armar al llegar. Si la página
  /// es vieja la devuelve igual (mejor lo de hace un instante que un hueco) y
  /// pide la nueva.
  CardBrowserRow? rowAt(int index) {
    final pageIndex = index ~/ kMyCardsPageSize;
    final page = _pages.remove(pageIndex);
    if (page != null) _pages[pageIndex] = page; // la más reciente al final
    if (page == null || page.dataEpoch != _dataEpoch) {
      _requestPage(pageIndex);
    }
    final offset = index - pageIndex * kMyCardsPageSize;
    if (page == null || offset >= page.rows.length) return null;
    return page.rows[offset];
  }

  // ---- el pedido ----------------------------------------------------------

  void setText(String text) {
    if (text == state.query.text) return;
    _changeQuery(state.query.copyWith(text: text));
  }

  void setStatus(CardBrowserStatus? status) {
    if (status == state.query.status) return;
    _changeQuery(state.query.copyWith(status: () => status));
  }

  void setScope(StudyScope scope) {
    if (scope == state.query.scope) return;
    _changeQuery(state.query.copyWith(scope: scope));
  }

  void setSort(CardBrowserSort sort) {
    if (sort == state.query.sort) {
      _changeQuery(state.query.copyWith(descending: !state.query.descending));
      return;
    }
    _changeQuery(state.query.copyWith(sort: sort, descending: false));
  }

  void toggleDescending() =>
      _changeQuery(state.query.copyWith(descending: !state.query.descending));

  void _changeQuery(CardBrowserQuery query) {
    _queryEpoch++;
    _pages.clear();
    _loading.clear();
    state = state.copyWith(
      query: query,
      total: () => null,
      failed: false,
      version: state.version + 1,
    );
    unawaited(_reload());
  }

  // ---- la selección ---------------------------------------------------------

  void startSelecting(String id) {
    state = state.copyWith(selecting: true, selected: {...state.selected, id});
  }

  void toggle(String id) {
    final next = {...state.selected};
    if (!next.remove(id)) next.add(id);
    state = state.copyWith(selected: next);
  }

  void clearSelection() {
    state = state.copyWith(selecting: false, selected: <String>{});
  }

  /// Elige TODAS las que cumplen el pedido de ahora, estén o no cargadas.
  /// Devuelve cuántas eligió; `null` si la lectura falló.
  Future<int?> selectAll() async {
    final epoch = _queryEpoch;
    final result = await ref
        .read(cardBrowserRepositoryProvider)
        .ids(state.query);
    return result.match((_) => null, (ids) {
      if (epoch != _queryEpoch) return null;
      state = state.copyWith(selecting: true, selected: ids.toSet());
      return ids.length;
    });
  }

  // ---- la lectura -----------------------------------------------------------

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(kMyCardsRefreshDelay, retry);
  }

  /// Vuelve a leer todo: lo que cambió en la base, o después de un fallo.
  void retry() {
    _dataEpoch++;
    _loading.clear();
    unawaited(_reload());
  }

  /// Vuelve a leer el total y los conteos; las páginas se renuevan solas al
  /// mirarlas.
  Future<void> _reload() async {
    final epoch = _queryEpoch;
    final query = state.query;
    final repository = ref.read(cardBrowserRepositoryProvider);
    final total = await repository.count(query);
    final counts = await repository.statusCounts(query);
    if (epoch != _queryEpoch || _disposed) return;
    total.match(
      (_) => state = state.copyWith(failed: true, version: state.version + 1),
      (n) => state = state.copyWith(
        total: () => n,
        statusCounts: () => counts.getOrElse((_) => const {}),
        failed: false,
        version: state.version + 1,
      ),
    );
  }

  void _requestPage(int pageIndex) {
    if (!_loading.add(pageIndex)) return;
    unawaited(_loadPage(pageIndex));
  }

  Future<void> _loadPage(int pageIndex) async {
    final epoch = _queryEpoch;
    final dataEpoch = _dataEpoch;
    final result = await ref
        .read(cardBrowserRepositoryProvider)
        .page(
          state.query,
          offset: pageIndex * kMyCardsPageSize,
          limit: kMyCardsPageSize,
        );
    if (epoch != _queryEpoch || _disposed) return;
    result.match(
      // Una página que falló se queda en `_loading`: no se reintenta sola en
      // cada armado de la lista (sería un bucle contra una base rota). La
      // pantalla ofrece reintentar, y cualquier cambio de pedido o de datos
      // la vuelve a pedir.
      (_) => state = state.copyWith(failed: true, version: state.version + 1),
      (rows) {
        _loading.remove(pageIndex);
        _pages[pageIndex] = _CachedPage(rows, dataEpoch);
        while (_pages.length > kMyCardsMaxCachedPages) {
          _pages.remove(_pages.keys.first);
        }
        state = state.copyWith(version: state.version + 1);
      },
    );
  }
}

final myCardsControllerProvider =
    AutoDisposeNotifierProvider<MyCardsController, MyCardsState>(
      MyCardsController.new,
    );
