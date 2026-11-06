import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/repositories/index_document_access.dart';
import 'package:sinapsis/features/index/domain/repositories/index_repository.dart';
import 'package:sinapsis/features/index/domain/services/index_match.dart';
import 'package:sinapsis/features/index/domain/services/index_order.dart';

/// Un [IndexRepository] de prueba para la pantalla del Índice (F46, paso 3).
///
/// Guarda los temas, los documentos y sus entradas como los tendría la base,
/// y arma cada lectura como el de verdad: los temas con sus cuentas y «Sin
/// tema» al final, los documentos de un tema de la A a la Z, los de todos en
/// el orden pedido, la búsqueda con los capítulos que contienen a cada
/// coincidencia. Cada lectura es un stream que vuelve a emitir con
/// [changed], como lo hace la base con cada escritura.
///
/// Cuenta lo que se le pide ([calls]) y cuántos lo están mirando ahora
/// ([watching]): con eso se prueba que la pantalla lee de a lo que se ve.
/// Una lectura se puede retener ([hold]) para ver la pantalla mientras carga.
class FakeIndexRepository implements IndexRepository {
  /// El nombre de cada tema, por su clave.
  final spaces = <String, String>{};

  /// Todos los documentos del Índice.
  final documents = <IndexDocument>[];

  /// Las entradas de cada documento, en su orden.
  final entries = <String, List<IndexEntry>>{};

  IndexProgress progress = const IndexProgress(
    documents: 0,
    indexedDocuments: 0,
    untitledImages: 0,
  );

  /// Cada lectura que se empezó a mirar, en orden: `topics`,
  /// `documentsOf:roma`, `documents:title`, `entries:a`, `search:nicea`,
  /// `progress`.
  final calls = <String>[];

  /// Cuántos miran ahora cada lectura.
  final watching = <String, int>{};

  /// Los títulos de imagen cambiados con [renameImage].
  final renamed = <String, String>{};

  final _changes = StreamController<void>.broadcast();
  final _held = <String>{};

  /// Vuelve a emitir todo lo que se está mirando.
  void changed() => _changes.add(null);

  /// Lo que empiece con [call] no emite hasta [release].
  void hold(String call) => _held.add(call);

  void release(String call) {
    _held.remove(call);
    changed();
  }

  /// Cuántos miran ahora las lecturas que empiezan con [prefix].
  int watchingStartingWith(String prefix) => watching.entries
      .where((e) => e.key.startsWith(prefix))
      .fold(0, (sum, e) => sum + e.value);

  Future<void> dispose() => _changes.close();

  Stream<T> _watch<T>(String call, T Function() read) {
    late final StreamController<T> controller;
    StreamSubscription<void>? changes;
    void emit() {
      if (_held.any(call.startsWith)) return;
      controller.add(read());
    }

    controller = StreamController<T>(
      onListen: () {
        calls.add(call);
        watching.update(call, (n) => n + 1, ifAbsent: () => 1);
        emit();
        changes = _changes.stream.listen((_) => emit());
      },
      // Sin devolver el futuro de soltar [changes]: el de una suscripción de
      // difusión se completa en la zona raíz, que el tiempo falso de las
      // pruebas no avanza, y `first` —que espera a soltar antes de dar su
      // valor— no terminaba nunca.
      onCancel: () {
        watching.update(call, (n) => n - 1);
        unawaited(changes?.cancel());
      },
    );
    return controller.stream;
  }

  List<IndexDocument> _byTitle(Iterable<IndexDocument> list) =>
      list.toList()..sort((a, b) => compareIndexNames(a.title, b.title));

  @override
  Stream<List<IndexTopic>> watchTopics() => _watch('topics', () {
    final named = [
      for (final MapEntry(key: id, value: name) in spaces.entries)
        if (documents.where((d) => d.spaceIds.contains(id)).length
            case final count when count > 0)
          IndexTopic(spaceId: id, name: name, documentCount: count),
    ]..sort((a, b) => compareIndexNames(a.name, b.name));
    final loose = documents.where((d) => d.spaceIds.isEmpty).length;
    return [
      ...named,
      if (loose > 0) IndexTopic(spaceId: null, name: '', documentCount: loose),
    ];
  });

  @override
  Stream<List<IndexDocument>> watchDocumentsOf(String? spaceId) => _watch(
    'documentsOf:$spaceId',
    () => _byTitle(
      documents.where(
        (d) =>
            spaceId == null ? d.spaceIds.isEmpty : d.spaceIds.contains(spaceId),
      ),
    ),
  );

  @override
  Stream<List<IndexDocument>> watchDocuments(IndexDocumentOrder order) =>
      _watch('documents:${order.name}', () {
        return switch (order) {
          IndexDocumentOrder.title => _byTitle(documents),
          IndexDocumentOrder.recent =>
            documents.toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        };
      });

  @override
  Stream<List<IndexEntry>> watchEntries(String documentId) => _watch(
    'entries:$documentId',
    () => List.unmodifiable(entries[documentId] ?? const <IndexEntry>[]),
  );

  @override
  Stream<List<IndexSearchHit>> watchSearch(String query, {int limit = 200}) =>
      _watch('search:$query', () {
        final hits = <IndexSearchHit>[];
        for (final document in _byTitle(documents)) {
          final chain = <IndexEntry>[];
          for (final entry in entries[document.id] ?? const <IndexEntry>[]) {
            final chapter = !entry.isImage && !entry.isWholeText;
            if (chapter) {
              chain
                ..removeWhere((e) => e.level >= entry.level)
                ..add(entry);
            }
            if (!indexTitleMatches(entry.title, query)) continue;
            hits.add(
              IndexSearchHit(
                entry: entry,
                documentTitle: document.title,
                sourceKind: document.sourceKind,
                spaceIds: document.spaceIds,
                ancestors: chapter
                    ? chain.sublist(0, chain.length - 1)
                    : const [],
              ),
            );
          }
        }
        return hits.take(limit).toList();
      });

  @override
  Future<Either<Failure, Map<String, List<IndexEntry>>>> readEntries(
    List<String> documentIds,
  ) async {
    calls.add('readEntries:${documentIds.length}');
    return right({
      for (final id in documentIds)
        if (entries[id] case final list? when list.isNotEmpty)
          id: List.unmodifiable(list),
    });
  }

  @override
  Stream<IndexProgress> watchProgress() => _watch('progress', () => progress);

  @override
  Future<Either<Failure, Unit>> renameImage(
    String imageId,
    String title,
  ) async {
    renamed[imageId] = title;
    return right(unit);
  }
}

/// Un [IndexDocumentAccess] de prueba (F46, paso 4): lo que se sabe de cada
/// documento —su título, su copia del original y su fuente en la Biblioteca
/// (paso 5c)— y su texto, como lo diría Procesado. Un documento que no está
/// en [facts] ya no existe.
class FakeIndexDocumentAccess implements IndexDocumentAccess {
  final facts = <String, IndexDocumentFacts>{};
  final texts = <String, String>{};

  /// Cada documento por el que se preguntó, en orden.
  final asked = <String>[];

  @override
  Future<IndexDocumentFacts?> factsOf(String documentId) async {
    asked.add(documentId);
    return facts[documentId];
  }

  @override
  Future<String?> textOf(String documentId) async => texts[documentId];
}

/// Un documento del Índice para las pruebas, con lo que importa de entrada.
IndexDocument indexDocument(
  String id,
  String title, {
  List<String> spaces = const [],
  SourceKind kind = SourceKind.document,
  DateTime? createdAt,
  int chapters = 0,
  int images = 0,
  bool hasText = true,
  bool indexed = true,
}) => IndexDocument(
  id: id,
  title: title,
  sourceKind: kind,
  createdAt: createdAt ?? DateTime(2026),
  chapterCount: chapters,
  imageCount: images,
  hasText: hasText,
  indexed: indexed,
  spaceIds: spaces,
);

/// Los capítulos de [documentId] como `(nivel, título)`, en su orden, con
/// claves desde [firstKey] y páginas del texto correlativas —o la del PDF si
/// [pdf]—.
List<IndexEntry> indexChapters(
  String documentId,
  List<(int, String)> chapters, {
  int firstKey = 1,
  bool pdf = false,
}) => [
  for (final (i, (level, title)) in chapters.indexed)
    IndexEntry(
      key: firstKey + i,
      documentId: documentId,
      origin: pdf ? IndexEntryOrigin.bookmark : IndexEntryOrigin.textHeading,
      level: level,
      position: i,
      title: title,
      textStart: i * 100,
      textEnd: i * 100 + title.length,
      textPage: i + 1,
      pdfPage: pdf ? 10 + i : null,
    ),
];

/// Una imagen de [documentId] en el lugar [position] de su galería.
IndexEntry indexImage(
  String documentId,
  int key, {
  required int position,
  String title = '',
}) => IndexEntry(
  key: key,
  documentId: documentId,
  origin: IndexEntryOrigin.image,
  level: 1,
  position: position,
  title: title,
  imageId: 'img-$key',
);

/// «Texto completo» de [documentId].
IndexEntry indexWholeText(String documentId, int key) => IndexEntry(
  key: key,
  documentId: documentId,
  origin: IndexEntryOrigin.wholeText,
  level: 1,
  position: 0,
  title: '',
  textStart: 0,
  textEnd: 10,
  textPage: 1,
);
