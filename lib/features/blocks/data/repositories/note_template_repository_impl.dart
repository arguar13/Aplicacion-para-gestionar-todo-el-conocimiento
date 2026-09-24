import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/note_template.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/blocks/domain/repositories/note_template_repository.dart';

class NoteTemplateRepositoryImpl implements NoteTemplateRepository {
  NoteTemplateRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Stream<List<NoteTemplate>> watchAll() {
    return watchQuery(
      db: _db,
      tables: [_db.noteTemplates],
      read: () async {
        final rows = await (_db.select(
          _db.noteTemplates,
        )..orderBy([(t) => OrderingTerm(expression: t.name)])).get();
        return rows.map(_toEntity).toList();
      },
      telemetry: _telemetry,
      hint: 'NoteTemplateRepositoryImpl.watchAll',
    );
  }

  @override
  Future<NoteTemplate> create({
    required String name,
    required List<ContentBlock> blocks,
    required List<TemplateProperty> properties,
  }) async {
    final template = NoteTemplate(
      id: _ids.next(),
      name: name,
      blocks: blocks,
      properties: properties,
      createdAt: _clock(),
    );
    await _db
        .into(_db.noteTemplates)
        .insert(
          NoteTemplatesCompanion.insert(
            id: template.id,
            name: template.name,
            blocksJson: encodeContentBlocks(template.blocks),
            propertiesJson: jsonEncode(
              properties.map(_propertyToJson).toList(),
            ),
            createdAt: template.createdAt,
          ),
        );
    return template;
  }

  @override
  Future<void> rename(String id, String name) async {
    await (_db.update(_db.noteTemplates)..where((t) => t.id.equals(id))).write(
      NoteTemplatesCompanion(name: Value(name)),
    );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.noteTemplates)..where((t) => t.id.equals(id))).go();
  }

  Map<String, Object?> _propertyToJson(TemplateProperty property) => {
    'definitionId': property.definitionId,
    'definitionName': property.definitionName,
    'value': property.value,
  };

  TemplateProperty _propertyFromJson(Map<String, Object?> json) =>
      TemplateProperty(
        definitionId: json['definitionId']! as String,
        definitionName: json['definitionName']! as String,
        value: json['value']! as String,
      );

  NoteTemplate _toEntity(NoteTemplateRow row) => NoteTemplate(
    id: row.id,
    name: row.name,
    blocks: decodeContentBlocks(row.blocksJson),
    properties: [
      for (final raw in jsonDecode(row.propertiesJson) as List<dynamic>)
        _propertyFromJson(raw as Map<String, Object?>),
    ],
    createdAt: row.createdAt,
  );
}
