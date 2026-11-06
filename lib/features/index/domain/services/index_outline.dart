import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';

/// Una fila de un documento desplegado en el Índice (F46): una entrada con lo
/// que la pantalla necesita para dibujarla en su lugar del árbol.
@immutable
class IndexOutlineRow {
  const IndexOutlineRow({
    required this.entry,
    required this.hasChildren,
    required this.unfolded,
    this.number,
  });

  final IndexEntry entry;

  /// «1», «1.2», «1.2.3»: su numeración entre los capítulos del documento.
  /// `null` en «Texto completo» y en una imagen, que no se numeran, y
  /// siempre que la numeración está apagada.
  final String? number;

  /// Si tiene capítulos adentro: lo que la deja plegarse.
  final bool hasChildren;

  /// Si sus capítulos se ven. Sin [hasChildren], siempre `true`.
  final bool unfolded;

  @override
  bool operator ==(Object other) =>
      other is IndexOutlineRow &&
      other.entry == entry &&
      other.number == number &&
      other.hasChildren == hasChildren &&
      other.unfolded == unfolded;

  @override
  int get hashCode => Object.hash(entry, number, hasChildren, unfolded);

  @override
  String toString() =>
      'IndexOutlineRow(${entry.level} ${number ?? '-'} «${entry.title}»'
      '${hasChildren ? (unfolded ? ' ▾' : ' ▸') : ''})';
}

/// Las filas que se ven de las entradas de un documento, en su orden: los
/// capítulos con su nivel, plegados como se pidió, y después «Texto completo»
/// o las imágenes, que no tienen nada adentro.
///
/// Un capítulo se despliega solo si su nivel es menor que [depth] —«Niveles:
/// 2» deja ver los de nivel 1 y 2, como en Word—, salvo que se haya abierto
/// o cerrado a mano: [folds] dice, por la clave de la entrada, lo que se
/// eligió. [depth] `null` es «Todo».
///
/// Una pasada, sin volver atrás: con un libro de miles de capítulos cuesta
/// lo que mide, y nunca más.
List<IndexOutlineRow> indexOutline(
  List<IndexEntry> entries, {
  required int? depth,
  Map<int, bool> folds = const {},
  bool numbered = false,
}) {
  final rows = <IndexOutlineRow>[];
  // Cuántos capítulos van en cada nivel por encima del actual: «1.2.3».
  final counters = <int>[];
  // Debajo de un capítulo plegado no se ve nada más hondo que él.
  int? hiddenBelow;
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final chapter = _isChapter(entry);
    final level = chapter ? entry.level : 1;
    String? number;
    if (chapter) {
      if (counters.length >= level) counters.length = level;
      while (counters.length < level) {
        counters.add(0);
      }
      counters[level - 1]++;
      if (numbered) number = counters.join('.');
    }
    if (hiddenBelow != null && level > hiddenBelow) continue;
    hiddenBelow = null;

    final hasChildren =
        chapter &&
        i + 1 < entries.length &&
        _isChapter(entries[i + 1]) &&
        entries[i + 1].level > level;
    final unfolded =
        !hasChildren || (folds[entry.key] ?? (depth == null || level < depth));
    if (!unfolded) hiddenBelow = level;
    rows.add(
      IndexOutlineRow(
        entry: entry,
        number: number,
        hasChildren: hasChildren,
        unfolded: unfolded,
      ),
    );
  }
  return rows;
}

bool _isChapter(IndexEntry entry) =>
    entry.origin != IndexEntryOrigin.image &&
    entry.origin != IndexEntryOrigin.wholeText;

/// Las coincidencias de una búsqueda de un mismo documento, con lo que las
/// contiene: lo que la pantalla dibuja como un pedazo del árbol, para que lo
/// encontrado se vea en su lugar y no suelto.
@immutable
class IndexSearchGroup {
  const IndexSearchGroup({required this.first, required this.rows});

  /// La primera coincidencia del documento: su título, su tipo y sus temas.
  final IndexSearchHit first;

  /// Los capítulos que contienen a cada coincidencia —una sola vez cada uno,
  /// aunque contengan a varias— y las coincidencias, en el orden del texto.
  final List<IndexSearchRow> rows;

  String get documentId => first.entry.documentId;
}

/// Una fila de [IndexSearchGroup]: una coincidencia, o un capítulo que se ve
/// porque contiene a una.
@immutable
class IndexSearchRow {
  const IndexSearchRow({required this.entry, required this.matched});

  final IndexEntry entry;

  /// Si es lo que se buscó; si no, es uno de sus padres.
  final bool matched;

  @override
  bool operator ==(Object other) =>
      other is IndexSearchRow &&
      other.entry == entry &&
      other.matched == matched;

  @override
  int get hashCode => Object.hash(entry, matched);

  @override
  String toString() => 'IndexSearchRow(«${entry.title}»${matched ? ' ✓' : ''})';
}

/// Agrupa [hits] —ya en el orden del Índice, por documento y como en el
/// árbol— por documento. Cada coincidencia lleva antes los capítulos que la
/// contienen que todavía no se mostraron: dos coincidencias de un mismo
/// capítulo comparten sus padres, y un padre que también coincide se marca
/// una vez, como coincidencia.
List<IndexSearchGroup> groupIndexSearch(List<IndexSearchHit> hits) {
  final groups = <IndexSearchGroup>[];
  IndexSearchHit? first;
  var rows = <IndexSearchRow>[];
  var shown = <int, int>{};

  void close() {
    final head = first;
    if (head != null) groups.add(IndexSearchGroup(first: head, rows: rows));
  }

  for (final hit in hits) {
    if (first == null || first.entry.documentId != hit.entry.documentId) {
      close();
      first = hit;
      rows = <IndexSearchRow>[];
      shown = <int, int>{};
    }
    for (final ancestor in hit.ancestors) {
      if (shown.containsKey(ancestor.key)) continue;
      shown[ancestor.key] = rows.length;
      rows.add(IndexSearchRow(entry: ancestor, matched: false));
    }
    final at = shown[hit.entry.key];
    if (at != null) {
      rows[at] = IndexSearchRow(entry: hit.entry, matched: true);
    } else {
      shown[hit.entry.key] = rows.length;
      rows.add(IndexSearchRow(entry: hit.entry, matched: true));
    }
  }
  close();
  return groups;
}
