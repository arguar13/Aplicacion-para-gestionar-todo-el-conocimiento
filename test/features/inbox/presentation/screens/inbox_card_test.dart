import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_providers.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La tarjeta de la Bandeja (F30, decisión 68): el texto limpio y los datos de
/// lo que se va a triar —autor, fecha, sitio, extensión, idioma—, y nunca un
/// reproductor.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  final now = DateTime(2026, 10, 1, 9);

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Rendition text(String id, String content) => Rendition.text(
    id: 'texto-$id',
    itemId: id,
    kind: RenditionKind.plainText,
    content: content,
    isPrimary: true,
    createdAt: now,
  );

  Future<KnowledgeItem> save(KnowledgeItem item) async {
    await harness.container.read(libraryRepositoryProvider).save(item);
    return item;
  }

  Future<void> pumpInbox(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const InboxScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('una página: el texto sin su Markdown, con el autor, la fecha '
      'y el sitio', (tester) async {
    await save(
      KnowledgeItem(
        id: 'pagina',
        title: 'Roma',
        source: Source(
          id: 'pagina',
          kind: SourceKind.webPage,
          capturedAt: now,
          url: 'https://www.ejemplo.org/roma',
          authorName: 'Mary Beard',
          publishedAt: DateTime(2019, 3, 14),
          language: 'es',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          Rendition.text(
            id: 'texto',
            itemId: 'pagina',
            kind: RenditionKind.markdown,
            content:
                '[![](//upload.ejemplo.org/roma.jpg)](/wiki/Archivo:Roma)\n\n'
                'Roma fue una **ciudad** que se hizo imperio.',
            isPrimary: true,
            createdAt: now,
          ),
        ],
      ),
    );

    await pumpInbox(tester);

    expect(find.byKey(const Key('pending-facts')), findsOneWidget);
    expect(find.text('Mary Beard'), findsOneWidget);
    expect(find.text('ejemplo.org'), findsOneWidget);
    expect(find.text('Español'), findsOneWidget);
    expect(find.textContaining('2019'), findsOneWidget);
    final excerpt = tester.widget<Text>(
      find.byKey(const Key('pending-excerpt')),
    );
    expect(excerpt.data, 'Roma fue una ciudad que se hizo imperio.');
  });

  testWidgets('un audio con su transcripción: el texto sin los minutos y lo '
      'que dura, sin ningún reproductor', (tester) async {
    await save(
      KnowledgeItem(
        id: 'audio',
        title: 'Una clase',
        source: Source(
          id: 'audio',
          kind: SourceKind.audio,
          capturedAt: now,
          originalFilePath: 'originales/audio/clase.m4a',
          language: 'es',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          text('audio', '[0:00] Buenas tardes a todos.\n[0:05] Empezamos.'),
        ],
      ),
    );
    // Guardar el elemento ya lo fragmentó: el último fragmento termina a los
    // 42 minutos.
    await harness.database.customStatement(
      'UPDATE chunks SET start_ms = 0, end_ms = ? WHERE item_id = ?',
      [42 * 60 * 1000, 'audio'],
    );

    await pumpInbox(tester);

    final excerpt = tester.widget<Text>(
      find.byKey(const Key('pending-excerpt')),
    );
    expect(excerpt.data, 'Buenas tardes a todos.\nEmpezamos.');
    expect(find.text('42 min'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('un PDF dice cuántas páginas tiene', (tester) async {
    await save(
      KnowledgeItem(
        id: 'libro',
        title: 'Historia de Roma',
        source: Source(
          id: 'libro',
          kind: SourceKind.document,
          capturedAt: now,
          originalFilePath: 'originales/libro/roma.pdf',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [text('libro', 'Primera página.\nSegunda página.')],
      ),
    );
    // Guardar el elemento ya lo fragmentó: cada fragmento sabe su página.
    await harness.database.customStatement(
      "UPDATE chunks SET page_number = 248 WHERE item_id = 'libro'",
    );

    await pumpInbox(tester);

    expect(find.text('248 páginas'), findsOneWidget);
  });

  testWidgets('una página sin texto propio muestra el de un archivo de su '
      '«Contenido», y de cuál es', (tester) async {
    final item = await save(
      KnowledgeItem(
        id: 'publicacion',
        title: 'Una publicación',
        source: Source(
          id: 'publicacion',
          kind: SourceKind.socialPost,
          capturedAt: now,
          url: 'https://social.ejemplo.org/p/1',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final attachments = harness.container.read(attachmentRepositoryProvider);
    final photo = await attachments.addAttachment(
      itemId: item.id,
      kind: RenditionKind.image,
      relativePath: 'originales/publicacion/contenido/cartel.jpg',
      position: 0,
      title: 'cartel.jpg',
    );
    await attachments.saveText(photo.id, 'Se vende bicicleta rodado 28.');

    await pumpInbox(tester);

    expect(find.text(es.inboxTextFromAttachment('cartel.jpg')), findsOneWidget);
    final excerpt = tester.widget<Text>(
      find.byKey(const Key('pending-excerpt')),
    );
    expect(excerpt.data, 'Se vende bicicleta rodado 28.');
    // Sin texto propio no hay de dónde extraer notas: el botón no se ofrece.
    expect(find.text(es.inboxActionExtract), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.ancestor(
              of: find.text(es.inboxActionExtract),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });
}
