import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_text_refresh.dart';

/// El texto nuevo de un video vuelto a extraer desde Procesado va a su
/// documento (F45, paso 4): lo pedido se guarda, y se cumple cuando la cola
/// termina —solo si llegó en su idioma—.
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

  KnowledgeItem video(String id, String text) => KnowledgeItem(
    id: id,
    title: title,
    source: Source(
      id: id,
      kind: SourceKind.youtube,
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
}
