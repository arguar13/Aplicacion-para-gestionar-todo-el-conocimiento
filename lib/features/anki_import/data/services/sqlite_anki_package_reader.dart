import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_exception.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_collection_mapper.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_package_reader.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// [AnkiPackageReader] sobre el zip y la base SQLite de un `.apkg`.
///
/// **Qué archivo del paquete lee.** Anki guarda la colección con tres
/// formatos, y los paquetes traen a veces más de uno:
///
/// - `collection.anki21b`: el actual (23.10 en adelante), comprimido con zstd
///   y con otro esquema. Dart no lo lee: si es lo único real que hay, falla
///   con [AnkiImportFailure.newFormatOnly] y dice cómo exportarlo.
/// - `collection.anki21`: el formato clásico con el calendario de las
///   versiones 2.1.x, el que Anki escribe con «Compatibilidad con versiones
///   antiguas».
/// - `collection.anki2`: el clásico más viejo; es el que escribe el
///   `AnkiPackageBuilder` de Sinapsis. Los paquetes del formato nuevo traen
///   además uno de relleno, con una sola nota que pide actualizar Anki: se
///   reconoce y no cuenta.
///
/// Se elige, en ese orden, `collection.anki21` y `collection.anki2`.
///
/// **Memoria.** Del zip se saca solo la colección (a un archivo temporal que
/// se borra al terminar, por tandas con el zlib nativo: `archive` junta cada
/// entrada entera en memoria al descomprimir) y la tabla `media`, que es un
/// JSON chico. Los medios (que pueden ser cientos de MB) no se tocan: se
/// cuentan por su manifiesto.
class SqliteAnkiPackageReader implements AnkiPackageReader {
  /// [maxCollectionBytes] es lo más que se acepta descomprimir de la
  /// colección; [workDirectory] da la carpeta temporal de trabajo (por
  /// defecto, una nueva dentro de la temporal del sistema). Los dos existen
  /// para las pruebas.
  const SqliteAnkiPackageReader({
    this.maxCollectionBytes = _defaultMaxCollectionBytes,
    this.workDirectory,
  });

  final int maxCollectionBytes;
  final Future<Directory> Function()? workDirectory;

  static const _legacyNames = ['collection.anki21', 'collection.anki2'];
  static const _newFormatName = 'collection.anki21b';
  static const _chunkSize = 64 * 1024;

  /// Un `.apkg` que pasa de esto sin descomprimir se rechaza como sospechoso
  /// de bomba: la colección más grande que se vio en la práctica, con
  /// cientos de miles de tarjetas, pesa decenas de MB.
  static const _defaultMaxCollectionBytes = 2 * 1024 * 1024 * 1024;

  @override
  Future<AnkiImportedPackage> readFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw const AnkiImportException(
        AnkiImportFailure.emptyFile,
        'No se encuentra el archivo del mazo de Anki.',
      );
    }
    if (file.lengthSync() == 0) throw _emptyFile();

    final source = InputFileStream(path);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(source);
        // `archive` lanza cualquier cosa con un archivo que no es un zip.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        throw _notAnApkg();
      }
      return await _guarded(() => _read(archive));
    } finally {
      await source.close();
    }
  }

  @override
  Future<AnkiImportedPackage> readBytes(Uint8List bytes) async {
    if (bytes.isEmpty) throw _emptyFile();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
      // Igual que arriba.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      throw _notAnApkg();
    }
    return _guarded(() => _read(archive));
  }

  /// Cualquier cosa que salga mal al leer un archivo ajeno es un
  /// [AnkiImportException]: lo que el lector ya sabe nombrar pasa tal cual; el
  /// disco que falla es [AnkiImportFailure.unreadable]; y cualquier otra
  /// cosa —un campo con una forma que nadie previó— es una colección dañada,
  /// con la excepción original en [AnkiImportException.cause].
  Future<AnkiImportedPackage> _guarded(
    Future<AnkiImportedPackage> Function() read,
  ) async {
    try {
      return await read();
    } on AnkiImportException {
      rethrow;
    } on FileSystemException catch (e) {
      throw AnkiImportException(
        AnkiImportFailure.unreadable,
        'No se pudo leer el mazo de Anki: el disco falló o no hay espacio '
        'libre.',
        cause: e,
      );
      // Entrada ajena e imprevisible: nunca una excepción cruda.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      throw AnkiImportException(
        AnkiImportFailure.corrupt,
        'El mazo de Anki está dañado: no se pudo leer su colección.',
        cause: e,
      );
    }
  }

  Future<AnkiImportedPackage> _read(Archive archive) async {
    final entries = {
      for (final entry in archive.files)
        if (entry.isFile) entry.name: entry,
    };

    final candidates = [
      for (final name in _legacyNames)
        if (entries.containsKey(name)) entries[name]!,
    ];
    final hasNewFormat = entries.containsKey(_newFormatName);
    if (candidates.isEmpty && !hasNewFormat) throw _notAnApkg();

    final directory =
        await (workDirectory?.call() ??
            Directory.systemTemp.createTemp('sinapsis-anki-'));
    try {
      AnkiImportException? lastProblem;
      var sawPlaceholder = false;
      for (final entry in candidates) {
        final dbFile = File(p.join(directory.path, entry.name));
        try {
          await _extract(entry, dbFile);
          return _readCollection(
            dbFile,
            sourceFile: entry.name,
            mediaCount: _mediaCount(entries['media']),
          );
        } on _PlaceholderCollection {
          // El relleno de un paquete del formato nuevo: se sigue mirando.
          sawPlaceholder = true;
          continue;
        } on AnkiImportException catch (e) {
          lastProblem = e;
        }
      }
      if (hasNewFormat || sawPlaceholder) throw _newFormatOnly();
      throw lastProblem ?? _notAnApkg();
    } finally {
      await _deleteQuietly(directory);
    }
  }

  // --- La colección ---

  AnkiImportedPackage _readCollection(
    File dbFile, {
    required String sourceFile,
    required int mediaCount,
  }) {
    final sqlite3.Database db;
    try {
      db = sqlite3.sqlite3.open(dbFile.path, mode: sqlite3.OpenMode.readOnly);
    } on sqlite3.SqliteException {
      throw _corrupt();
    }
    try {
      return _mapCollection(db, sourceFile: sourceFile, mediaCount: mediaCount);
    } on sqlite3.SqliteException {
      // «no such table», «file is not a database»…: la colección no sirve.
      throw _corrupt();
    } finally {
      db.close();
    }
  }

  AnkiImportedPackage _mapCollection(
    sqlite3.Database db, {
    required String sourceFile,
    required int mediaCount,
  }) {
    final col = db.select('SELECT crt, models, decks FROM col LIMIT 1');
    if (col.isEmpty) throw _corrupt();
    final row = col.first;

    final modelsJson = row['models'];
    final decksJson = row['decks'];
    final crt = row['crt'];
    if (modelsJson is! String ||
        decksJson is! String ||
        crt is! int ||
        modelsJson.trim().isEmpty ||
        decksJson.trim().isEmpty) {
      // El esquema nuevo deja vacíos esos campos de `col` (viven en tablas
      // aparte): no es un formato que este lector entienda.
      throw const AnkiImportException(
        AnkiImportFailure.unsupportedSchema,
        'La colección de este mazo es de una versión de Anki que Sinapsis no '
        'sabe leer. En Anki, exportalo de nuevo marcando «Compatibilidad con '
        'versiones antiguas» (en inglés, «Support older Anki versions»).',
      );
    }

    final models = parseAnkiModels(modelsJson);
    final decks = parseAnkiDecks(decksJson);

    if (_isPlaceholder(db)) throw const _PlaceholderCollection();

    final lastReview = <int, int>{};
    final reviews = <AnkiImportedReview>[];
    final warnings = <String>[];
    _readRevlog(db, lastReview, reviews, warnings);

    final createdAt = DateTime.fromMillisecondsSinceEpoch(crt * 1000);
    final mapper = AnkiCollectionMapper(
      collectionCreatedAt: createdAt,
      models: models,
      deckNames: decks.names,
      filteredDecks: decks.filtered,
      lastReviewByCard: lastReview,
    );

    // Las tarjetas juntas con su nota, nota por nota (así las hermanas se ven
    // a la vez), sin cargar la colección entera en memoria.
    final statement = db.prepare(
      'SELECT n.id AS nid, n.guid AS guid, n.mid AS mid, n.tags AS tags, '
      'n.flds AS flds, c.id AS cid, c.did AS did, c.ord AS ord, '
      'c.type AS type, c.queue AS queue, c.due AS due, c.ivl AS ivl, '
      'c.factor AS factor, c.reps AS reps, c.lapses AS lapses, '
      'c.odue AS odue, c.odid AS odid, c."left" AS stepsleft '
      'FROM cards c JOIN notes n ON n.id = c.nid '
      'ORDER BY n.id, c.ord',
    );
    try {
      final cursor = statement.selectCursor();
      AnkiNoteRow? current;
      var group = <AnkiCardRow>[];
      while (cursor.moveNext()) {
        final r = cursor.current;
        final noteId = _int(r['nid']);
        if (current != null && current.id != noteId) {
          mapper.addNote(current, group);
          group = <AnkiCardRow>[];
        }
        if (current == null || current.id != noteId) {
          current = AnkiNoteRow(
            id: noteId,
            guid: _string(r['guid']),
            modelId: _int(r['mid']),
            tags: _string(r['tags']),
            fields: _string(r['flds']),
          );
        }
        group.add(
          AnkiCardRow(
            id: _int(r['cid']),
            deckId: _int(r['did']),
            ord: _int(r['ord']),
            type: _int(r['type']),
            queue: _int(r['queue']),
            due: _int(r['due']),
            interval: _int(r['ivl']),
            factor: _int(r['factor']),
            reps: _int(r['reps']),
            lapses: _int(r['lapses']),
            originalDue: _int(r['odue']),
            originalDeckId: _int(r['odid']),
            left: _int(r['stepsleft']),
          ),
        );
      }
      if (current != null) mapper.addNote(current, group);
    } finally {
      statement.close();
    }

    // Una tarjeta que apunta a una nota que no existe no sale del JOIN.
    final orphans = _int(
      db
          .select(
            'SELECT COUNT(*) AS n FROM cards c '
            'WHERE NOT EXISTS (SELECT 1 FROM notes n WHERE n.id = c.nid)',
          )
          .first['n'],
    );

    final built = mapper.build();
    if (built.isEmpty && mapper.skipped == 0 && orphans == 0) {
      warnings.add('El mazo de Anki no tiene ninguna tarjeta.');
    }

    return AnkiImportedPackage(
      decks: built,
      reviews: reviews,
      packageMediaFiles: mediaCount,
      collectionCreatedAt: createdAt,
      sourceFile: sourceFile,
      warnings: [...mapper.warnings, ...warnings],
      skippedCards: mapper.skipped + orphans,
    );
  }

  /// Si la colección es el relleno que Anki escribe junto al formato nuevo:
  /// una sola nota que pide actualizar Anki.
  bool _isPlaceholder(sqlite3.Database db) {
    final count = _int(db.select('SELECT COUNT(*) AS n FROM notes').first['n']);
    if (count != 1) return false;
    final flds = db.select('SELECT flds FROM notes LIMIT 1').first['flds'];
    return flds is String &&
        flds.toLowerCase().contains('please update to the latest anki');
  }

  /// El historial es opcional: sin tabla, o con filas raras, el calendario
  /// sigue valiendo.
  void _readRevlog(
    sqlite3.Database db,
    Map<int, int> lastReview,
    List<AnkiImportedReview> reviews,
    List<String> warnings,
  ) {
    try {
      final statement = db.prepare(
        'SELECT id, cid, ease, ivl, lastIvl, time FROM revlog ORDER BY id',
      );
      try {
        final cursor = statement.selectCursor();
        while (cursor.moveNext()) {
          final r = cursor.current;
          final ease = _int(r['ease']);
          // `ease` 0 son los reprogramados a mano, no un repaso.
          if (ease < 1 || ease > 4) continue;
          final id = _int(r['id']);
          final cid = _int(r['cid']);
          lastReview[cid] = id;
          reviews.add(
            AnkiImportedReview(
              ankiCardId: cid,
              reviewedAt: DateTime.fromMillisecondsSinceEpoch(id),
              ease: ease,
              intervalDays: _days(_int(r['ivl'])),
              previousIntervalDays: _days(_int(r['lastIvl'])),
              durationMs: _int(r['time']),
            ),
          );
        }
      } finally {
        statement.close();
      }
    } on sqlite3.SqliteException {
      lastReview.clear();
      reviews.clear();
      warnings.add('El mazo no trae el historial de repasos.');
    }
  }

  /// Los intervalos negativos de `revlog` son segundos: menos de un día.
  int _days(int interval) => interval < 0 ? 0 : interval;

  int _int(Object? value) => value is int ? value : 0;

  String _string(Object? value) => value is String ? value : '';

  // --- El zip ---

  /// Cuántos medios dice tener el paquete. El manifiesto `media` es un JSON
  /// `{"0": "foto.jpg", ...}`; si no se puede leer, 0 (los medios que las
  /// tarjetas referencian se cuentan aparte, desde su texto).
  int _mediaCount(ArchiveFile? entry) {
    if (entry == null || entry.size > 64 * 1024 * 1024) return 0;
    try {
      final bytes = entry.readBytes();
      if (bytes == null) return 0;
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map ? decoded.length : 0;
      // Manifiesto ilegible: no cambia el calendario ni el texto.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return 0;
    }
  }

  /// Escribe [entry] en [out] descomprimiéndola por tandas con el zlib nativo.
  /// Comprueba el CRC-32 de la entrada y borra el archivo si falla.
  Future<void> _extract(ArchiveFile entry, File out) async {
    if (entry.size > maxCollectionBytes) throw _corrupt();
    final sink = out.openWrite();
    try {
      await sink.addStream(_decompressed(entry));
      await sink.close();
      // Cualquier fallo del zip o del disco es «el archivo no sirve».
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      try {
        await sink.close();
        // Ya se está fallando.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
      await _deleteQuietly(out);
      throw _corrupt();
    }
  }

  Stream<List<int>> _decompressed(ArchiveFile entry) async* {
    final content = entry.rawContent;
    if (content == null) return;

    final method = content is ZipFile
        ? content.compressionMethod
        : CompressionType.none;
    final compressed = content.getStream(decompress: false);
    final start = compressed.position;
    try {
      Stream<List<int>> chunks() async* {
        while (!compressed.isEOS) {
          final size = compressed.length < _chunkSize
              ? compressed.length
              : _chunkSize;
          yield compressed.readBytes(size).toUint8List();
        }
      }

      final plain = switch (method) {
        CompressionType.deflate => chunks().transform(
          ZLibCodec(raw: true).decoder,
        ),
        CompressionType.none => chunks(),
        _ => throw UnsupportedError('Compresión no soportada: $method'),
      };

      var crc = 0;
      await for (final chunk in plain) {
        crc = getCrc32(chunk, crc);
        yield chunk;
      }
      final expected = entry.crc32;
      if (expected != null && crc != expected) {
        throw FormatException('El CRC-32 de ${entry.name} no coincide.');
      }
    } finally {
      compressed.setPosition(start);
    }
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) await entity.delete(recursive: true);
    } on FileSystemException {
      // Es un temporal: el sistema lo limpia.
    }
  }

  // --- Errores ---

  AnkiImportException _emptyFile() => const AnkiImportException(
    AnkiImportFailure.emptyFile,
    'El archivo está vacío.',
  );

  AnkiImportException _notAnApkg() => const AnkiImportException(
    AnkiImportFailure.notAnApkg,
    'El archivo no es un mazo de Anki (.apkg).',
  );

  AnkiImportException _corrupt() => const AnkiImportException(
    AnkiImportFailure.corrupt,
    'El mazo de Anki está dañado: no se pudo leer su colección.',
  );

  AnkiImportException _newFormatOnly() => const AnkiImportException(
    AnkiImportFailure.newFormatOnly,
    'Este mazo está en el formato nuevo de Anki, que Sinapsis no puede abrir. '
    'En Anki, exportalo de nuevo marcando «Compatibilidad con versiones '
    'antiguas» (en inglés, «Support older Anki versions»).',
  );
}

/// La colección de relleno de un paquete del formato nuevo.
class _PlaceholderCollection implements Exception {
  const _PlaceholderCollection();
}
