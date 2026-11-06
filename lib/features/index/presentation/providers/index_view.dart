import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';

/// Cómo se arma el Índice (F46): «Por tema · Por documento».
enum IndexArrangement {
  /// El árbol de los temas, con sus documentos y los capítulos de cada uno.
  byTopic,

  /// Todos los documentos, sin los temas.
  byDocument,
}

/// «Niveles: 1 · 2 · 3 · Todo», como en el índice de Word: hasta qué nivel
/// se despliegan solos los capítulos de un documento abierto.
enum IndexDepth {
  one(1),
  two(2),
  three(3),
  all(null);

  const IndexDepth(this.levels);

  /// Cuántos niveles se ven; `null` es «Todo».
  final int? levels;
}

/// Lo que se está mirando del Índice: cómo se arma, qué está desplegado y qué
/// se busca. Cada cosa en su lugar, para que cada parte de la pantalla mire
/// solo la suya (`select`) y un cambio no vuelva a dibujar el árbol entero.
@immutable
class IndexView {
  const IndexView({
    this.arrangement = IndexArrangement.byTopic,
    this.order = IndexDocumentOrder.title,
    this.depth = IndexDepth.three,
    this.numbered = false,
    this.query = '',
    this.foldedTopics = const {},
    this.openDocuments = const {},
    this.chapterFolds = const {},
  });

  final IndexArrangement arrangement;

  /// El orden de «Por documento».
  final IndexDocumentOrder order;

  final IndexDepth depth;

  /// Si los capítulos llevan su numeración, «1.2.3».
  final bool numbered;

  /// Lo buscado, sin espacios en los bordes; vacío es el árbol.
  final String query;

  /// Los temas plegados a mano: de entrada están todos desplegados. `null`
  /// es «Sin tema».
  final Set<String?> foldedTopics;

  /// Los documentos desplegados a mano: de entrada están todos plegados, y
  /// sus capítulos se leen recién al desplegarlos. Uno que está bajo dos
  /// temas se despliega en los dos.
  final Set<String> openDocuments;

  /// Los capítulos abiertos o cerrados a mano, por documento y por la clave
  /// de la entrada, distinto de lo que dicen los niveles. Cada documento
  /// tiene su mapa: abrir un capítulo cambia solo el de su documento.
  final Map<String, Map<int, bool>> chapterFolds;

  bool get searching => query.isNotEmpty;

  IndexView copyWith({
    IndexArrangement? arrangement,
    IndexDocumentOrder? order,
    IndexDepth? depth,
    bool? numbered,
    String? query,
    Set<String?>? foldedTopics,
    Set<String>? openDocuments,
    Map<String, Map<int, bool>>? chapterFolds,
  }) => IndexView(
    arrangement: arrangement ?? this.arrangement,
    order: order ?? this.order,
    depth: depth ?? this.depth,
    numbered: numbered ?? this.numbered,
    query: query ?? this.query,
    foldedTopics: foldedTopics ?? this.foldedTopics,
    openDocuments: openDocuments ?? this.openDocuments,
    chapterFolds: chapterFolds ?? this.chapterFolds,
  );
}

/// Quien cambia [IndexView]. Recuerda entre una vez y otra cómo se arma el
/// Índice —por tema o por documento, el orden, los niveles y la numeración—;
/// lo desplegado y lo buscado son de esta vez.
class IndexViewController extends StateNotifier<IndexView> {
  IndexViewController(this._prefs) : super(_restore(_prefs));

  final SharedPreferences _prefs;

  /// Dónde se recuerda.
  static const prefsKey = 'index_view_v1';

  static IndexView _restore(SharedPreferences prefs) {
    final stored = prefs.getString(prefsKey);
    if (stored == null) return const IndexView();
    try {
      final json = jsonDecode(stored);
      // Algo que no es lo que se guardó: se vuelve a lo de siempre.
      if (json is! Map<String, Object?>) return const IndexView();
      return IndexView(
        arrangement: _byName(
          IndexArrangement.values,
          json['arrangement'],
          IndexArrangement.byTopic,
        ),
        order: _byName(
          IndexDocumentOrder.values,
          json['order'],
          IndexDocumentOrder.title,
        ),
        depth: _byName(IndexDepth.values, json['depth'], IndexDepth.three),
        numbered: json['numbered'] == true,
      );
    } on FormatException {
      return const IndexView();
    }
  }

  static T _byName<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.where((value) => value.name == name).firstOrNull ?? fallback;

  void _remember() => _prefs.setString(
    prefsKey,
    jsonEncode({
      'arrangement': state.arrangement.name,
      'order': state.order.name,
      'depth': state.depth.name,
      'numbered': state.numbered,
    }),
  );

  void arrange(IndexArrangement arrangement) {
    if (arrangement == state.arrangement) return;
    state = state.copyWith(arrangement: arrangement);
    _remember();
  }

  void sortBy(IndexDocumentOrder order) {
    if (order == state.order) return;
    state = state.copyWith(order: order);
    _remember();
  }

  /// Elige los niveles. Como en Word, rehace lo desplegado: lo abierto o
  /// cerrado a mano dentro de los documentos vuelve a lo que dicen los
  /// niveles. Los temas y los documentos quedan como estaban.
  void showDepth(IndexDepth depth) {
    if (depth == state.depth && state.chapterFolds.isEmpty) return;
    state = state.copyWith(depth: depth, chapterFolds: const {});
    _remember();
  }

  void toggleNumbering() {
    state = state.copyWith(numbered: !state.numbered);
    _remember();
  }

  /// Busca [text]; en blanco, vuelve al árbol tal como estaba.
  void search(String text) {
    final query = text.trim();
    if (query == state.query) return;
    state = state.copyWith(query: query);
  }

  void toggleTopic(String? spaceId) {
    final folded = {...state.foldedTopics};
    if (!folded.remove(spaceId)) folded.add(spaceId);
    state = state.copyWith(foldedTopics: folded);
  }

  void toggleDocument(String documentId) {
    final open = {...state.openDocuments};
    if (!open.remove(documentId)) open.add(documentId);
    state = state.copyWith(openDocuments: open);
  }

  /// Abre o cierra a mano el capítulo [entryKey] de [documentId]: lo que
  /// [unfolded] dice que se ve ahora pasa a ser lo contrario.
  void toggleChapter(
    String documentId,
    int entryKey, {
    required bool unfolded,
  }) {
    final folds = {...state.chapterFolds};
    folds[documentId] = {...?folds[documentId], entryKey: !unfolded};
    state = state.copyWith(chapterFolds: folds);
  }
}

/// Lo que se está mirando del Índice. No se suelta al salir de la pantalla:
/// volver a «Estudiar → Índice» la encuentra como se la dejó.
final indexViewProvider = StateNotifierProvider<IndexViewController, IndexView>(
  (ref) => IndexViewController(ref.watch(sharedPreferencesProvider)),
);
