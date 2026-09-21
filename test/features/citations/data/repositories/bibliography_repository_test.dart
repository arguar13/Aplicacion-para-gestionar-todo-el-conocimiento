import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/features/citations/data/repositories/bibliography_repository_impl.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/services/bibliography_builder.dart';
import 'package:sinapsis/features/citations/domain/services/styles/apa7_style.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

import '../../../../support/fake_id_generator.dart';

/// De dónde salen las fuentes de una bibliografía (F15): lo que se lee de cada
/// una, y los conjuntos —espacio, rama del Atlas, nota, selección, lo que
/// muestra la Biblioteca—. Contra SQLite real, en memoria.
void main() {
  late AppDatabase db;
  late KnowledgeEntryWriter writer;
  late BibliographyRepositoryImpl repository;
  final capturedAt = DateTime(2026, 9, 11, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    writer = KnowledgeEntryWriter(
      db,
      clock: () => DateTime(2026, 9, 21, 9),
      ids: FakeIdGenerator(prefix: 'persona'),
    );
    repository = BibliographyRepositoryImpl(db);
  });

  tearDown(() => db.close());

  Future<void> source(
    String id, {
    String? title,
    SourceKind kind = SourceKind.webPage,
    String? url,
    String? authorName,
    DateTime? publishedAt,
    String? spaceId,
  }) => writer.upsert(
    KnowledgeItem(
      id: id,
      title: title ?? 'Título $id',
      spaceId: spaceId,
      source: Source(
        id: 'src-$id',
        kind: kind,
        capturedAt: capturedAt,
        url: url,
        authorName: authorName,
        publishedAt: publishedAt,
      ),
      processingState: ProcessingState.ready,
      createdAt: capturedAt,
      updatedAt: capturedAt,
    ),
  );

  Future<void> note(String id) => source(id, kind: SourceKind.manualNote);

  Future<void> trash(String id) =>
      (db.update(db.knowledgeEntries)..where((e) => e.id.equals(id))).write(
        KnowledgeEntriesCompanion(deletedAt: Value(DateTime(2026, 9, 20))),
      );

  Future<void> relate(String from, String to, RelationKind kind) => db
      .into(db.relations)
      .insert(
        RelationsCompanion.insert(
          id: 'rel-$from-$to-${kind.name}',
          fromItemId: from,
          toItemId: to,
          kind: kind,
          createdAt: capturedAt,
        ),
      );

  Future<void> link(String from, String? to, {String title = 'Enlace'}) => db
      .into(db.inlineLinks)
      .insert(
        InlineLinksCompanion.insert(
          id: 'link-$from-${to ?? title}',
          fromItemId: from,
          targetTitle: title,
          normalizedTitle: '$title-${to ?? 'roto'}'.toLowerCase(),
          toItemId: Value(to),
          createdAt: capturedAt,
        ),
      );

  Future<void> assign(String itemId, String valueId) => db
      .into(db.itemPropertyValues)
      .insert(
        ItemPropertyValuesCompanion.insert(
          itemId: itemId,
          propertyValueId: valueId,
        ),
      );

  Future<String> temaId() async => (await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.name.equals('Tema'))).getSingle()).id;

  Future<void> value(String id, {String? parent, int depth = 0}) async => db
      .into(db.propertyValues)
      .insert(
        PropertyValuesCompanion.insert(
          id: id,
          definitionId: await temaId(),
          value: 'Valor $id',
          createdAt: capturedAt,
          parentId: Value(parent),
          depth: Value(depth),
        ),
      );

  List<String> ids(List<BibliographySource> sources) => [
    for (final s in sources) s.itemId,
  ];

  const garcia = PersonName(family: 'García Márquez', given: 'Gabriel');

  group('lo que se lee de cada fuente', () {
    test(
      'lo mínimo para citarla: título, enlace, autor, fechas y tipo',
      () async {
        await source(
          'pagina',
          title: 'Una entrada',
          url: 'https://blog.example.org/entrada',
          authorName: 'Ana Pérez',
          publishedAt: DateTime(2020, 6),
        );

        final result = (await repository.sourcesOf(['pagina'])).single;
        final cited = result.source;

        expect(result.itemId, 'pagina');
        expect(cited.title, 'Una entrada');
        expect(cited.url, 'https://blog.example.org/entrada');
        expect(cited.authorName, 'Ana Pérez');
        expect(cited.capturedAt, capturedAt);
        expect(cited.kind, SourceKind.webPage);
        // Sin precisión guardada, una fecha capturada es de día completo.
        expect(cited.date, PublicationDate.ofDay(2020, 6, 1));
        expect(cited.reference.isEmpty, isTrue);
      },
    );

    test('los datos bibliográficos y sus personas, en su orden', () async {
      await source('libro', title: 'Cien años de soledad');
      await writer.setReference(
        'libro',
        const ReferenceData(
          type: ReferenceType.book,
          publisher: 'Sudamericana',
          publisherPlace: 'Buenos Aires',
          contributors: [
            Contributor(name: garcia),
            Contributor(
              name: PersonName(family: 'Rabassa', given: 'Gregory'),
              role: ContributorRole.translator,
            ),
          ],
        ),
      );

      final reference = (await repository.sourcesOf([
        'libro',
      ])).single.source.reference;

      expect(reference.type, ReferenceType.book);
      expect(reference.publisher, 'Sudamericana');
      expect(reference.contributors.map((c) => c.name.family), [
        'García Márquez',
        'Rabassa',
      ]);
      expect(reference.contributors.last.role, ContributorRole.translator);
    });

    test(
      'la fecha junta la de la fuente con la exactitud de la referencia',
      () async {
        await source('anio', publishedAt: DateTime(1967));
        await source('sin-fecha', publishedAt: DateTime(2001, 5, 5));
        await source('mes', publishedAt: DateTime(2020, 3));
        await writer.setReference(
          'anio',
          const ReferenceData(publicationPrecision: PublicationPrecision.year),
        );
        await writer.setReference(
          'sin-fecha',
          const ReferenceData(
            publicationPrecision: PublicationPrecision.undated,
          ),
        );
        await writer.setReference(
          'mes',
          const ReferenceData(publicationPrecision: PublicationPrecision.month),
        );

        final byId = {
          for (final s in await repository.sourcesOf([
            'anio',
            'sin-fecha',
            'mes',
          ]))
            s.itemId: s.source.date,
        };

        expect(byId['anio'], PublicationDate.ofYear(1967));
        expect(byId['mes'], PublicationDate.ofMonth(2020, 3));
        // «Sin fecha» gana sobre cualquier fecha guardada: se decidió así.
        expect(byId['sin-fecha'], const PublicationDate.undated());
      },
    );

    test('una fuente sin fecha guardada tiene la fecha desconocida', () async {
      await source('nada');

      final cited = (await repository.sourcesOf(['nada'])).single.source;

      expect(cited.date.isUnknown, isTrue);
    });

    test('una referencia sin texto —solo datos— también se cita', () async {
      await source('solo-datos', kind: SourceKind.reference);
      await writer.setReference(
        'solo-datos',
        const ReferenceData(type: ReferenceType.book, publisher: 'Editorial'),
      );

      final cited = (await repository.sourcesOf(['solo-datos'])).single.source;

      expect(cited.kind, SourceKind.reference);
      expect(cited.type, ReferenceType.book);
    });
  });

  group('lo que se deja afuera', () {
    test('lo que no existe, una nota y lo que está en la papelera', () async {
      await source('vivo');
      await source('borrado');
      await note('nota');
      await trash('borrado');

      final result = await repository.sourcesOf([
        'vivo',
        'borrado',
        'nota',
        'fantasma',
      ]);

      expect(ids(result), ['vivo']);
    });

    test('sin repetir y en el orden en que vienen', () async {
      await source('a');
      await source('b');
      await source('c');

      final result = await repository.sourcesOf(['c', 'a', 'c', 'b', 'a']);

      expect(ids(result), ['c', 'a', 'b']);
    });

    test('una lista vacía da una lista vacía', () async {
      expect(await repository.sourcesOf(const []), isEmpty);
    });

    test('pasa el tope de una consulta sin perder ninguna', () async {
      // Más ids de los que entran en una consulta (400).
      const total = 950;
      await db.batch((batch) {
        batch
          ..insertAll(db.knowledgeEntries, [
            for (var i = 0; i < total; i++)
              KnowledgeEntriesCompanion.insert(
                id: 'f$i',
                title: 'Fuente $i',
                kind: ItemKind.source,
                state: ItemState.triaged,
                createdAt: capturedAt,
                updatedAt: capturedAt,
                deviceId: 'telefono',
              ),
          ])
          ..insertAll(db.knowledgeSources, [
            for (var i = 0; i < total; i++)
              KnowledgeSourcesCompanion.insert(
                itemId: 'f$i',
                sourceType: SourceKind.webPage,
                capturedAt: capturedAt,
                contentHash: '',
                processingStatus: SourceProcessingStatus.done,
              ),
          ]);
      });

      final result = await repository.sourcesOf([
        for (var i = 0; i < total; i++) 'f$i',
      ]);

      expect(result, hasLength(total));
      expect(ids(result).toSet(), hasLength(total));
    });
  });

  group('los conjuntos', () {
    test(
      'un espacio: sus fuentes, sin sus notas ni lo de otros espacios',
      () async {
        await db
            .into(db.spaces)
            .insert(
              SpacesCompanion.insert(
                id: 'historia',
                name: 'Historia',
                createdAt: capturedAt,
              ),
            );
        await source('a', spaceId: 'historia');
        await source('b', spaceId: 'historia');
        await source('fuera');
        await source('borrada', spaceId: 'historia');
        await note('nota');
        await writer.setSpace(['nota'], 'historia');
        await trash('borrada');

        final result = await repository.sourcesOfSpace('historia');

        expect(ids(result), unorderedEquals(['a', 'b']));
      },
    );

    test('una rama del Atlas: el tema y todo lo que cuelga de él', () async {
      await value('roma');
      await value('republica', parent: 'roma', depth: 1);
      await value('gracos', parent: 'republica', depth: 2);
      await value('grecia');
      await source('roma-1');
      await source('republica-1');
      await source('gracos-1');
      await source('grecia-1');
      await source('sin-tema');
      await assign('roma-1', 'roma');
      await assign('republica-1', 'republica');
      await assign('gracos-1', 'gracos');
      await assign('grecia-1', 'grecia');

      expect(
        ids(await repository.sourcesOfBranch('roma')),
        unorderedEquals(['roma-1', 'republica-1', 'gracos-1']),
      );
      expect(
        ids(await repository.sourcesOfBranch('republica')),
        unorderedEquals(['republica-1', 'gracos-1']),
      );
      expect(ids(await repository.sourcesOfBranch('grecia')), ['grecia-1']);
    });

    test('una fuente en dos temas de la rama entra una vez', () async {
      await value('roma');
      await value('republica', parent: 'roma', depth: 1);
      await source('doble');
      await assign('doble', 'roma');
      await assign('doble', 'republica');

      expect(ids(await repository.sourcesOfBranch('roma')), ['doble']);
    });

    test(
      'lo que muestra la Biblioteca: sus filtros, sin su orden ni su página',
      () async {
        await source('web-1');
        await source('web-2');
        await source('web-3');
        await source('video', kind: SourceKind.youtube);

        final webs = await repository.sourcesMatching(
          const LibraryQuery(
            sourceKinds: {SourceKind.webPage},
            sortBy: LibrarySort.title,
            limit: 1,
            offset: 1,
          ),
        );
        final all = await repository.sourcesMatching(const LibraryQuery());

        expect(ids(webs), unorderedEquals(['web-1', 'web-2', 'web-3']));
        expect(ids(all), hasLength(4));
      },
    );

    test('una selección: las fuentes que la componen', () async {
      await source('a');
      await source('b');
      await source('c');

      expect(ids(await repository.sourcesOf({'b', 'c'})), ['b', 'c']);
    });
  });

  group('lo que cita una nota', () {
    test('lo que extrajo, lo que dice citar y lo que enlaza', () async {
      await note('nota');
      await source('extraida');
      await source('citada');
      await source('enlazada');
      await source('relacionada');
      await source('ajena');
      await relate('nota', 'extraida', RelationKind.extractedFrom);
      await relate('nota', 'citada', RelationKind.cites);
      await relate('nota', 'relacionada', RelationKind.relatedTo);
      await link('nota', 'enlazada');

      final result = await repository.sourcesCitedBy('nota');

      expect(ids(result), unorderedEquals(['extraida', 'citada', 'enlazada']));
    });

    test(
      'un enlace roto, otra nota o lo que está en la papelera no cuentan',
      () async {
        await note('nota');
        await note('otra-nota');
        await source('borrada');
        await source('viva');
        await link('nota', null, title: 'Roto');
        await link('nota', 'otra-nota', title: 'Otra');
        await relate('nota', 'borrada', RelationKind.cites);
        await relate('nota', 'viva', RelationKind.cites);
        await trash('borrada');

        expect(ids(await repository.sourcesCitedBy('nota')), ['viva']);
      },
    );

    test('una fuente citada de dos maneras entra una vez', () async {
      await note('nota');
      await source('doble');
      await relate('nota', 'doble', RelationKind.extractedFrom);
      await relate('nota', 'doble', RelationKind.cites);
      await link('nota', 'doble');

      expect(ids(await repository.sourcesCitedBy('nota')), ['doble']);
    });

    test('lo que cita otra nota no es de esta', () async {
      await note('mia');
      await note('tuya');
      await source('de-tuya');
      await relate('tuya', 'de-tuya', RelationKind.cites);

      expect(await repository.sourcesCitedBy('mia'), isEmpty);
    });
  });

  group('de la base a la bibliografía', () {
    test('las fuentes de un espacio, ordenadas y formateadas en APA', () async {
      await db
          .into(db.spaces)
          .insert(
            SpacesCompanion.insert(
              id: 'tesis',
              name: 'Tesis',
              createdAt: capturedAt,
            ),
          );
      await source(
        'borges',
        title: 'El Aleph',
        spaceId: 'tesis',
        publishedAt: DateTime(1949),
      );
      await source(
        'garcia',
        title: 'Cien años de soledad',
        spaceId: 'tesis',
        publishedAt: DateTime(1967),
      );
      await source('web', title: 'Una página', spaceId: 'tesis');
      await writer.setReference(
        'borges',
        const ReferenceData(
          type: ReferenceType.book,
          publisher: 'Losada',
          publicationPrecision: PublicationPrecision.year,
          contributors: [
            Contributor(
              name: PersonName(family: 'Borges', given: 'Jorge Luis'),
            ),
          ],
        ),
      );
      await writer.setReference(
        'garcia',
        const ReferenceData(
          type: ReferenceType.book,
          publisher: 'Sudamericana',
          publicationPrecision: PublicationPrecision.year,
          contributors: [Contributor(name: garcia)],
        ),
      );

      final bibliography = buildBibliography(
        await repository.sourcesOfSpace('tesis'),
        style: const Apa7Style(),
      );

      expect(bibliography.title, 'Referencias');
      expect(
        bibliography.toPlainText(),
        'Borges, J. L. (1949). El Aleph. Losada.\n'
        'García Márquez, G. (1967). Cien años de soledad. Sudamericana.\n'
        // Una página web capturada sin enlace ni datos: se cita con lo que
        // hay y lo que falta queda a la vista.
        '[falta: autor]. ([falta: año]). Una página. [falta: enlace]',
      );
    });
  });
}
