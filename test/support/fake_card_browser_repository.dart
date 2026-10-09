import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_row.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/card_browser_repository.dart';

/// Un [CardBrowserRepository] en memoria para probar el control de «Mis
/// tarjetas» sin una base: devuelve `total` tarjetas (`c0`, `c1`…), deja
/// frenar las lecturas para probar el orden de llegada, y registra cada
/// llamada. El SQL de verdad se prueba aparte, contra SQLite.
class FakeCardBrowserRepository implements CardBrowserRepository {
  FakeCardBrowserRepository({this.total = 0});

  int total;

  /// Cuántas tarjetas devuelve cada pedido; por defecto, `total`.
  int Function(CardBrowserQuery query)? totalFor;

  final List<({CardBrowserQuery query, int offset, int limit})> pageCalls = [];
  int countCalls = 0;
  int idsCalls = 0;
  final List<List<String>> resets = [];
  final List<List<String>> deletes = [];

  /// Mientras esté puesto, las páginas esperan a que se complete.
  Completer<void>? pageGate;
  Completer<void>? idsGate;
  Completer<void>? countGate;

  bool failPages = false;
  bool failCount = false;
  bool failIds = false;
  bool failWrites = false;

  Map<CardBrowserStatus, int> counts = {
    for (final s in CardBrowserStatus.values) s: 0,
  };

  final _changes = StreamController<void>.broadcast();

  /// Avisa que algo cambió en la base.
  void notifyChange() => _changes.add(null);

  Future<void> close() => _changes.close();

  int _totalOf(CardBrowserQuery query) =>
      totalFor == null ? total : totalFor!(query);

  Flashcard cardAt(int index, {String prefix = 'c'}) => Flashcard(
    id: '$prefix$index',
    itemId: 'item',
    front: 'Pregunta $prefix$index',
    back: 'Respuesta $prefix$index',
    dueAt: DateTime(2026, 9, 11, 10),
    createdAt: DateTime(2026, 9),
  );

  @override
  Future<Either<Failure, int>> count(CardBrowserQuery query) async {
    countCalls++;
    final gate = countGate;
    final answer = _totalOf(query);
    if (gate != null) await gate.future;
    if (failCount) return left(const Failure.unexpected(message: 'falló'));
    return right(answer);
  }

  @override
  Future<Either<Failure, List<CardBrowserRow>>> page(
    CardBrowserQuery query, {
    required int offset,
    required int limit,
  }) async {
    pageCalls.add((query: query, offset: offset, limit: limit));
    final gate = pageGate;
    if (gate != null) await gate.future;
    if (failPages) return left(const Failure.unexpected(message: 'falló'));
    final end = (offset + limit).clamp(0, _totalOf(query));
    final prefix = query.text.isEmpty ? 'c' : query.text;
    return right([
      for (var i = offset; i < end; i++)
        CardBrowserRow(
          card: cardAt(i, prefix: prefix),
          itemTitle: 'Elemento',
          lapses: 0,
        ),
    ]);
  }

  @override
  Future<Either<Failure, List<String>>> ids(CardBrowserQuery query) async {
    idsCalls++;
    final gate = idsGate;
    if (gate != null) await gate.future;
    if (failIds) return left(const Failure.unexpected(message: 'falló'));
    final prefix = query.text.isEmpty ? 'c' : query.text;
    return right([for (var i = 0; i < _totalOf(query); i++) '$prefix$i']);
  }

  @override
  Future<Either<Failure, Map<CardBrowserStatus, int>>> statusCounts(
    CardBrowserQuery query,
  ) async => right(counts);

  @override
  Stream<void> changes() => _changes.stream;

  @override
  Future<Either<Failure, int>> resetSchedule(Iterable<String> ids) async {
    if (failWrites) return left(const Failure.unexpected(message: 'falló'));
    resets.add(ids.toList());
    return right(ids.length);
  }

  @override
  Future<Either<Failure, int>> deleteMany(Iterable<String> ids) async {
    if (failWrites) return left(const Failure.unexpected(message: 'falló'));
    deletes.add(ids.toList());
    return right(ids.length);
  }
}
