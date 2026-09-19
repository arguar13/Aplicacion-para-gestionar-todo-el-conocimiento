import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/links/domain/entities/broken_link.dart';
import 'package:sinapsis/features/links/domain/repositories/link_repository.dart';
import 'package:sinapsis/features/links/presentation/providers/link_providers.dart';
import 'package:sinapsis/features/links/presentation/screens/broken_links_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Un repositorio de mentira: la pantalla se prueba contra lo que emite y lo
/// que se le pide crear, no contra una base. La lógica de crear —y su
/// atomicidad— se prueba en `link_repository_impl_test`.
class _FakeLinkRepository implements LinkRepository {
  _FakeLinkRepository(this._links);

  List<BrokenLink> _links;
  final _changes = StreamController<List<BrokenLink>>.broadcast();

  /// Cada lote pedido: los títulos y el subtipo.
  final batches = <(List<String>, NoteKind)>[];

  /// Si está, `createNotesForLinks` devuelve esto en vez de crear.
  Either<Failure, int>? result;

  /// Si está, `createNotesForLinks` espera a que se complete.
  Completer<void>? gate;

  @override
  Stream<List<BrokenLink>> watchBrokenLinks() async* {
    yield _links;
    yield* _changes.stream;
  }

  @override
  Future<Either<Failure, int>> createNotesForLinks(
    List<String> titles, {
    NoteKind kind = NoteKind.living,
  }) async {
    batches.add((titles, kind));
    await gate?.future;
    final outcome = result ?? right(titles.length);
    if (outcome.isRight()) {
      _links = [
        for (final link in _links)
          if (!titles.contains(link.title)) link,
      ];
      _changes.add(_links);
    }
    return outcome;
  }

  @override
  Future<Either<Failure, Set<String>>> findMissingTitles(
    Set<String> normalizedTitles, {
    String? excludingItemId,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, KnowledgeItem>> createNoteForLink({
    required String title,
    NoteKind kind = NoteKind.living,
  }) => throw UnimplementedError();
}

BrokenLink _link(String title, List<(String, String)> sources) => BrokenLink(
  title: title,
  normalizedTitle: title.toLowerCase(),
  sources: [
    for (final (id, noteTitle) in sources)
      BrokenLinkSource(itemId: id, title: noteTitle),
  ],
);

void main() {
  final es = AppLocalizationsEs();

  final cartago = _link('Cartago', [('n1', 'Viaje'), ('n2', 'Diario')]);
  final atenas = _link('Atenas', [('n1', 'Viaje')]);
  final esparta = _link('Esparta', [('n3', 'Grecia')]);

  Future<_FakeLinkRepository> pumpScreen(
    WidgetTester tester, {
    List<BrokenLink> links = const [],
    Stream<List<BrokenLink>>? overrideStream,
  }) async {
    final repository = _FakeLinkRepository(links);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const BrokenLinksScreen()),
        GoRoute(
          path: RoutePaths.itemDetailPattern,
          builder: (_, state) =>
              Scaffold(body: Text('detalle de ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          linkRepositoryProvider.overrideWithValue(repository),
          if (overrideStream != null)
            brokenLinksProvider.overrideWith((ref) => overrideStream),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Finder tile(String title) => find.widgetWithText(ExpansionTile, '[[$title]]');

  Finder checkboxOf(String title) =>
      find.descendant(of: tile(title), matching: find.byType(Checkbox));

  testWidgets('lista cada título con en cuántas notas está escrito, sin barra '
      'de creación mientras nada esté marcado', (tester) async {
    await pumpScreen(tester, links: [cartago, atenas]);

    expect(find.text(es.brokenLinksTitle), findsOneWidget);
    expect(tile('Cartago'), findsOneWidget);
    expect(tile('Atenas'), findsOneWidget);
    expect(find.text(es.brokenLinksWrittenIn(2)), findsOneWidget);
    expect(find.text(es.brokenLinksWrittenIn(1)), findsOneWidget);
    expect(find.text(es.brokenLinksHint), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('sin enlaces rotos muestra el estado vacío', (tester) async {
    await pumpScreen(tester);

    expect(find.text(es.brokenLinksEmpty), findsOneWidget);
    expect(find.text(es.brokenLinksSelectAll), findsNothing);
  });

  testWidgets('si no se pueden leer, lo dice', (tester) async {
    await pumpScreen(
      tester,
      overrideStream: Stream<List<BrokenLink>>.error(StateError('boom')),
    );

    expect(find.text(es.brokenLinksLoadError), findsOneWidget);
  });

  testWidgets('marcar un título muestra la barra de creación con el subtipo '
      'por defecto en viva', (tester) async {
    await pumpScreen(tester, links: [cartago, atenas]);

    await tester.tap(checkboxOf('Cartago'));
    await tester.pump();

    expect(
      find.widgetWithText(FilledButton, es.brokenLinksCreateSelected(1)),
      findsOneWidget,
    );
    final living = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, es.noteKindLiving),
    );
    expect(living.selected, isTrue);
  });

  testWidgets('seleccionar todos y quitar la selección', (tester) async {
    await pumpScreen(tester, links: [cartago, atenas, esparta]);

    await tester.tap(find.text(es.brokenLinksSelectAll));
    await tester.pump();
    expect(
      find.widgetWithText(FilledButton, es.brokenLinksCreateSelected(3)),
      findsOneWidget,
    );

    await tester.tap(find.text(es.brokenLinksClearSelection));
    await tester.pump();
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('crea las notas marcadas con el subtipo elegido, avisa cuántas '
      'y las saca de la lista', (tester) async {
    final repository = await pumpScreen(
      tester,
      links: [cartago, atenas, esparta],
    );

    await tester.tap(checkboxOf('Cartago'));
    await tester.tap(checkboxOf('Esparta'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, es.noteKindMap));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, es.brokenLinksCreateSelected(2)),
    );
    await tester.pumpAndSettle();

    // Un lote, con los títulos marcados como se escribieron y el subtipo.
    expect(repository.batches, hasLength(1));
    expect(repository.batches.single.$1, ['Cartago', 'Esparta']);
    expect(repository.batches.single.$2, NoteKind.map);
    expect(find.text(es.brokenLinksCreated(2)), findsOneWidget);
    expect(tile('Cartago'), findsNothing);
    expect(tile('Esparta'), findsNothing);
    expect(tile('Atenas'), findsOneWidget);
    // Lo creado ya no está marcado: la barra desaparece.
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('si falla, avisa y conserva la selección para reintentar', (
    tester,
  ) async {
    final repository = await pumpScreen(tester, links: [cartago, atenas]);
    repository.result = left(const Failure.unexpected(message: 'boom'));

    await tester.tap(checkboxOf('Cartago'));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, es.brokenLinksCreateSelected(1)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(es.brokenLinksCreated(1)), findsNothing);
    expect(tile('Cartago'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, es.brokenLinksCreateSelected(1)),
      findsOneWidget,
    );
  });

  testWidgets('mientras se crea, nada responde: una segunda pulsación no crea '
      'otro lote', (tester) async {
    final repository = await pumpScreen(tester, links: [cartago, atenas]);
    repository.gate = Completer<void>();

    await tester.tap(checkboxOf('Cartago'));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, es.brokenLinksCreateSelected(1)),
    );
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(tester.widget<Checkbox>(checkboxOf('Atenas')).onChanged, isNull);

    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(repository.batches, hasLength(1));
  });

  testWidgets('un grupo se despliega con las notas que lo escriben, y tocar '
      'una la abre', (tester) async {
    await pumpScreen(tester, links: [cartago]);
    expect(find.text('Diario'), findsNothing);

    await tester.tap(tile('Cartago'));
    await tester.pumpAndSettle();
    expect(find.text('Viaje'), findsOneWidget);
    expect(find.text('Diario'), findsOneWidget);

    await tester.tap(find.text('Diario'));
    await tester.pumpAndSettle();

    expect(find.text('detalle de n2'), findsOneWidget);
  });

  testWidgets('desplegar un grupo no lo marca', (tester) async {
    await pumpScreen(tester, links: [cartago]);

    await tester.tap(tile('Cartago'));
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(checkboxOf('Cartago')).value, isFalse);
    expect(find.byType(FilledButton), findsNothing);
  });
}
