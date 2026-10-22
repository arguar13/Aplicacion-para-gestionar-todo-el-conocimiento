import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/renditions.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';

/// Lo que se resalta para estudiar un documento (F36, v40): las oraciones del
/// resumen y de la síntesis, y las palabras clave.
///
/// Como un subrayado, apunta a una forma de texto y a un rango de ese texto, y
/// guarda el fragmento copiado: si el texto se vuelve a extraer, se reubica
/// por el fragmento (`TextAnchorRelocator`). Va aparte de `highlights` a
/// propósito: un subrayado es de la persona —con su nota, en «Leer para
/// destilar», en lo que se exporta—, y esto lo marca la IA y se rehace al
/// volver a analizar.
@DataClassName('StudyMarkRow')
@TableIndex(name: 'idx_study_marks_rendition', columns: {#renditionId})
class StudyMarks extends Table {
  @override
  String get tableName => 'study_marks';

  TextColumn get id => text()();

  TextColumn get renditionId =>
      text().references(Renditions, #id, onDelete: KeyAction.cascade)();

  TextColumn get kind => textEnum<StudyMarkKind>()();

  /// Quién la puso: la IA al analizar, o la persona al elegir una palabra
  /// clave a mano.
  TextColumn get origin => textEnum<ContentOrigin>()();

  IntColumn get startOffset => integer()();
  IntColumn get endOffset => integer()();

  /// El texto marcado, copiado: con él se reubica si el texto cambia.
  TextColumn get excerpt => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (end_offset > start_offset)',
    'CHECK (start_offset >= 0)',
  ];
}

/// Hasta dónde se analizó el texto de una forma para estudiarlo (F36, v40):
/// un documento largo se analiza por partes, y cada parte que termina corre
/// [analyzedUntil]. Si el análisis se corta —se cerró la app, se paró—, sigue
/// desde ahí.
@DataClassName('StudyAnalysisRow')
class StudyAnalyses extends Table {
  @override
  String get tableName => 'study_analyses';

  TextColumn get renditionId =>
      text().references(Renditions, #id, onDelete: KeyAction.cascade)();

  /// Hasta qué posición del texto está analizado: el final de la última
  /// oración de la última parte que terminó.
  IntColumn get analyzedUntil => integer()();

  /// Cuándo terminó la última parte, si ya no queda ninguna.
  DateTimeColumn get completedAt => dateTime().nullable()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {renditionId};

  @override
  List<String> get customConstraints => ['CHECK (analyzed_until >= 0)'];
}
