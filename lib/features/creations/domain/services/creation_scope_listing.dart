import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_catalog.dart';

/// Cuántos recientes se ven arriba de la lista del selector (M11).
const kRecentScopesShown = 3;

/// Las cuatro pestañas del selector: Todo · Documentos · Cuadernos · Temas.
enum CreationScopeTab {
  all,
  document,
  notebook,
  topic;

  /// La pestaña donde vive [scope]: la que abre la hoja.
  static CreationScopeTab of(CreationScope scope) => switch (scope) {
    AllProcessed() => all,
    ProcessedDocumentScope() => document,
    NotebookScope() => notebook,
    TopicScope() || SpaceScope() => topic,
  };

  /// Si [scope] es de esta pestaña. «Todo lo procesado» no es de ninguna: es
  /// su propia fila, la primera de «Todo».
  bool includes(CreationScope scope) =>
      !scope.isAll && (this == all || of(scope) == this);
}

/// Una fila del selector: lo que apunta, su nombre como se muestra —un tema
/// con su rama, «Roma › Imperio»— y su línea.
typedef CreationScopeEntry = ({
  CreationScope scope,
  String name,
  CreationScopeLine line,
});

/// Las filas del selector (F43, M11), armadas una vez por catálogo: todo de
/// la A a la Z —sin mayúsculas ni acentos, como el Atlas—, y de ahí cada
/// pestaña, los recientes sin repetir y la búsqueda.
///
/// Es puro: no lee nada. Lo arma la hoja con lo que ya leyó en lote (el
/// catálogo y los temas del Atlas) y lo vuelve a armar solo si eso cambia,
/// nunca al escribir en el buscador.
class CreationScopeListing {
  /// [topics] son los temas de la categoría elegida, con el nombre a mostrar;
  /// los que el catálogo no tiene —todavía no llegó su línea— no se ofrecen.
  factory CreationScopeListing({
    required CreationScopeCatalog catalog,
    required List<({CreationScope scope, String name})> topics,
  }) {
    final listed = <CreationScopeEntry>[
      for (final line in catalog.documents)
        (scope: line.scope, name: line.name, line: line),
      for (final line in catalog.notebooks)
        (scope: line.scope, name: line.name, line: line),
      for (final topic in topics)
        if (catalog.lineOf(topic.scope) case final line?)
          (scope: topic.scope, name: topic.name, line: line),
    ];
    final folded = {
      for (final entry in listed)
        entry.scope: normalizeVocabularyLabel(entry.name),
    };
    listed.sort((a, b) {
      final byName = folded[a.scope]!.compareTo(folded[b.scope]!);
      return byName != 0
          ? byName
          : a.scope.storageKey.compareTo(b.scope.storageKey);
    });
    return CreationScopeListing._(
      catalog,
      listed,
      folded,
      // Los temas de otra categoría que están entre los recientes: se ven
      // arriba aunque no estén en la lista.
      {
        for (final line in catalog.topics)
          line.scope: (scope: line.scope, name: line.name, line: line),
        for (final entry in listed) entry.scope: entry,
      },
    );
  }

  CreationScopeListing._(
    this.catalog,
    this._sorted,
    this._folded,
    this._byScope,
  );

  final CreationScopeCatalog catalog;
  final List<CreationScopeEntry> _sorted;
  final Map<CreationScope, String> _folded;
  final Map<CreationScope, CreationScopeEntry> _byScope;
  final Map<CreationScopeTab, List<CreationScopeEntry>> _byTab = {};

  /// Lo de [tab], entero y de la A a la Z.
  List<CreationScopeEntry> of(CreationScopeTab tab) => _byTab[tab] ??= [
    for (final entry in _sorted)
      if (tab.includes(entry.scope)) entry,
  ];

  /// La fila de [scope], o `null` si ya no existe.
  CreationScopeEntry? entryOf(CreationScope scope) => _byScope[scope];

  /// Sin buscar: **«Recientes»**, los primeros [kRecentScopesShown] de
  /// [recents] que son de [tab] y existen, y **«Todos»**, lo de [tab] de la A
  /// a la Z sin ellos. Nada sale dos veces.
  ({List<CreationScopeEntry> recent, List<CreationScopeEntry> rest}) sections(
    CreationScopeTab tab,
    List<CreationScope> recents,
  ) {
    final recent = [
      for (final scope in recents)
        if (tab.includes(scope))
          if (_byScope[scope] case final entry?) entry,
    ].take(kRecentScopesShown).toList();
    final shown = {for (final entry in recent) entry.scope};
    return (
      recent: recent,
      rest: [
        for (final entry in of(tab))
          if (!shown.contains(entry.scope)) entry,
      ],
    );
  }

  /// Buscando: una sola lista. Primero lo de [tab] cuyo nombre tiene [text]
  /// —sin mayúsculas ni acentos— y después los documentos de [inText], los que
  /// lo tienen en su texto, como busca Procesado; cada parte, de la A a la Z.
  List<CreationScopeEntry> search(
    CreationScopeTab tab,
    String text, {
    Set<String> inText = const {},
  }) {
    final needle = normalizeVocabularyLabel(text);
    if (needle.isEmpty) return of(tab);
    final byName = [
      for (final entry in of(tab))
        if (_folded[entry.scope]!.contains(needle)) entry,
    ];
    if (inText.isEmpty) return byName;
    final named = {for (final entry in byName) entry.scope};
    return [
      ...byName,
      for (final entry in of(tab))
        if (entry.scope case ProcessedDocumentScope(
          :final documentId,
        ) when inText.contains(documentId) && !named.contains(entry.scope))
          entry,
    ];
  }

  /// Los de [recents] que ya no existen —un documento en la papelera, un
  /// cuaderno o un tema borrados—: los que se olvidan.
  List<CreationScope> missing(List<CreationScope> recents) => [
    for (final scope in recents)
      if (!scope.isAll && catalog.lineOf(scope) == null) scope,
  ];
}
