import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_providers.dart';
import 'package:sinapsis/features/attachments/presentation/widgets/item_content_section.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../../support/attachment_test_doubles.dart';
import '../../../../support/in_memory_file_store.dart';

void main() {
  final item = KnowledgeItem(
    id: 'pagina',
    title: 'Roma',
    source: Source(
      id: 'src',
      kind: SourceKind.webPage,
      capturedAt: DateTime(2026, 10),
      url: 'https://es.wikipedia.org/wiki/Roma',
    ),
    processingState: ProcessingState.ready,
    createdAt: DateTime(2026, 10),
    updatedAt: DateTime(2026, 10),
  );

  late FakeAttachmentRepository repository;

  setUp(() {
    repository = FakeAttachmentRepository();
  });

  Future<void> pump(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          attachmentRepositoryProvider.overrideWithValue(repository),
          fileStoreProvider.overrideWithValue(InMemoryFileStore()),
          ...overrides,
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: ItemContentSection(item: item)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Attachment> add(
    RenditionKind kind,
    String path, {
    String? title,
    int size = 1024,
    int position = 0,
  }) => repository.addAttachment(
    itemId: item.id,
    kind: kind,
    relativePath: path,
    position: position,
    title: title,
    originUrl: 'https://upload.wikimedia.org/$path',
    sizeBytes: size,
  );

  testWidgets('sin nada bajado ni por bajar, no dibuja nada', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('item-content-section')), findsNothing);
  });

  testWidgets('agrupado por tipo, en el orden de la decisión D, con su '
      'texto y de dónde salió', (tester) async {
    final pdf = await add(
      RenditionKind.pdf,
      'originales/src/contenido/informe.pdf',
      title: 'Informe anual',
      size: 2 * 1024 * 1024,
    );
    await repository.saveText(pdf.id, 'El texto del informe.');
    await add(RenditionKind.image, 'originales/src/contenido/coliseo.jpg');
    await add(RenditionKind.audio, 'originales/src/contenido/charla.mp3');
    await add(RenditionKind.video, 'originales/src/contenido/visita.mp4');

    await pump(tester);

    expect(find.text('Contenido'), findsOneWidget);
    final groups = [
      'Documentos · 1',
      'Audios · 1',
      'Videos · 1',
      'Imágenes · 1',
    ];
    final positions = [
      for (final group in groups) tester.getTopLeft(find.text(group)).dy,
    ];
    expect(positions, orderedEquals([...positions]..sort()));
    expect(find.text('Informe anual'), findsOneWidget);
    expect(
      find.textContaining('PDF · 2,0 MB · Con texto · De upload.wikimedia.org'),
      findsOneWidget,
    );
    expect(find.textContaining('Texto pendiente'), findsNWidgets(2));
  });

  testWidgets('tocar un archivo ofrece abrirlo y leer su texto', (
    tester,
  ) async {
    final pdf = await add(
      RenditionKind.pdf,
      'originales/src/contenido/informe.pdf',
      title: 'Informe anual',
    );
    await repository.saveText(pdf.id, 'El texto del informe.');
    await pump(tester);

    await tester.tap(find.text('Informe anual'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('content-open')), findsOneWidget);
    await tester.tap(find.byKey(const Key('content-read-text')));
    await tester.pumpAndSettle();
    expect(find.textContaining('El texto del informe.'), findsOneWidget);
  });

  testWidgets('lo que quedó afuera, con «Bajar el resto»', (tester) async {
    await add(RenditionKind.image, 'originales/src/contenido/a.jpg');
    await repository.plan(item.id, [
      AttachmentCandidate(
        url: Uri.parse('https://x.org/v.mp4'),
        kind: RenditionKind.video,
        position: 1,
        expectedBytes: 700 * 1024 * 1024,
      ),
    ], status: AttachmentDownloadStatus.leftOut);
    final queue = _RecordingQueue();

    await pump(
      tester,
      overrides: [processingQueueProvider.overrideWith((ref) => queue)],
    );

    expect(
      find.textContaining(
        'Quedó afuera 1 archivo: no entraban en el tope de '
        '500,0 MB por elemento. Pesan 700,0 MB en total.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('content-download-rest')));
    await tester.pumpAndSettle();

    expect(queue.retried, [item.id]);
    expect(
      repository.downloads.single.status,
      AttachmentDownloadStatus.pending,
    );
    expect(repository.downloads.single.forced, isTrue);
  });
}

class _RecordingQueue extends Fake implements ProcessingQueueNotifier {
  final retried = <String>[];

  @override
  Future<void> retry(String itemId) async => retried.add(itemId);

  @override
  void dispose() {}
}
