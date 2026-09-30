import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/bulk_write_scope.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/database/person_vocabulary.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/services/reference_codec.dart';
import 'package:sinapsis/core/domain/services/reference_normalizer.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// El único lugar que escribe los campos de un elemento —`item`, su `note` y su
/// `source`— (F11).
///
/// Escribirlos desde varios lados dejaba tres cosas sin dueño: `rev` y
/// `deviceId` eran columnas fantasma, y no había cómo saber quién había
/// cambiado qué. Ahora cada modificación pasa por acá y hace lo mismo:
///
/// - sube `rev` y escribe el `deviceId` de esta instalación, **solo si algún
///   campo cambió de verdad**: un guardado que no cambia nada —el pipeline de
///   procesamiento guarda más de una vez el mismo elemento— no ensucia la
///   historia;
/// - y registra en `field_version` cada campo que cambió, con el linaje: sin
///   fila previa, la cadena de ediciones es propia (`base` nula); si la última
///   edición fue de este mismo dispositivo, se conserva su `base`; y si fue de
///   OTRO —una versión que llegó por una fusión—, esa versión pasa a ser la
///   `base` de la nueva. Es lo que le permite a una fusión decir «esta edición
///   partió de la tuya» en vez de marcar un conflicto.
///
/// Escribe también los datos bibliográficos de una fuente y sus personas
/// —`source_reference`, `source_contributor`— (F15): en la fusión de bóvedas y
/// en el linaje son UN campo, `reference`, y por eso los escribe quien versiona
/// los campos.
///
/// Un test recorre `lib` y falla si otro archivo escribe estas tablas.
class KnowledgeEntryWriter {
  KnowledgeEntryWriter(
    this._db, {
    Clock clock = DateTime.now,
    IdGenerator ids = const UuidV7Generator(),
  }) : _clock = clock,
       _ids = ids;

  final AppDatabase _db;
  final Clock _clock;

  /// De donde salen los ids de las personas que este escritor crea en el
  /// vocabulario al guardar una referencia.
  final IdGenerator _ids;

  /// Distinto de `null` durante [runBulk]: el último valor de cada (elemento,
  /// campo) tocado, todavía sin escribir en `field_version`. Vive en la
  /// instancia —no en la clase— porque cada repositorio crea un escritor
  /// nuevo por acceso; [runBulk] pasa ESTE escritor a su función para que
  /// las llamadas de adentro compartan el mismo lote.
  Map<String, Map<String, DateTime>>? _deferredTouches;

  String get _deviceId => _db.deviceId;

  /// Modo lote (F19, 19.2/19.4, decisión B): mientras [body] corre —recibe
  /// ESTE mismo escritor, ya en modo lote—, `_touch` no escribe cada
  /// `field_version` al toque: guarda en memoria el último valor por
  /// (elemento, campo) y lo vuelca en una sola escritura por campo al
  /// cerrar. Alrededor de todo, [withSuspendedSearchIndexes] (decisión A)
  /// suspende `item_search`, acotado a los elementos que de verdad
  /// cambiaron —los mismos que quedaron en el volcado de arriba, ya se
  /// sabe cuáles son sin otra consulta—, y NO suspende `chunk_search`: este
  /// escritor nunca escribe `chunks` (ver el doc comment de la clase), y
  /// suspenderlo para no usarlo solo pagaría el costo de un `rebuild` de
  /// FTS5 sobre la tabla entera de chunks sin ninguna razón. Medido en un
  /// lote real de miles de elementos: repoblar `item_search` completo por
  /// cada lote, por chico que fuera contra una bóveda grande, costaba más
  /// de lo que ahorraba suspender los triggers (F19, 19.4).
  ///
  /// La suspensión, el cuerpo del lote y el volcado final corren dentro de
  /// UNA transacción: un lote que falla a mitad de camino no deja ni
  /// índices ni `field_version` a medias, porque Drift deshace la
  /// transacción entera. Las claves foráneas y los invariantes de texto de
  /// fuente no dependen de ningún trigger que este método toque, así que
  /// siguen activos sin cambios durante todo el lote.
  ///
  /// No admite anidarse: un escritor ya en modo lote lanza si se lo llama
  /// de nuevo antes de terminar.
  Future<T> runBulk<T>(
    Future<T> Function(KnowledgeEntryWriter writer) body,
  ) async {
    if (_deferredTouches != null) {
      throw StateError('runBulk ya está activo en este escritor: no se anida.');
    }
    var touchedIds = const Iterable<String>.empty();
    return _db.transaction(() async {
      return withSuspendedSearchIndexes(
        _db,
        () async {
          _deferredTouches = {};
          try {
            return await body(this);
          } finally {
            final pending = _deferredTouches!;
            _deferredTouches = null;
            touchedIds = pending.keys.toList();
            for (final itemEntry in pending.entries) {
              for (final fieldEntry in itemEntry.value.entries) {
                await _touchNow(
                  itemEntry.key,
                  fieldEntry.key,
                  fieldEntry.value,
                );
              }
            }
          }
        },
        touchedItemIds: () => touchedIds,
        chunks: false,
      );
    });
  }

  /// Escribe el elemento [item]: la fila de `item` y, según sea, su `source` o
  /// su `note`. Lo único que se escribe del elemento en sí.
  ///
  /// `title`/`subtitle`/`notes`/`spaceId`/`updatedAt` y los campos
  /// estructurales de `source` se sobreescriben siempre: son un reflejo directo
  /// de [item]. `state` —y, para una nota, `noteKind`/`maturity`, y
  /// `contentHash` de una fuente— se preservan si ya existían: los escribe otra
  /// cosa (la Bandeja, `createRelation`, el chunking), nunca este método. Nunca
  /// toca `deletedAt`: borrar y restaurar tienen sus propias operaciones.
  ///
  /// [changedRenditions] son los ids de las formas cuyo texto —o archivo— este
  /// guardado crea o cambia. El texto en sí lo escribe quien guarda las formas
  /// (que es también quien puede compararlo con lo que había): acá solo se
  /// versiona, para que el `rev` suba UNA vez por guardado y no una por forma.
  Future<void> upsert(
    KnowledgeItem item, {
    Iterable<String> changedRenditions = const [],
  }) async {
    await _db.transaction(() async {
      final now = _clock();
      final existing = await (_db.select(
        _db.knowledgeEntries,
      )..where((e) => e.id.equals(item.id))).getSingleOrNull();
      final existingSource = await (_db.select(
        _db.knowledgeSources,
      )..where((s) => s.itemId.equals(item.id))).getSingleOrNull();

      final kind = itemKindFor(item.source.kind);
      final state = nextMirrorState(
        current: existing?.state,
        processingState: item.processingState,
        sourceKind: item.source.kind,
      );

      // Lo que cambió, por campo. Contra «nada» —un elemento nuevo— cambia todo
      // lo que tiene un valor: crearlo es la primera versión de cada campo.
      final changed = <String>[
        if (existing?.title != item.title) EntryField.title,
        if (existing?.subtitle != item.subtitle) EntryField.subtitle,
        if (existing?.notes != item.notes) EntryField.notes,
        if (existing?.spaceId != item.spaceId) EntryField.spaceId,
        if (existing?.state != state) EntryField.state,
        ..._changedSourceFields(item, existingSource),
        for (final id in changedRenditions) EntryField.rendition(id),
      ];

      if (existing == null) {
        await _db
            .into(_db.knowledgeEntries)
            .insert(
              KnowledgeEntriesCompanion.insert(
                id: item.id,
                title: item.title,
                subtitle: Value(item.subtitle),
                notes: Value(item.notes),
                spaceId: Value(item.spaceId),
                kind: kind,
                state: state,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                deviceId: _deviceId,
              ),
            );
      } else {
        await (_db.update(
          _db.knowledgeEntries,
        )..where((e) => e.id.equals(item.id))).write(
          KnowledgeEntriesCompanion(
            title: Value(item.title),
            subtitle: Value(item.subtitle),
            notes: Value(item.notes),
            spaceId: Value(item.spaceId),
            kind: Value(kind),
            state: Value(state),
            createdAt: Value(item.createdAt),
            updatedAt: Value(item.updatedAt),
            // Solo si algo cambió: ver la documentación de la clase.
            rev: changed.isEmpty
                ? const Value.absent()
                : Value(existing.rev + 1),
            deviceId: changed.isEmpty ? const Value.absent() : Value(_deviceId),
          ),
        );
      }

      await _writeTypedRow(item, kind, existingSource);
      for (final field in changed) {
        await _touch(item.id, field, now);
      }
    });
  }

  /// Guarda los datos bibliográficos y las personas de la fuente [itemId]
  /// (F15). Devuelve `false`, sin tocar nada, si el elemento no existe o no es
  /// una fuente: una nota no tiene editorial ni DOI.
  ///
  /// [reference] reemplaza a lo que había —para BORRAR un dato hay que
  /// mandarlo vacío—. Antes se la limpia (`normalizeReference`): los textos
  /// recortados, los identificadores normalizados y los inválidos fuera. Las
  /// personas se resuelven contra el vocabulario de autores
  /// (`PersonVocabulary`): una que no existe se crea, y dos obras de la misma
  /// persona comparten UN valor.
  ///
  /// Es UN campo de linaje, [EntryField.reference]: sube el `rev` y registra la
  /// versión una vez, y **solo si algo cambió** —guardar lo mismo no ensucia la
  /// historia—. Lo que sí hace siempre es dejar el espejo de las personas al
  /// día en `item_property_values`, para que un espejo que alguien tocó a mano
  /// se cure solo.
  Future<bool> setReference(String itemId, ReferenceData reference) async {
    final wanted = normalizeReference(reference);
    return _db.transaction(() async {
      final entry = await _entry(itemId);
      if (entry == null || entry.kind != ItemKind.source) return false;

      final people = PersonVocabulary(_db, ids: _ids, clock: _clock);
      final contributors = <Contributor>[];
      final seen = <String>{};
      for (final contributor in wanted.contributors) {
        final personId = await people.resolve(contributor);
        // Sin persona que resolver, o dos formas de escribir la misma con el
        // mismo rol: una sola vez.
        if (personId == null) continue;
        if (!seen.add('${contributor.role.name}|$personId')) continue;
        contributors.add(contributor.copyWith(personId: personId));
      }
      final resolved = wanted.copyWith(contributors: contributors);

      final before = await ReferenceReader(_db).read(itemId);
      if (!_sameReference(before, resolved)) {
        await _writeReference(itemId, resolved);
        await _bumpEntry(itemId);
        await _touch(itemId, EntryField.reference, _clock());
      }
      await _mirrorContributors(itemId, contributors);
      return true;
    });
  }

  /// Pasa las obras de la persona [discardId] a [keepId] (F15), como las
  /// asignaciones al fusionar dos valores: si una obra ya nombraba a [keepId]
  /// con el mismo rol, la de [discardId] sobra y se borra; el resto cambia de
  /// persona conservando su rol y su lugar. Devuelve lo que hace falta para
  /// deshacerlo con [restoreContributors].
  ///
  /// La referencia de cada obra tocada queda anotada como editada
  /// ([touchReferences]): pasó a nombrar a otra persona, y una fusión de
  /// bóvedas tiene que verlo como una edición. Es lo que escribe cuando una
  /// operación del vocabulario cambia las personas de una obra, y por eso vive
  /// acá y no en el motor de fusión de valores: las escrituras de estas tablas
  /// pasan todas por este archivo.
  Future<
    ({List<SourceContributorRow> moved, List<SourceContributorRow> dropped})
  >
  repointContributors({required String keepId, required String discardId}) {
    return _db.transaction(() async {
      final rows = await (_db.select(
        _db.sourceContributors,
      )..where((c) => c.propertyValueId.equals(discardId))).get();
      final moved = <SourceContributorRow>[];
      final dropped = <SourceContributorRow>[];
      for (final row in rows) {
        final alreadyHasKeep =
            await (_db.select(_db.sourceContributors)..where(
                  (c) =>
                      c.itemId.equals(row.itemId) &
                      c.propertyValueId.equals(keepId) &
                      c.role.equalsValue(row.role),
                ))
                .getSingleOrNull();
        if (alreadyHasKeep != null) {
          dropped.add(row);
          await (_db.delete(_db.sourceContributors)..where(
                (c) =>
                    c.itemId.equals(row.itemId) &
                    c.propertyValueId.equals(discardId) &
                    c.role.equalsValue(row.role),
              ))
              .go();
        } else {
          moved.add(row);
        }
      }
      await (_db.update(_db.sourceContributors)
            ..where((c) => c.propertyValueId.equals(discardId)))
          .write(SourceContributorsCompanion(propertyValueId: Value(keepId)));
      await touchReferences([
        for (final row in [...moved, ...dropped]) row.itemId,
      ]);
      return (moved: moved, dropped: dropped);
    });
  }

  /// Deshace [repointContributors]: las obras [moved] vuelven a nombrar a
  /// [discardId] y las [dropped] —que sobraban— a estar. Lanza
  /// [ContributorRestoreConflict], sin dejar nada a medias, si alguien las
  /// cambió desde entonces: una obra ya no nombra a [keepId] con ese rol, o el
  /// lugar que dejó una de las que sobraban ya lo ocupa otra persona.
  ///
  /// [discardId] tiene que existir otra vez: la clave lo exige.
  Future<void> restoreContributors({
    required String keepId,
    required String discardId,
    required List<SourceContributorRow> moved,
    required List<SourceContributorRow> dropped,
  }) async {
    if (moved.isEmpty && dropped.isEmpty) return;
    await _db.transaction(() async {
      for (final row in moved) {
        final stillThere =
            await (_db.select(_db.sourceContributors)..where(
                  (c) =>
                      c.itemId.equals(row.itemId) &
                      c.propertyValueId.equals(keepId) &
                      c.role.equalsValue(row.role),
                ))
                .getSingleOrNull();
        if (stillThere == null) {
          throw const ContributorRestoreConflict(
            'Una obra ya no nombra a la persona en la que se fusionó.',
          );
        }
      }
      for (final row in dropped) {
        final placeTaken =
            await (_db.select(_db.sourceContributors)..where(
                  (c) =>
                      c.itemId.equals(row.itemId) &
                      c.position.equals(row.position),
                ))
                .getSingleOrNull();
        if (placeTaken != null) {
          throw const ContributorRestoreConflict(
            'Una obra cambió sus personas: no se puede volver a como estaban.',
          );
        }
      }

      for (final row in moved) {
        await (_db.update(_db.sourceContributors)..where(
              (c) =>
                  c.itemId.equals(row.itemId) &
                  c.propertyValueId.equals(keepId) &
                  c.role.equalsValue(row.role),
            ))
            .write(
              SourceContributorsCompanion(propertyValueId: Value(discardId)),
            );
      }
      for (final row in dropped) {
        await _db.into(_db.sourceContributors).insert(row);
      }
      await touchReferences([
        for (final row in [...moved, ...dropped]) row.itemId,
      ]);
    });
  }

  /// Anota que la referencia de cada una de [itemIds] cambió SIN pasar por
  /// [setReference]: sube su `rev` y renueva la versión del campo, una vez cada
  /// una. Los elementos que no existen o no son fuentes se saltean.
  ///
  /// Es lo que corresponde cuando una operación del vocabulario cambia las
  /// personas de una obra —fusionar dos autores, o deshacerlo—: la obra pasa a
  /// nombrar a otra persona, y una fusión de bóvedas tiene que verlo como una
  /// edición de la referencia y no como algo que estaba así desde siempre.
  Future<void> touchReferences(Iterable<String> itemIds) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return;
    await _db.transaction(() async {
      final now = _clock();
      for (var start = 0; start < ids.length; start += _idsPerQuery) {
        final slice = ids.skip(start).take(_idsPerQuery).toList();
        final rows =
            await (_db.select(_db.knowledgeEntries)..where(
                  (e) => e.id.isIn(slice) & e.kind.equalsValue(ItemKind.source),
                ))
                .get();
        for (final row in rows) {
          await _bumpEntry(row.id);
          await _touch(row.id, EntryField.reference, now);
        }
      }
    });
  }

  /// Si [a] y [b] dicen lo mismo: los mismos datos y las mismas personas, con
  /// el mismo rol y en el mismo orden. Del nombre de cada persona no importa
  /// cómo llegó escrito —lo que vale es el valor del vocabulario que la
  /// representa—.
  bool _sameReference(ReferenceData a, ReferenceData b) {
    if (a.copyWith(contributors: const []) !=
        b.copyWith(contributors: const [])) {
      return false;
    }
    if (a.contributors.length != b.contributors.length) return false;
    for (var i = 0; i < a.contributors.length; i++) {
      if (a.contributors[i].personId != b.contributors[i].personId ||
          a.contributors[i].role != b.contributors[i].role) {
        return false;
      }
    }
    return true;
  }

  /// Escribe [data] —con las personas ya resueltas— en lugar de lo que había.
  /// Una referencia sin ningún dato borra su fila en vez de guardar una vacía.
  Future<void> _writeReference(String itemId, ReferenceData data) async {
    await (_db.delete(
      _db.sourceContributors,
    )..where((c) => c.itemId.equals(itemId))).go();
    if (data.isEmpty) {
      await (_db.delete(
        _db.sourceReferences,
      )..where((r) => r.itemId.equals(itemId))).go();
      return;
    }

    await _db
        .into(_db.sourceReferences)
        .insertOnConflictUpdate(
          SourceReferencesCompanion.insert(
            itemId: itemId,
            referenceType: Value(data.type),
            containerTitle: Value(data.containerTitle),
            publisher: Value(data.publisher),
            publisherPlace: Value(data.publisherPlace),
            edition: Value(data.edition),
            volume: Value(data.volume),
            issue: Value(data.issue),
            pages: Value(data.pages),
            isbn: Value(data.isbn),
            issn: Value(data.issn),
            doi: Value(data.doi),
            accessedAt: Value(data.accessedAt),
            citationKey: Value(data.citationKey),
            publicationPrecision: Value(data.publicationPrecision),
          ),
        );
    for (final (position, contributor) in data.contributors.indexed) {
      await _db
          .into(_db.sourceContributors)
          .insert(
            SourceContributorsCompanion.insert(
              itemId: itemId,
              // Ya resuelta: ver `setReference`.
              propertyValueId: contributor.personId!,
              role: contributor.role,
              position: position,
            ),
          );
    }
  }

  /// Deja en `item_property_values` a las personas de [contributors] y solo a
  /// ellas **entre las que puso este espejo** (`ItemPropertyOrigin.reference`).
  ///
  /// Se sincroniza por diferencia, como las etiquetas de la Biblioteca: una
  /// asignación `manual` de la misma persona —alguien la puso desde el editor
  /// de propiedades, o ya estaba en una categoría «Autor» de antes— no se toca
  /// ni se degrada, y no se borra cuando la persona sale de la obra.
  Future<void> _mirrorContributors(
    String itemId,
    List<Contributor> contributors,
  ) async {
    final wanted = {for (final c in contributors) c.personId!};

    final mirrored =
        (await (_db.select(_db.itemPropertyValues)..where(
                  (a) =>
                      a.itemId.equals(itemId) &
                      a.origin.equalsValue(ItemPropertyOrigin.reference),
                ))
                .get())
            .map((a) => a.propertyValueId)
            .toSet();

    final stale = mirrored.difference(wanted);
    if (stale.isNotEmpty) {
      await (_db.delete(_db.itemPropertyValues)..where(
            (a) =>
                a.itemId.equals(itemId) &
                a.origin.equalsValue(ItemPropertyOrigin.reference) &
                a.propertyValueId.isIn(stale),
          ))
          .go();
    }

    final present = wanted.isEmpty
        ? <String>{}
        : (await (_db.select(_db.itemPropertyValues)..where(
                    (a) =>
                        a.itemId.equals(itemId) &
                        a.propertyValueId.isIn(wanted),
                  ))
                  .get())
              .map((a) => a.propertyValueId)
              .toSet();
    for (final personId in wanted.difference(present)) {
      await _db
          .into(_db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: itemId,
              propertyValueId: personId,
              origin: const Value(ItemPropertyOrigin.reference),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  /// Cambia el espacio de [itemIds]. Solo los que de verdad lo cambian suben su
  /// `rev` y registran la versión.
  Future<void> setSpace(Iterable<String> itemIds, String? spaceId) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return;
    await _db.transaction(() async {
      final now = _clock();
      for (var start = 0; start < ids.length; start += _idsPerQuery) {
        final slice = ids.skip(start).take(_idsPerQuery).toList();
        final rows = await (_db.select(
          _db.knowledgeEntries,
        )..where((e) => e.id.isIn(slice))).get();
        final changing = [
          for (final row in rows)
            if (row.spaceId != spaceId) row,
        ];
        for (final row in changing) {
          await _writeEntry(
            row,
            KnowledgeEntriesCompanion(spaceId: Value(spaceId)),
          );
          await _touch(row.id, EntryField.spaceId, now);
        }
      }
    });
  }

  /// Cambia el estado de trabajo intelectual de [itemId]. Devuelve `false` si
  /// el elemento no existe.
  Future<bool> setState(String itemId, ItemState to) async {
    return _db.transaction(() async {
      final row = await _entry(itemId);
      if (row == null) return false;
      if (row.state == to) return true;
      await _writeEntry(row, KnowledgeEntriesCompanion(state: Value(to)));
      await _touch(itemId, EntryField.state, _clock());
      return true;
    });
  }

  /// Cambia el subtipo de la nota [itemId]. Devuelve `false` si no existe.
  Future<bool> setNoteKind(String itemId, NoteKind kind) async {
    return _db.transaction(() async {
      final note = await (_db.select(
        _db.knowledgeNotes,
      )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
      if (note == null) return false;
      if (note.noteKind == kind) return true;
      await (_db.update(_db.knowledgeNotes)
            ..where((n) => n.itemId.equals(itemId)))
          .write(KnowledgeNotesCompanion(noteKind: Value(kind)));
      await _bumpEntry(itemId);
      await _touch(itemId, EntryField.noteKind, _clock());
      return true;
    });
  }

  /// Cambia la madurez de la nota [itemId]. Devuelve `false` si no existe.
  Future<bool> setMaturity(String itemId, NoteMaturity maturity) async {
    return _db.transaction(() async {
      final note = await (_db.select(
        _db.knowledgeNotes,
      )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
      if (note == null) return false;
      if (note.maturity == maturity) return true;
      await (_db.update(_db.knowledgeNotes)
            ..where((n) => n.itemId.equals(itemId)))
          .write(KnowledgeNotesCompanion(maturity: Value(maturity)));
      await _bumpEntry(itemId);
      await _touch(itemId, EntryField.maturity, _clock());
      return true;
    });
  }

  /// Marca [itemId] como generada por [model] (F16, D3): una sola vez, al
  /// nacer como derivado. Devuelve `false` si el elemento no existe o si ya
  /// estaba marcado —la propia tabla documenta que esto «no se toca
  /// después»—.
  ///
  /// Aparte de [setNoteKind]/[setMaturity] en que NO pasa por
  /// [EntryField]/[_touch]: esos dos son valores que el usuario elige y
  /// puede cambiar de nuevo desde una pantalla, así que necesitan
  /// versionarse para que una fusión sepa distinguir «lo cambié yo» de «lo
  /// cambió el otro». Esto se escribe una sola vez, nunca desde una
  /// interfaz que el usuario controle —mismo criterio que `dedupHash`/
  /// `simhash`, calculados una vez y nunca versionados—.
  Future<bool> markGenerated(
    String itemId, {
    required String model,
    required DateTime at,
  }) async {
    return _db.transaction(() async {
      final note = await (_db.select(
        _db.knowledgeNotes,
      )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
      if (note == null || note.generatedByModel != null) return false;
      await (_db.update(
        _db.knowledgeNotes,
      )..where((n) => n.itemId.equals(itemId))).write(
        KnowledgeNotesCompanion(
          generatedByModel: Value(model),
          generatedAt: Value(at),
        ),
      );
      await _bumpEntry(itemId);
      return true;
    });
  }

  /// Marca que el usuario ya tocó el contenido de la nota generada
  /// [itemId] (F16, D3): «pasa a ser suya». De falso a verdadero una sola
  /// vez, sin vuelta atrás. Devuelve `false` si el elemento no existe, no es
  /// una nota generada —`generatedByModel` nulo: «siempre en falso para una
  /// nota que no es un derivado», tal como documenta la propia tabla— o ya
  /// estaba marcado. Mismo motivo que [markGenerated] para no pasar por
  /// [EntryField]/[_touch]: no hay ninguna pantalla donde el usuario elija
  /// este valor a mano, es un efecto de editar el contenido, no un campo
  /// propio.
  Future<bool> markDerivedEdited(String itemId) async {
    return _db.transaction(() async {
      final note = await (_db.select(
        _db.knowledgeNotes,
      )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
      if (note == null || note.generatedByModel == null || note.derivedEdited) {
        return false;
      }
      await (_db.update(_db.knowledgeNotes)
            ..where((n) => n.itemId.equals(itemId)))
          .write(const KnowledgeNotesCompanion(derivedEdited: Value(true)));
      await _bumpEntry(itemId);
      return true;
    });
  }

  /// Cambia el subtítulo y/o las notas libres de [itemId]; lo que no se pasa
  /// no se toca. Devuelve `false` si el elemento no existe.
  ///
  /// Aparte de [upsert] porque quien lo necesita —la fusión de duplicados, que
  /// junta lo que el usuario escribió en los dos— no tiene un `KnowledgeItem`
  /// armado ni tiene por qué volver a escribir sus formas.
  Future<bool> setFreeText(
    String itemId, {
    Value<String?> subtitle = const Value.absent(),
    Value<String?> notes = const Value.absent(),
  }) async {
    return _db.transaction(() async {
      final row = await _entry(itemId);
      if (row == null) return false;
      final changed = [
        if (subtitle.present && row.subtitle != subtitle.value)
          EntryField.subtitle,
        if (notes.present && row.notes != notes.value) EntryField.notes,
      ];
      if (changed.isEmpty) return true;
      final now = _clock();
      await _writeEntry(
        row,
        KnowledgeEntriesCompanion(
          subtitle: subtitle,
          notes: notes,
          updatedAt: Value(now),
        ),
      );
      for (final field in changed) {
        await _touch(itemId, field, now);
      }
      return true;
    });
  }

  /// Manda a la papelera los elementos VIVOS de [itemIds]: les pone
  /// `deletedAt`. Devuelve los que de verdad se mandaron —uno que no existe o
  /// que ya estaba en la papelera no cuenta, y no cambia su fecha—.
  ///
  /// No se borra nada: ni la fila, ni el texto, ni lo que cuelga del elemento,
  /// ni el archivo original. Sube el `rev`, escribe el dispositivo y versiona
  /// `deletedAt`, como cualquier otro cambio: una fusión tiene que poder
  /// distinguir «lo borró el otro» de «lo edité yo».
  Future<List<String>> trash(Iterable<String> itemIds) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return const [];
    return _db.transaction(() async {
      final now = _clock();
      final trashed = <String>[];
      for (var start = 0; start < ids.length; start += _idsPerQuery) {
        final slice = ids.skip(start).take(_idsPerQuery).toList();
        final rows = await (_db.select(
          _db.knowledgeEntries,
        )..where((e) => e.id.isIn(slice) & e.deletedAt.isNull())).get();
        for (final row in rows) {
          await _writeEntry(
            row,
            KnowledgeEntriesCompanion(deletedAt: Value(now)),
          );
          await _touch(row.id, EntryField.deletedAt, now);
          trashed.add(row.id);
        }
      }
      return trashed;
    });
  }

  /// Saca de la papelera los elementos de [itemIds] que están en ella: les
  /// quita `deletedAt`. Devuelve los que de verdad se restauraron.
  Future<List<String>> restore(Iterable<String> itemIds) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return const [];
    return _db.transaction(() async {
      final now = _clock();
      final restored = <String>[];
      for (var start = 0; start < ids.length; start += _idsPerQuery) {
        final slice = ids.skip(start).take(_idsPerQuery).toList();
        final rows = await (_db.select(
          _db.knowledgeEntries,
        )..where((e) => e.id.isIn(slice) & e.deletedAt.isNotNull())).get();
        for (final row in rows) {
          await _writeEntry(
            row,
            const KnowledgeEntriesCompanion(deletedAt: Value(null)),
          );
          await _touch(row.id, EntryField.deletedAt, now);
          restored.add(row.id);
        }
      }
      return restored;
    });
  }

  /// Pone el campo [field] de [itemId] en [value], que llega como TEXTO: así
  /// lo guarda un conflicto de fusión, sea cual sea el campo (F11).
  ///
  /// Los enumerados llegan por su nombre, las fechas como segundos desde 1970 y
  /// un espacio por su identificador. Es una modificación como cualquier otra:
  /// sube el `rev`, escribe el dispositivo de acá y registra la versión del
  /// campo, así que una fusión posterior la ve como lo que es —una edición
  /// nueva— y no como el conflicto de antes.
  ///
  /// Devuelve `false`, sin tocar nada, si el elemento no existe, si [field] no
  /// es uno de los campos versionados o si [value] no sirve para él (un nombre
  /// de enumerado que no existe, un título vacío).
  Future<bool> setFieldFromText(
    String itemId,
    String field,
    String? value,
  ) async {
    switch (field) {
      case EntryField.title:
        return _setTitle(itemId, value);
      case EntryField.subtitle:
        return setFreeText(itemId, subtitle: Value(value));
      case EntryField.notes:
        return setFreeText(itemId, notes: Value(value));
      case EntryField.spaceId:
        if (await _entry(itemId) == null) return false;
        await setSpace([itemId], value);
        return true;
      case EntryField.state:
        final to = ItemState.values.asNameMap()[value];
        return to == null ? false : setState(itemId, to);
      case EntryField.deletedAt:
        if (await _entry(itemId) == null) return false;
        if (value == null) {
          await restore([itemId]);
        } else {
          await trash([itemId]);
        }
        return true;
      case EntryField.noteKind:
        final to = NoteKind.values.asNameMap()[value];
        return to == null ? false : setNoteKind(itemId, to);
      case EntryField.maturity:
        final to = NoteMaturity.values.asNameMap()[value];
        return to == null ? false : setMaturity(itemId, to);
      case EntryField.reference:
        // La referencia entera, como la guarda un conflicto de fusión
        // (`encodeReference`); sin texto, es «esta versión no tenía ninguna».
        if (value == null) return setReference(itemId, const ReferenceData());
        final reference = decodeReference(value);
        return reference == null ? false : setReference(itemId, reference);
      case EntryField.originUrl:
      case EntryField.authorName:
      case EntryField.authorUrl:
      case EntryField.originalBlobPath:
      case EntryField.language:
        return _setSourceText(itemId, field, value);
      case EntryField.publishedAt:
        final seconds = value == null ? null : int.tryParse(value);
        if (value != null && seconds == null) return false;
        return _setSourceDate(
          itemId,
          seconds == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
        );
    }
    return false;
  }

  Future<bool> _setTitle(String itemId, String? title) async {
    if (title == null || title.trim().isEmpty) return false;
    return _db.transaction(() async {
      final row = await _entry(itemId);
      if (row == null) return false;
      if (row.title == title) return true;
      final now = _clock();
      await _writeEntry(
        row,
        KnowledgeEntriesCompanion(title: Value(title), updatedAt: Value(now)),
      );
      await _touch(itemId, EntryField.title, now);
      return true;
    });
  }

  Future<bool> _setSourceText(String itemId, String field, String? text) {
    return _setSource(itemId, field, (source) {
      final current = switch (field) {
        EntryField.originUrl => source.originUrl,
        EntryField.authorName => source.authorName,
        EntryField.authorUrl => source.authorUrl,
        EntryField.language => source.language,
        _ => source.originalBlobPath,
      };
      if (current == text) return null;
      return switch (field) {
        EntryField.originUrl => KnowledgeSourcesCompanion(
          originUrl: Value(text),
        ),
        EntryField.authorName => KnowledgeSourcesCompanion(
          authorName: Value(text),
        ),
        EntryField.authorUrl => KnowledgeSourcesCompanion(
          authorUrl: Value(text),
        ),
        EntryField.language => KnowledgeSourcesCompanion(language: Value(text)),
        _ => KnowledgeSourcesCompanion(originalBlobPath: Value(text)),
      };
    });
  }

  Future<bool> _setSourceDate(String itemId, DateTime? date) {
    return _setSource(itemId, EntryField.publishedAt, (source) {
      if (source.publishedAt == date) return null;
      return KnowledgeSourcesCompanion(publishedAt: Value(date));
    });
  }

  /// Aplica el cambio que [change] decide sobre la fila de `source` de
  /// [itemId] —`null` si no hay nada que cambiar— y lo versiona.
  Future<bool> _setSource(
    String itemId,
    String field,
    KnowledgeSourcesCompanion? Function(KnowledgeSourceRow source) change,
  ) async {
    return _db.transaction(() async {
      final source = await (_db.select(
        _db.knowledgeSources,
      )..where((s) => s.itemId.equals(itemId))).getSingleOrNull();
      if (source == null) return false;
      final companion = change(source);
      if (companion == null) return true;
      await (_db.update(
        _db.knowledgeSources,
      )..where((s) => s.itemId.equals(itemId))).write(companion);
      await _bumpEntry(itemId);
      await _touch(itemId, field, _clock());
      return true;
    });
  }

  /// Borra [itemId] de la base, para siempre: la fila de `item` y, por las
  /// cascadas del esquema, todo lo que cuelga de ella —su fuente o nota, sus
  /// formas, subrayados, chunks, vínculos, tarjetas y versiones por campo—.
  ///
  /// SOLO si ya está en la papelera: es lo único que borra un elemento de
  /// verdad, y lo hace únicamente cuando el usuario lo pide sobre algo que ya
  /// había borrado. Devuelve `false` —y no toca nada— si el elemento no existe
  /// o sigue vivo.
  ///
  /// El archivo original en el disco NO se toca: el disco no tiene cascadas, y
  /// decidir si otro elemento todavía lo usa es cosa de quien llama.
  Future<bool> purge(String itemId) async {
    final removed = await (_db.delete(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(itemId) & e.deletedAt.isNotNull())).go();
    return removed > 0;
  }

  // ---------------------------------------------------------------------

  /// Cuántos ids entran en una sola consulta: por debajo del tope de parámetros
  /// de SQLite.
  static const _idsPerQuery = 400;

  Future<KnowledgeEntryRow?> _entry(String itemId) => (_db.select(
    _db.knowledgeEntries,
  )..where((e) => e.id.equals(itemId))).getSingleOrNull();

  /// Escribe [change] sobre [row] y sube su `rev` con el `deviceId` de acá.
  Future<void> _writeEntry(
    KnowledgeEntryRow row,
    KnowledgeEntriesCompanion change,
  ) => (_db.update(_db.knowledgeEntries)..where((e) => e.id.equals(row.id)))
      .write(
        change.copyWith(rev: Value(row.rev + 1), deviceId: Value(_deviceId)),
      );

  /// Sube el `rev` de [itemId] cuando lo que cambió no está en `item` sino en
  /// `note` o en una forma.
  Future<void> _bumpEntry(String itemId) async {
    final row = await _entry(itemId);
    if (row == null) return;
    await _writeEntry(row, const KnowledgeEntriesCompanion());
  }

  /// Los campos de `source` que cambian con [item]. Sin fila previa cambia cada
  /// metadato que tiene un valor.
  List<String> _changedSourceFields(
    KnowledgeItem item,
    KnowledgeSourceRow? existing,
  ) {
    if (itemKindFor(item.source.kind) == ItemKind.note) return const [];
    final source = item.source;
    return [
      if (existing?.originUrl != source.url) EntryField.originUrl,
      if (existing?.authorName != source.authorName) EntryField.authorName,
      if (existing?.authorUrl != source.authorUrl) EntryField.authorUrl,
      if (existing?.publishedAt != source.publishedAt) EntryField.publishedAt,
      if (existing?.originalBlobPath != source.originalFilePath)
        EntryField.originalBlobPath,
      if (existing?.language != source.language) EntryField.language,
    ];
  }

  /// La fila de `note` —con sus valores de partida— o la de `source`.
  Future<void> _writeTypedRow(
    KnowledgeItem item,
    ItemKind kind,
    KnowledgeSourceRow? existingSource,
  ) async {
    if (kind == ItemKind.note) {
      await _db
          .into(_db.knowledgeNotes)
          .insert(
            KnowledgeNotesCompanion.insert(
              itemId: item.id,
              noteKind: NoteKind.living,
              maturity: NoteMaturity.seed,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      return;
    }

    await _db
        .into(_db.knowledgeSources)
        .insertOnConflictUpdate(
          KnowledgeSourcesCompanion.insert(
            itemId: item.id,
            sourceType: item.source.kind,
            originUrl: Value(item.source.url),
            authorName: Value(item.source.authorName),
            authorUrl: Value(item.source.authorUrl),
            publishedAt: Value(item.source.publishedAt),
            capturedAt: item.source.capturedAt,
            originalBlobPath: Value(item.source.originalFilePath),
            language: Value(item.source.language),
            contentHash: existingSource?.contentHash ?? '',
            processingStatus: sourceProcessingStatusFor(item.processingState),
          ),
        );
  }

  /// Registra que [field] de [itemId] cambió ahora, en este dispositivo. En
  /// modo lote ([runBulk]) no escribe nada: guarda el valor en memoria, y
  /// [runBulk] lo vuelca —una vez por (elemento, campo)— al cerrar.
  Future<void> _touch(String itemId, String field, DateTime now) async {
    final deferred = _deferredTouches;
    if (deferred != null) {
      (deferred[itemId] ??= {})[field] = now;
      return;
    }
    await _touchNow(itemId, field, now);
  }

  Future<void> _touchNow(String itemId, String field, DateTime now) async {
    final previous =
        await (_db.select(_db.fieldVersions)..where(
              (f) => f.itemId.equals(itemId) & f.fieldName.equals(field),
            ))
            .getSingleOrNull();

    // El linaje: qué versión ajena parte esta edición.
    final DateTime? baseAt;
    final String? baseDevice;
    if (previous == null) {
      baseAt = null;
      baseDevice = null;
    } else if (previous.deviceId == _deviceId) {
      baseAt = previous.baseUpdatedAt;
      baseDevice = previous.baseDeviceId;
    } else {
      baseAt = previous.updatedAt;
      baseDevice = previous.deviceId;
    }

    await _db
        .into(_db.fieldVersions)
        .insertOnConflictUpdate(
          FieldVersionsCompanion.insert(
            itemId: itemId,
            fieldName: field,
            updatedAt: now,
            deviceId: _deviceId,
            baseUpdatedAt: Value(baseAt),
            baseDeviceId: Value(baseDevice),
          ),
        );
  }
}

/// Por qué [KnowledgeEntryWriter.restoreContributors] no pudo devolver las
/// obras a la persona que las tenía: lo que la fusión dejó ya no está como
/// estaba.
class ContributorRestoreConflict implements Exception {
  const ContributorRestoreConflict(this.message);

  final String message;

  @override
  String toString() => 'ContributorRestoreConflict: $message';
}
