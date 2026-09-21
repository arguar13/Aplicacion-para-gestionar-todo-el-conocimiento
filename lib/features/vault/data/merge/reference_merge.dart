import 'dart:convert';

import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_row_mapping.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/services/reference_codec.dart';
import 'package:sinapsis/features/vault/data/merge/entry_merge_planner.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_fields.dart';
import 'package:sinapsis/features/vault/data/merge/stamp_rows.dart';
import 'package:sinapsis/features/vault/domain/merge/field_merge_rule.dart';

/// Decide qué versión de los datos bibliográficos de una fuente queda al
/// fusionar la copia de otra bóveda con esta (F15).
///
/// Los datos de una referencia y sus personas son UN campo de linaje
/// ([MergeField.isComposite]): se decide con la misma [FieldMergeRule] que el
/// título o las notas, y la vista previa y la fusión la usan las dos. Lo que
/// cambia es cómo se sabe si son distintos y qué texto se guarda de la versión
/// que no queda en vivo.
///
/// **Las personas se comparan por identidad, no por identificador.** Un valor
/// del vocabulario es el mismo en las dos bóvedas si tiene el mismo
/// identificador —aunque alguien lo haya renombrado en una— o, si no, la misma
/// etiqueta dentro de la misma categoría: es exactamente la regla con que
/// `VocabularyMerge` los une, escrita acá como SQL para que no haga falta que
/// el vocabulario ya esté fusionado. Así renombrar a una autora en una bóveda
/// no hace que todas sus obras parezcan cambiadas.
///
/// Solo mira las fuentes que las dos bóvedas tienen y que tienen algo de esto
/// en alguna: una copia casi igual se planifica leyendo casi nada.
class ReferenceMergePlanner {
  const ReferenceMergePlanner(this._db);

  final AppDatabase _db;

  static const _incoming = kIncomingSchema;

  /// Cuántos elementos se leen por consulta: por debajo del tope de parámetros
  /// de SQLite.
  static const _itemsPerQuery = 400;

  /// Quién es, en esta bóveda, la persona `v` de la copia: la de su mismo
  /// identificador, o la de su misma etiqueta en la categoría del mismo nombre,
  /// o —si acá no existe— una marca propia. Lo mismo que
  /// `VocabularyMerge._mapValues`.
  static const _incomingIdentity =
      '''
    COALESCE(
      (SELECT l.id FROM main.property_values l WHERE l.id = v.id),
      (SELECT l.id
         FROM main.property_values l
         JOIN main.property_definitions ld ON ld.id = l.definition_id
         JOIN $_incoming.property_definitions d
           ON d.id = v.definition_id AND d.name = ld.name COLLATE NOCASE
        WHERE l.value = v.value COLLATE NOCASE
        LIMIT 1),
      'incoming:' || v.id)''';

  /// Los cambios de [field] en las fuentes comunes, ya decididos: solo las
  /// que las dos bóvedas tienen distintas.
  Future<List<FieldChange>> differing(MergeField field) async {
    final candidates = await _db.customSelect('''
      SELECT m.id AS item_id,
             ${StampRows.columns(localVersion: 'lf', incomingVersion: 'inf', localItem: 'm', incomingItem: 'i')}
        FROM main.item m
        JOIN $_incoming.item i ON i.id = m.id
        LEFT JOIN main.field_version lf
               ON lf.item_id = m.id AND lf.field_name = '${field.name}'
        LEFT JOIN $_incoming.field_version inf
               ON inf.item_id = m.id AND inf.field_name = '${field.name}'
       WHERE m.kind = 'source' AND i.kind = 'source'
         AND (EXISTS (SELECT 1 FROM main.source_reference r
                       WHERE r.item_id = m.id)
           OR EXISTS (SELECT 1 FROM main.source_contributor c
                       WHERE c.item_id = m.id)
           OR EXISTS (SELECT 1 FROM $_incoming.source_reference r
                       WHERE r.item_id = m.id)
           OR EXISTS (SELECT 1 FROM $_incoming.source_contributor c
                       WHERE c.item_id = m.id))
       ORDER BY m.id''').get();

    final changes = <FieldChange>[];
    for (var start = 0; start < candidates.length; start += _itemsPerQuery) {
      final slice = candidates.skip(start).take(_itemsPerQuery).toList();
      final ids = [for (final row in slice) row.read<String>('item_id')];
      final local = await _read('main', ids);
      final incoming = await _read(_incoming, ids);
      for (final row in slice) {
        final id = row.read<String>('item_id');
        final l = local[id] ?? _Side.empty;
        final i = incoming[id] ?? _Side.empty;
        final decision = StampRows.decide(row, valuesDiffer: l.key != i.key);
        if (decision == FieldDecision.same) continue;
        changes.add(
          FieldChange(
            itemId: id,
            field: field,
            decision: decision,
            localValue: l.text,
            incomingValue: i.text,
            localStamp: StampRows.field(row, 'l'),
            incomingStamp: StampRows.field(row, 'i'),
          ),
        );
      }
    }
    return changes;
  }

  /// Lo que la bóveda [schema] —`main` o la copia— tiene de cada uno de [ids].
  Future<Map<String, _Side>> _read(String schema, List<String> ids) async {
    final marks = List.filled(ids.length, '?').join(', ');
    final variables = [for (final id in ids) Variable<String>(id)];
    final identity = schema == _incoming ? _incomingIdentity : 'v.id';

    final references = {
      for (final row
          in await _db
              .customSelect(
                'SELECT * FROM $schema.source_reference '
                'WHERE item_id IN ($marks)',
                variables: variables,
              )
              .get())
        row.read<String>('item_id'): row,
    };
    final people = <String, List<_Person>>{};
    for (final row in await _db.customSelect('''
      SELECT c.item_id AS item_id, c.role AS role, $identity AS identity,
             v.value AS label, v.name_family AS family, v.name_given AS given,
             v.name_suffix AS suffix, v.is_institution AS institution
        FROM $schema.source_contributor c
        JOIN $schema.property_values v ON v.id = c.property_value_id
       WHERE c.item_id IN ($marks)
       ORDER BY c.item_id, c.position''', variables: variables).get()) {
      (people[row.read<String>('item_id')] ??= []).add(
        _Person(
          identity: row.read<String>('identity'),
          contributor: Contributor(
            name: personNameFromColumns(
              label: row.read<String>('label'),
              family: row.read<String?>('family'),
              given: row.read<String?>('given'),
              suffix: row.read<String?>('suffix'),
              isInstitution: row.read<int?>('institution') == null
                  ? null
                  : row.read<int>('institution') == 1,
            ),
            role:
                _named(ContributorRole.values, row.read<String>('role')) ??
                ContributorRole.author,
          ),
        ),
      );
    }

    return {
      for (final id in {...references.keys, ...people.keys})
        id: _Side(_dataOf(references[id], people[id] ?? const []), [
          for (final person in people[id] ?? const <_Person>[]) person.identity,
        ]),
    };
  }

  ReferenceData _dataOf(QueryRow? row, List<_Person> people) {
    final accessed = row?.read<int?>('accessed_at');
    return ReferenceData(
      type: _named(ReferenceType.values, row?.read<String?>('reference_type')),
      contributors: [for (final person in people) person.contributor],
      containerTitle: row?.read<String?>('container_title'),
      publisher: row?.read<String?>('publisher'),
      publisherPlace: row?.read<String?>('publisher_place'),
      edition: row?.read<String?>('edition'),
      volume: row?.read<String?>('volume'),
      issue: row?.read<String?>('issue'),
      pages: row?.read<String?>('pages'),
      isbn: row?.read<String?>('isbn'),
      issn: row?.read<String?>('issn'),
      doi: row?.read<String?>('doi'),
      accessedAt: accessed == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(accessed * 1000),
      citationKey: row?.read<String?>('citation_key'),
      publicationPrecision: _named(
        PublicationPrecision.values,
        row?.read<String?>('publication_precision'),
      ),
    );
  }
}

/// Una persona de una obra con su identidad en esta bóveda.
class _Person {
  const _Person({required this.identity, required this.contributor});

  final String identity;
  final Contributor contributor;
}

/// Lo que una bóveda tiene de UNA fuente.
class _Side {
  const _Side(this.data, this.identities);

  /// Sin nada de esto: para la fuente que solo una de las dos bóvedas tiene.
  static const empty = _Side(ReferenceData(), []);

  final ReferenceData data;

  /// Quién es, en esta bóveda, cada persona de [data], en su orden.
  final List<String> identities;

  /// La referencia como texto, o `null` si no tiene nada: lo que se guarda si
  /// esta versión no queda en vivo.
  String? get text => data.isEmpty ? null : encodeReference(data);

  /// Con qué se compara: los datos y, por cada persona, quién es y con qué
  /// rol. Dos lados con la misma clave dicen lo mismo aunque a una persona se
  /// la llame distinto en cada bóveda.
  String get key => jsonEncode({
    'data': referenceToJson(data.copyWith(contributors: const [])),
    'people': [
      for (var i = 0; i < identities.length; i++)
        '${data.contributors[i].role.name}|${identities[i]}',
    ],
  });
}

/// El valor de [values] que se llama [name], o `null` si no hay ninguno.
T? _named<T extends Enum>(List<T> values, String? name) =>
    name == null ? null : values.asNameMap()[name];
