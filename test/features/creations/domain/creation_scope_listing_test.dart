import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_catalog.dart';
import 'package:sinapsis/features/creations/domain/services/creation_scope_listing.dart';

/// Las filas del selector de Repasar (F43, M11): de la A a la Z sin
/// mayúsculas ni acentos, cada pestaña con lo suyo, «Recientes» —como mucho
/// tres— sin repetirse abajo y la búsqueda en una sola lista.
void main() {
  CreationScopeLine line(CreationScope scope, String name) =>
      CreationScopeLine(scope: scope, name: name);

  final catalog = CreationScopeCatalog(
    all: line(const CreationScope.allProcessed(), ''),
    documents: [
      line(const CreationScope.document('gen'), 'génesis'),
      line(const CreationScope.document('exo'), 'Éxodo'),
      line(const CreationScope.document('dan'), 'Daniel'),
      line(const CreationScope.document('lev'), 'Levítico'),
      line(const CreationScope.document('num'), 'Números'),
    ],
    notebooks: [line(const CreationScope.notebook('exa'), 'Examen')],
    topics: [
      line(const CreationScope.topic('roma'), 'Roma'),
      line(const CreationScope.topic('imp'), 'Imperio'),
      line(const CreationScope.topic('otra'), 'De otra categoría'),
    ],
  );
  final listing = CreationScopeListing(
    catalog: catalog,
    topics: [
      (scope: const CreationScope.topic('imp'), name: 'Roma › Imperio'),
      (scope: const CreationScope.topic('roma'), name: 'Roma'),
      // Sin línea todavía: no se ofrece.
      (scope: const CreationScope.topic('nueva'), name: 'Nueva'),
    ],
  );

  List<String> names(Iterable<CreationScopeEntry> entries) => [
    for (final e in entries) e.name,
  ];

  test('de la A a la Z sin mayúsculas ni acentos, cada pestaña con lo '
      'suyo', () {
    expect(names(listing.of(CreationScopeTab.document)), [
      'Daniel',
      'Éxodo',
      'génesis',
      'Levítico',
      'Números',
    ]);
    expect(names(listing.of(CreationScopeTab.notebook)), ['Examen']);
    // Un tema con su rama queda junto a ella.
    expect(names(listing.of(CreationScopeTab.topic)), [
      'Roma',
      'Roma › Imperio',
    ]);
    expect(names(listing.of(CreationScopeTab.all)), [
      'Daniel',
      'Examen',
      'Éxodo',
      'génesis',
      'Levítico',
      'Números',
      'Roma',
      'Roma › Imperio',
    ]);
  });

  test('«Recientes», como mucho tres de la pestaña y que existan; «Todos», '
      'sin ellos', () {
    final recents = [
      const CreationScope.notebook('exa'),
      const CreationScope.document('lev'),
      const CreationScope.document('borrado'),
      const CreationScope.topic('otra'),
      const CreationScope.document('dan'),
      const CreationScope.document('num'),
      const CreationScope.document('gen'),
    ];

    final all = listing.sections(CreationScopeTab.all, recents);
    expect(names(all.recent), ['Examen', 'Levítico', 'De otra categoría']);
    expect(names(all.rest), [
      'Daniel',
      'Éxodo',
      'génesis',
      'Números',
      'Roma',
      'Roma › Imperio',
    ]);

    final documents = listing.sections(CreationScopeTab.document, recents);
    expect(names(documents.recent), ['Levítico', 'Daniel', 'Números']);
    expect(names(documents.rest), ['Éxodo', 'génesis']);
    // Nada sale dos veces.
    for (final tab in CreationScopeTab.values) {
      final (:recent, :rest) = listing.sections(tab, recents);
      final scopes = [
        for (final e in [...recent, ...rest]) e.scope,
      ];
      expect(scopes.toSet(), hasLength(scopes.length), reason: tab.name);
      expect(scopes.toSet(), {
        for (final e in listing.of(tab)) e.scope,
        ...recent.map((e) => e.scope),
      }, reason: '${tab.name}: todo está, arriba o abajo');
    }

    // Un tema de otra categoría se ve entre los recientes de «Temas».
    expect(names(listing.sections(CreationScopeTab.topic, recents).recent), [
      'De otra categoría',
    ]);
  });

  test('la búsqueda: una sola lista, sin acentos ni mayúsculas', () {
    expect(names(listing.search(CreationScopeTab.all, 'EXO')), ['Éxodo']);
    expect(names(listing.search(CreationScopeTab.all, 'ex')), [
      'Examen',
      'Éxodo',
    ]);
    expect(names(listing.search(CreationScopeTab.document, 'ex')), ['Éxodo']);
    expect(names(listing.search(CreationScopeTab.topic, 'imperio')), [
      'Roma › Imperio',
    ]);
    expect(listing.search(CreationScopeTab.all, 'cartago'), isEmpty);
  });

  test('buscando, después de lo que lo tiene en el nombre, los documentos '
      'que lo tienen en el texto', () {
    expect(
      names(
        listing.search(
          CreationScopeTab.all,
          'ex',
          inText: {'dan', 'exo', 'num', 'exa'},
        ),
      ),
      ['Examen', 'Éxodo', 'Daniel', 'Números'],
      reason:
          'cada documento una vez; un id que no es de un documento no '
          'cuenta',
    );
    expect(
      names(listing.search(CreationScopeTab.notebook, 'ex', inText: {'dan'})),
      ['Examen'],
    );
  });

  test('los recientes que ya no existen son los que se olvidan', () {
    expect(
      listing.missing([
        const CreationScope.allProcessed(),
        const CreationScope.document('dan'),
        const CreationScope.document('borrado'),
        const CreationScope.notebook('otro'),
        const CreationScope.topic('otra'),
      ]),
      [
        const CreationScope.document('borrado'),
        const CreationScope.notebook('otro'),
      ],
    );
  });

  test('cada recorte abre en su pestaña', () {
    expect(
      CreationScopeTab.of(const CreationScope.allProcessed()),
      CreationScopeTab.all,
    );
    expect(
      CreationScopeTab.of(const CreationScope.space('t')),
      CreationScopeTab.topic,
    );
    expect(
      CreationScopeTab.all.includes(const CreationScope.allProcessed()),
      isFalse,
      reason: '«Todo lo procesado» es su propia fila',
    );
  });
}
