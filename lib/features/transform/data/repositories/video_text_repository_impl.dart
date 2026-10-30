import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/transform/domain/entities/stored_video_text.dart';
import 'package:sinapsis/features/transform/domain/repositories/video_text_repository.dart';

/// [VideoTextRepository] sobre la base (F45, paso 4).
///
/// Una consulta por lista, con el comienzo de cada texto cortado en la base
/// (`substr`): un video de cuatro horas no se lee entero para mirar su
/// escritura. Lo de la papelera queda afuera ([activeItemSql]).
class VideoTextRepositoryImpl implements VideoTextRepository {
  const VideoTextRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
  }) : _db = database,
       _telemetry = telemetry;

  final AppDatabase _db;
  final TelemetryService _telemetry;

  /// El texto principal de la fila de `item` [alias]: la forma de texto
  /// marcada como principal, o si no la primera —sin los textos de lo bajado
  /// de una página (`text_of`) ni las notas de bloques—, como
  /// `primaryTextOf`.
  static String _primaryTextSql(String alias) =>
      '(SELECT substr(p.content, 1, $kStoredVideoTextHead) FROM renditions p '
      'WHERE p.item_id = $alias.id AND p.content IS NOT NULL '
      "AND p.text_of IS NULL AND p.kind <> '${RenditionKind.blocks.name}' "
      'ORDER BY p.is_primary DESC, p.created_at, p.id LIMIT 1)';

  /// Si la fuente se está procesando: espera su turno o está en curso.
  static final _reextractingSql =
      "source.processing_status IN ('${SourceProcessingStatus.pending.name}', "
      "'${SourceProcessingStatus.running.name}')";

  @override
  Stream<List<StoredVideoText>> watchPending() {
    final states = [
      for (final state in InboxStatus.pending.itemStates) "'${state.name}'",
    ].join(', ');
    final sql =
        'SELECT item.id AS source_id, item.title AS title, '
        'source.language AS language, $_reextractingSql AS reextracting, '
        '${_primaryTextSql('item')} AS head '
        'FROM item JOIN source ON source.item_id = item.id '
        "WHERE item.kind = '${ItemKind.source.name}' "
        'AND item.state IN ($states) AND $kActiveItemSql '
        "AND source.source_type = '${SourceKind.youtube.name}' "
        'ORDER BY item.created_at, item.id';
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeEntries, _db.knowledgeSources, _db.renditions],
      read: () async {
        final rows = await _db.customSelect(sql).get();
        return [
          for (final row in rows)
            if (row.readNullable<String>('head') case final head?)
              StoredVideoText(
                sourceId: row.read<String>('source_id'),
                title: row.read<String>('title'),
                language: row.readNullable<String>('language'),
                head: head,
                reextracting: row.read<bool>('reextracting'),
              ),
        ];
      },
      telemetry: _telemetry,
      hint: 'VideoTextRepositoryImpl.watchPending',
    );
  }

  @override
  Stream<List<StoredVideoText>> watchProcessed() {
    final sql =
        'SELECT doc.id AS document_id, item.id AS source_id, '
        'item.title AS title, source.language AS language, '
        '$_reextractingSql AS reextracting, '
        '(SELECT substr(part.content, 1, $kStoredVideoTextHead) '
        'FROM processed_parts part WHERE part.document_id = doc.id '
        "AND part.section = '${ProcessedSection.text.name}' "
        'ORDER BY part.position LIMIT 1) AS head, '
        '${_primaryTextSql('item')} AS source_head '
        'FROM processed_documents pd '
        'JOIN item doc ON doc.id = pd.item_id '
        'JOIN item ON item.id = pd.source_item_id '
        'JOIN source ON source.item_id = item.id '
        "WHERE pd.source_kind = '${SourceKind.youtube.name}' "
        'AND ${activeItemSql('doc')} AND $kActiveItemSql '
        'ORDER BY doc.created_at, doc.id';
    return watchQuery(
      db: _db,
      tables: [
        _db.processedDocuments,
        _db.processedParts,
        _db.knowledgeEntries,
        _db.knowledgeSources,
        _db.renditions,
      ],
      read: () async {
        final rows = await _db.customSelect(sql).get();
        return [
          for (final row in rows)
            if (row.readNullable<String>('head') case final head?)
              StoredVideoText(
                sourceId: row.read<String>('source_id'),
                documentId: row.read<String>('document_id'),
                title: row.read<String>('title'),
                language: row.readNullable<String>('language'),
                head: head,
                sourceHead: row.readNullable<String>('source_head'),
                reextracting: row.read<bool>('reextracting'),
              ),
        ];
      },
      telemetry: _telemetry,
      hint: 'VideoTextRepositoryImpl.watchProcessed',
    );
  }
}
