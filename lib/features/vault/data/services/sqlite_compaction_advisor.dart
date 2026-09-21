import 'package:path/path.dart' as p;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/services/compaction_advisor.dart';
import 'package:sinapsis/features/vault/domain/services/free_space_probe.dart';

/// Mide la base abierta con los `PRAGMA` de SQLite —cuántas páginas tiene,
/// cuántas están libres, cómo devuelve lo que se borra— y le pregunta a
/// [FreeSpaceProbe] cuánto disco queda donde vive el archivo.
class SqliteCompactionAdvisor implements CompactionAdvisor {
  const SqliteCompactionAdvisor({
    required AppDatabase database,
    required FreeSpaceProbe freeSpace,
  }) : _database = database,
       _freeSpace = freeSpace;

  final AppDatabase _database;
  final FreeSpaceProbe _freeSpace;

  @override
  Future<CompactionAssessment> assess() async {
    final file = await _databaseFile();
    return CompactionAssessment(
      pageSize: await _pragma('page_size'),
      pageCount: await _pragma('page_count'),
      freePages: await _pragma('freelist_count'),
      autoVacuum: AutoVacuumMode.fromPragma(await _pragma('auto_vacuum')),
      // Una base en memoria no tiene un archivo cuyo disco preguntar.
      freeSpaceBytes: file == null
          ? null
          : await _freeSpace.freeBytesAt(p.dirname(file)),
    );
  }

  Future<int> _pragma(String name) async {
    final row = await _database.customSelect('PRAGMA $name').getSingle();
    return row.read<int>(name);
  }

  /// La ruta del archivo de la base principal, o `null` si es en memoria.
  Future<String?> _databaseFile() async {
    final rows = await _database.customSelect('PRAGMA database_list').get();
    for (final row in rows) {
      if (row.read<String>('name') != 'main') continue;
      final file = row.readNullable<String>('file');
      return (file == null || file.isEmpty) ? null : file;
    }
    return null;
  }
}
