import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_text_refresh.dart';

/// El texto nuevo de una fuente vuelta a extraer desde su documento procesado
/// va a ese documento (F45, paso 4): lo pedido se guarda y se cumple cuando la
/// cola termina —en un video, solo si llegó en su idioma—; lo que la persona
/// editó se queda, y lo que la IA solo ordenó se renueva y se vuelve a
/// ordenar.
void main() {
  final now = DateTime(2026, 10, 30, 12);
  const title =
      'Las reliquias de San Francisco de Asís que han fascinado al mundo';
  const spanish =
      '[0:00] Las reliquias de San Francisco de Asís han fascinado al mundo, '
      'y en este video vamos a ver por qué son tan importantes para los '
      'fieles y cómo se conservan desde hace más de ochocientos años.';
  const arabic =
      '[0:00] بقايا القديس فرنسيس الأسيزي التي أذهلت العالم\n'
      '[0:07] في هذا الفيديو نتحدث عن تاريخ هذه الآثار المقدسة';

  late List<String> updated;
  late ProcessedTextRefresh refresh;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    updated = [];
    refresh = ProcessedTextRefresh(
      preferences: await SharedPreferences.getInstance(),
      update: (sourceId) async {
        updated.add(sourceId);
        return right(null);
      },
    );
  });

  KnowledgeItem video(
    String id,
    String text, {
    SourceKind kind = SourceKind.youtube,
  }) => KnowledgeItem(
    id: id,
    title: title,
    source: Source(
      id: id,
      kind: kind,
      capturedAt: now,
      url: 'https://youtu.be/dQw4w9WgXcQ',
      language: 'es',
    ),
    processingState: ProcessingState.ready,
    createdAt: now,
    updatedAt: now,
    renditions: [
      Rendition.text(
        id: 'r-$id',
        itemId: id,
        kind: RenditionKind.plainText,
        content: text,
        isPrimary: true,
        createdAt: now,
      ),
    ],
  );

  test(
    'lo pedido se guarda y se cumple al llegar el texto en su idioma',
    () async {
      await refresh.request('v');
      expect(refresh.pending, {'v'});

      await refresh.afterProcessed(video('v', spanish));

      expect(updated, ['v']);
      expect(refresh.pending, isEmpty);
    },
  );

  test('si el texto nuevo llegó en otro idioma otra vez, no se trae: el '
      'documento sigue ofreciendo volver a extraer', () async {
    await refresh.request('v');

    await refresh.afterProcessed(video('v', arabic));

    expect(updated, isEmpty);
    expect(refresh.pending, isEmpty);
  });

  test('lo que no se pidió desde Procesado no se toca', () async {
    await refresh.request('otro');

    await refresh.afterProcessed(video('v', spanish));

    expect(updated, isEmpty);
    expect(refresh.pending, {'otro'});
  });

  test('traerlo ahora dice si se pudo', () async {
    final failing = ProcessedTextRefresh(
      preferences: await SharedPreferences.getInstance(),
      update: (_) async =>
          left(const Failure.unexpected(message: 'la base falló')),
    );

    expect(await refresh.updateNow('v'), isTrue);
    expect(await failing.updateNow('v'), isFalse);
  });

  test('en un audio o un documento el idioma no se compara: el texto nuevo '
      'llega igual', () async {
    await refresh.request('clase');

    await refresh.afterProcessed(
      video('clase', arabic, kind: SourceKind.audio),
    );

    expect(updated, ['clase']);
  });

  test('si el cambio no se hizo, lo pedido se olvida', () async {
    await refresh.request('v');
    await refresh.cancel('v');

    await refresh.afterProcessed(video('v', spanish));

    expect(updated, isEmpty);
    expect(refresh.pending, isEmpty);
  });

  test('lo guardado que no se puede leer no toca ningún documento', () async {
    SharedPreferences.setMockInitialValues({
      kProcessedTextRefreshKey: 'no es un mapa',
    });
    final broken = ProcessedTextRefresh(
      preferences: await SharedPreferences.getInstance(),
      update: (sourceId) async {
        updated.add(sourceId);
        return right(null);
      },
    );

    await broken.afterProcessed(video('v', spanish));

    expect(updated, isEmpty);
  });

  group('las páginas editadas', () {
    // El texto viejo de la fuente: dos páginas, de 0 a 20 y de 20 a 45.
    const oldSource = 'Roma fundó colonias.Cartago perdió la guerra.';

    ProcessedPart page(String id, String content, int start, int end) =>
        ProcessedPart(
          id: id,
          documentId: processedDocumentIdFor('libro'),
          section: ProcessedSection.text,
          position: 0,
          content: content,
          origin: ProcessedPartOrigin.copied,
          edited: true,
          createdAt: now,
          updatedAt: now,
          sourceRenditionId: 'r-libro',
          sourceStart: start,
          sourceEnd: end,
        );

    late List<ProcessedPart> pages;
    late List<String> released;
    late List<String> retidied;
    late ProcessedTextRefresh following;

    setUp(() async {
      released = [];
      retidied = [];
      // La primera, ordenada por la IA: los mismos renglones, partidos de
      // otra forma. La segunda, editada por la persona: otra palabra.
      pages = [
        page('ordenada', 'Roma fundó\ncolonias.', 0, 20),
        page('editada', 'Cartago ganó la guerra.', 20, 45),
      ];
      following = ProcessedTextRefresh(
        preferences: await SharedPreferences.getInstance(),
        update: (sourceId) async {
          updated.add(sourceId);
          return right(null);
        },
        textPages: (_) async => pages,
        sourceText: (_) async => oldSource,
        release: (part) async => released.add(part.id),
        retidy: (documentId) async => retidied.add(documentId),
        worker: <Q, R>(work, message, {required size}) async => work(message),
      );
    });

    test('lo que la IA solo ordenó vuelve a la fuente, se renueva y se '
        'vuelve a ordenar; lo que editó la persona se queda', () async {
      await following.request('libro');
      await following.afterProcessed(
        video('libro', 'Roma fundó colonias.', kind: SourceKind.document),
      );

      expect(released, ['ordenada']);
      expect(updated, ['libro']);
      expect(retidied, [processedDocumentIdFor('libro')]);
    });

    test('una página ordenada que la persona tocó después del pedido es '
        'suya: se queda', () async {
      await following.request('libro');
      pages = [
        page('ordenada', 'Roma fundó\ncolonias, dijo.', 0, 20),
        pages.last,
      ];
      await following.afterProcessed(
        video('libro', 'Roma fundó colonias.', kind: SourceKind.document),
      );

      expect(released, isEmpty);
      expect(updated, ['libro']);
      // Nada volvió a la fuente: nada que volver a ordenar.
      expect(retidied, isEmpty);
    });

    test('traerlo ahora, sin texto viejo con qué comparar, no renueva '
        'ninguna página editada', () async {
      await following.updateNow('libro');

      expect(released, isEmpty);
      expect(updated, ['libro']);
    });
  });
}
