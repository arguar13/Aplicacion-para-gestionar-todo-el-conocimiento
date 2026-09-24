import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../support/library_harness.dart';

/// Un cuaderno funciona como buscador acotado del chat SIN el modelo de
/// lenguaje descargado (F16, D1; F16 16.1, 8/8): confirma, con un test
/// dedicado, el camino que ya deja construido el commit 7 —acotar no
/// depende de tener el modelo, igual que el modo «con mi bóveda» sin
/// cuaderno ya servía de buscador desde F9 (principio 4: degradar antes
/// que fallar).
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpChat(WidgetTester tester) async {
    // Sin `chatModelReady`: por defecto es `false` — es justo lo que este
    // test necesita confirmar.
    harness = await LibraryHarness.create();
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
  }

  Future<void> selectScope(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const Key('chat-notebook-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'sin el modelo descargado, elegir un cuaderno igual acota la búsqueda',
    (tester) async {
      await pumpChat(tester);
      // Título y cuerpo distintos: si coincidieran, la tarjeta de fuente
      // mostraría el mismo texto dos veces —título y fragmento citado— y
      // `find.text` dejaría de ser único.
      await harness.capture('Adentro del cuaderno\n\nhabla de lo de adentro');
      await harness.capture('Afuera del cuaderno\n\nhabla de lo de afuera');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final inside = items.firstWhere((i) => i.title == 'Adentro del cuaderno');

      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Mi cuaderno', mode: NotebookMode.manual);
      await harness.container
          .read(notebookRepositoryProvider)
          .addItem(notebookId: notebook.id, itemId: inside.id);
      await tester.pumpAndSettle();

      // Sin acotar todavía: la palabra "cuaderno" está en los dos títulos.
      await send(tester, 'cuaderno');
      expect(find.text('Adentro del cuaderno'), findsOneWidget);
      expect(find.text('Afuera del cuaderno'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_comment_outlined));
      await tester.pumpAndSettle();
      await selectScope(tester, 'Mi cuaderno');
      await send(tester, 'cuaderno');

      // Acotado, solo el de adentro — sin haber tocado el modelo en ningún
      // momento: no hay `chatModelReady` en este test.
      expect(find.text('Adentro del cuaderno'), findsOneWidget);
      expect(find.text('Afuera del cuaderno'), findsNothing);
      expect(harness.chatModel.vaultConversations, isEmpty);
    },
  );

  testWidgets(
    'sin el modelo descargado, un cuaderno sin nada adentro dice que no '
    'encontró nada —no es que la búsqueda haya fallado—',
    (tester) async {
      await pumpChat(tester);
      await harness.capture('Lo único que hay\n\ncon algo de cuerpo');

      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Cuaderno vacío', mode: NotebookMode.manual);
      await tester.pumpAndSettle();

      await selectScope(tester, notebook.name);
      await send(tester, 'lo único');

      expect(find.text('Lo único que hay'), findsNothing);
      expect(find.text(es.chatNoSourcesFound), findsOneWidget);
    },
  );

  testWidgets(
    'un cuaderno por consulta también acota la búsqueda sin el modelo',
    (tester) async {
      await pumpChat(tester);
      await harness.capture('Adentro por consulta\n\nhabla de una consulta');
      await harness.capture('Afuera de la consulta\n\nhabla de otra cosa');

      // La consulta de un cuaderno por consulta sale de una vista guardada
      // (16.3): esa vía nunca lleva `ids` —`libraryQueryToJson` los deja
      // afuera a propósito, es de la sesión, no del filtro que se nombra—,
      // así que lo que de verdad acota acá es el propio filtro de texto.
      await harness.container
          .read(notebookRepositoryProvider)
          .create(
            name: 'Por consulta',
            mode: NotebookMode.query,
            query: const LibraryQuery(searchText: 'adentro'),
          );
      await tester.pumpAndSettle();

      await selectScope(tester, 'Por consulta');
      await send(tester, 'consulta');

      expect(find.text('Adentro por consulta'), findsOneWidget);
      expect(find.text('Afuera de la consulta'), findsNothing);
      expect(harness.chatModel.vaultConversations, isEmpty);
    },
  );
}
