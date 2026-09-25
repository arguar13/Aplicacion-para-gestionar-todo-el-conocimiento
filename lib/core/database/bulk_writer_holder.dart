import 'package:sinapsis/core/database/knowledge_entry_writer.dart';

/// Comparte, entre los repositorios que escriben con [KnowledgeEntryWriter],
/// cuál escritor está en modo lote ([KnowledgeEntryWriter.runBulk]) ahora
/// mismo —si hay alguno— (F19, 19.4).
///
/// Cada repositorio crea su propio escritor por llamada
/// (`KnowledgeEntryWriter get _writer => KnowledgeEntryWriter(...)`), así
/// que sin este puente un lote que abre UN repositorio no se nota en otro
/// que la misma operación también toca. Es lo que le pasa a
/// `ImportReferencesFileUseCase`: guarda con `LibraryRepository` Y con
/// `ReferenceRepository` por cada entrada, dos repositorios que no se
/// conocen entre sí. Una sola instancia de este puente, inyectada en los
/// dos, alcanza: no hace falta que compartan nada más que la misma
/// `AppDatabase` —que ya comparten, al ser la única de la app—.
class BulkWriterHolder {
  KnowledgeEntryWriter? _current;

  /// El escritor en modo lote activo, o `null` fuera de un lote.
  KnowledgeEntryWriter? get current => _current;

  /// Corre [body] con [writer] —ya en modo lote— puesto a disposición de
  /// [current] mientras dura. Restaura lo que había antes al terminar, para
  /// que un lote pueda abrir otro adentro de una operación ajena sin
  /// perderla —no hace falta hoy, pero es lo único que mantiene el invariante
  /// de que [current] siempre vuelve a lo que era—.
  Future<T> runWith<T>(
    KnowledgeEntryWriter writer,
    Future<T> Function() body,
  ) async {
    final previous = _current;
    _current = writer;
    try {
      return await body();
    } finally {
      _current = previous;
    }
  }
}
