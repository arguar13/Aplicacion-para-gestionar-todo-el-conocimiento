import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/card_browser_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/my_cards_controller.dart';

import '../../../../support/fake_card_browser_repository.dart';

/// El control de «Mis tarjetas» (F31, ola 2, decisión 72): lee de a páginas,
/// guarda pocas, descarta lo viejo y se entera de los cambios.
void main() {
  late FakeCardBrowserRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = FakeCardBrowserRepository(total: 10000);
    container =
        ProviderContainer(
            overrides: [cardBrowserRepositoryProvider.overrideWithValue(repo)],
          )
          // autoDispose: alguien tiene que estar mirando.
          ..listen(myCardsControllerProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await repo.close();
  });

  MyCardsController controller() =>
      container.read(myCardsControllerProvider.notifier);
  MyCardsState state() => container.read(myCardsControllerProvider);

  /// Deja correr las lecturas pendientes.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await pumpEventQueue();
    }
  }

  group('la primera lectura', () {
    test('trae el total y los conteos, y no las tarjetas', () async {
      expect(state().total, isNull);
      await settle();

      expect(state().total, 10000);
      expect(state().statusCounts, isNotNull);
      expect(repo.pageCalls, isEmpty);
      expect(controller().cachedRows, 0);
    });

    test('rowAt pide la página y la devuelve al llegar', () async {
      await settle();

      expect(controller().rowAt(0), isNull);
      await settle();

      expect(controller().rowAt(0)!.card.id, 'c0');
      expect(controller().rowAt(49)!.card.id, 'c49');
      expect(repo.pageCalls.single.offset, 0);
      expect(repo.pageCalls.single.limit, kMyCardsPageSize);
      // La siguiente todavía no se pidió: recién ahora se pide.
      expect(controller().rowAt(50), isNull);
      await settle();
      expect(repo.pageCalls.last.offset, kMyCardsPageSize);
    });

    test(
      'pedir dos veces lo mismo mientras llega no repite la lectura',
      () async {
        await settle();
        controller()
          ..rowAt(3)
          ..rowAt(4)
          ..rowAt(5);
        await settle();
        expect(repo.pageCalls, hasLength(1));
        // Y ya cargada no se vuelve a leer.
        controller().rowAt(6);
        await settle();
        expect(repo.pageCalls, hasLength(1));
      },
    );

    test('una lista vacía y una de una tarjeta', () async {
      repo.total = 0;
      controller().retry();
      await settle();
      expect(state().total, 0);

      repo.total = 1;
      controller().retry();
      await settle();
      expect(state().total, 1);
      controller().rowAt(0);
      await settle();
      expect(controller().rowAt(0)!.card.id, 'c0');
      expect(controller().rowAt(1), isNull);
    });
  });

  group('la memoria', () {
    test('recorrer las 10.000 nunca deja más de seis páginas', () async {
      await settle();
      var peak = 0;
      for (var page = 0; page < 10000 ~/ kMyCardsPageSize; page++) {
        controller().rowAt(page * kMyCardsPageSize);
        await settle();
        final rows = controller().cachedRows;
        if (rows > peak) peak = rows;
      }
      expect(repo.pageCalls, hasLength(200));
      expect(peak, kMyCardsPageSize * kMyCardsMaxCachedPages);
      expect(
        controller().cachedRows,
        kMyCardsPageSize * kMyCardsMaxCachedPages,
      );
    });

    test('descarta la que hace más que no se mira', () async {
      await settle();
      // Se cargan las seis primeras.
      for (var page = 0; page < kMyCardsMaxCachedPages; page++) {
        controller().rowAt(page * kMyCardsPageSize);
        await settle();
      }
      // Se vuelve a mirar la primera: pasa a ser la más reciente.
      controller().rowAt(0);
      // Entra una séptima: sale la segunda, no la primera.
      controller().rowAt(kMyCardsMaxCachedPages * kMyCardsPageSize);
      await settle();

      expect(controller().rowAt(0), isNotNull);
      final callsBefore = repo.pageCalls.length;
      expect(controller().rowAt(kMyCardsPageSize), isNull); // la segunda salió
      await settle();
      expect(repo.pageCalls.length, callsBefore + 1);
    });
  });

  group('cambiar el pedido', () {
    test('descarta lo cargado y vuelve a contar', () async {
      await settle();
      controller().rowAt(0);
      await settle();
      expect(controller().cachedRows, kMyCardsPageSize);

      repo.totalFor = (query) => query.text == 'x' ? 7 : 10000;
      controller().setText('x');
      expect(state().total, isNull);
      expect(controller().cachedRows, 0);
      await settle();

      expect(state().total, 7);
      expect(state().query.text, 'x');
    });

    test('una lectura vieja que llega tarde se ignora', () async {
      await settle();
      repo.pageGate = Completer<void>();
      controller().rowAt(0); // pide la página del pedido de antes
      await pumpEventQueue();

      repo.totalFor = (_) => 10000;
      controller().setText('nuevo'); // el pedido cambia mientras espera
      repo.pageGate!.complete();
      await settle();

      // Las tarjetas del pedido viejo no se mezclan con las del nuevo.
      expect(controller().cachedRows, 0);
      repo.pageGate = null;
      controller().rowAt(0);
      await settle();
      expect(controller().rowAt(0)!.card.id, 'nuevo0');
    });

    test('setStatus, setScope y setText no hacen nada si no cambian', () async {
      await settle();
      final version = state().version;
      controller()
        ..setStatus(null)
        ..setScope(const StudyScope.all())
        ..setText('');
      await settle();
      expect(state().version, version);
      expect(repo.countCalls, 1);
    });

    test('un filtro, un recorte y el orden llegan al repositorio', () async {
      await settle();
      controller()
        ..setStatus(CardBrowserStatus.mature)
        ..setScope(const StudyScope.item('roma'))
        ..setSort(CardBrowserSort.ease);
      await settle();
      controller().rowAt(0);
      await settle();

      final query = repo.pageCalls.last.query;
      expect(query.status, CardBrowserStatus.mature);
      expect(query.scope, const StudyScope.item('roma'));
      expect(query.sort, CardBrowserSort.ease);
      expect(query.descending, isFalse);
    });

    test(
      'elegir el mismo orden lo invierte; otro, vuelve a ascendente',
      () async {
        await settle();
        controller().setSort(CardBrowserSort.due);
        expect(state().query.descending, isTrue);
        controller().setSort(CardBrowserSort.due);
        expect(state().query.descending, isFalse);
        controller()
          ..setSort(CardBrowserSort.due)
          ..setSort(CardBrowserSort.lapses);
        expect(state().query.sort, CardBrowserSort.lapses);
        expect(state().query.descending, isFalse);
        controller().toggleDescending();
        expect(state().query.descending, isTrue);
      },
    );
  });

  group('los cambios en la base', () {
    test('se vuelve a contar y las páginas se renuevan al mirarlas', () async {
      await settle();
      controller().rowAt(0);
      await settle();
      final counts = repo.countCalls;
      final pages = repo.pageCalls.length;

      repo
        ..total = 9990
        ..notifyChange()
        ..notifyChange(); // una ráfaga es una sola lectura
      await Future<void>.delayed(
        kMyCardsRefreshDelay + const Duration(milliseconds: 100),
      );
      await settle();

      expect(repo.countCalls, counts + 1);
      expect(state().total, 9990);
      // Lo que ya estaba cargado se sigue viendo mientras llega lo nuevo.
      expect(controller().rowAt(0), isNotNull);
      await settle();
      expect(repo.pageCalls.length, pages + 1);
    });
  });

  group('los fallos', () {
    test('una página que falla no se reintenta sola en cada armado', () async {
      await settle();
      repo.failPages = true;
      for (var i = 0; i < 5; i++) {
        controller().rowAt(0);
        await settle();
      }
      expect(state().failed, isTrue);
      expect(repo.pageCalls, hasLength(1));

      repo.failPages = false;
      controller().retry();
      await settle();
      expect(state().failed, isFalse);
      controller().rowAt(0);
      await settle();
      expect(controller().rowAt(0), isNotNull);
    });

    test('un conteo que falla se dice, y reintentar lo arregla', () async {
      repo.failCount = true;
      controller().retry();
      await settle();
      expect(state().failed, isTrue);

      repo.failCount = false;
      controller().retry();
      await settle();
      expect(state().failed, isFalse);
      expect(state().total, 10000);
    });
  });

  group('la selección', () {
    test('elegir, quitar y cancelar', () async {
      await settle();
      controller().startSelecting('c1');
      expect(state().selecting, isTrue);
      expect(state().selected, {'c1'});

      controller()
        ..toggle('c2')
        ..toggle('c1');
      expect(state().selected, {'c2'});

      controller().clearSelection();
      expect(state().selecting, isFalse);
      expect(state().selected, isEmpty);
    });

    test('elegir todas trae los ids de todas, estén cargadas o no', () async {
      await settle();
      final picked = await controller().selectAll();
      expect(picked, 10000);
      expect(state().selected, hasLength(10000));
      expect(state().selected, contains('c9999'));
      expect(state().selecting, isTrue);
      expect(repo.idsCalls, 1);
      // No se cargó ninguna tarjeta para eso.
      expect(controller().cachedRows, 0);
    });

    test('si falla la lectura de los ids, no elige nada', () async {
      await settle();
      repo.failIds = true;
      expect(await controller().selectAll(), isNull);
      expect(state().selected, isEmpty);
    });

    test(
      'elegir todas con un pedido que cambió mientras tanto se ignora',
      () async {
        await settle();
        repo.idsGate = Completer<void>();
        final picking = controller().selectAll();
        await pumpEventQueue();
        controller().setText('otro');
        repo.idsGate!.complete();

        expect(await picking, isNull);
        expect(state().selected, isEmpty);
      },
    );
  });
}
