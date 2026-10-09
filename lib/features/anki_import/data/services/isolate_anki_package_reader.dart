import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/anki_import/data/services/sqlite_anki_package_reader.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_exception.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_package_reader.dart';

/// Lee el `.apkg` en otro isolate: descomprimir la colección y recorrer miles
/// de notas con SQLite es trabajo síncrono, y en el hilo de la pantalla la
/// congelaría mientras dura.
///
/// Lo que lanza el lector (`AnkiImportException`) viaja de vuelta como dato, no
/// como excepción: la `cause` original puede ser una excepción de SQLite o del
/// zip que no cruza entre isolates, y perderla es mejor que perder el aviso.
class IsolateAnkiPackageReader implements AnkiPackageReader {
  const IsolateAnkiPackageReader();

  @override
  Future<AnkiImportedPackage> readFile(String path) async =>
      (await compute(_readFile, path)).unwrap();

  @override
  Future<AnkiImportedPackage> readBytes(Uint8List bytes) async =>
      (await compute(_readBytes, bytes)).unwrap();
}

class _ReadResult {
  const _ReadResult.ok(this.package) : failure = null, message = null;

  const _ReadResult.failed(this.failure, this.message) : package = null;

  final AnkiImportedPackage? package;
  final AnkiImportFailure? failure;
  final String? message;

  AnkiImportedPackage unwrap() {
    final failure = this.failure;
    if (failure != null) throw AnkiImportException(failure, message!);
    return package!;
  }
}

Future<_ReadResult> _readFile(String path) =>
    _run((reader) => reader.readFile(path));

Future<_ReadResult> _readBytes(Uint8List bytes) =>
    _run((reader) => reader.readBytes(bytes));

Future<_ReadResult> _run(
  Future<AnkiImportedPackage> Function(AnkiPackageReader reader) read,
) async {
  try {
    return _ReadResult.ok(await read(const SqliteAnkiPackageReader()));
  } on AnkiImportException catch (e) {
    return _ReadResult.failed(e.failure, e.message);
  }
}
