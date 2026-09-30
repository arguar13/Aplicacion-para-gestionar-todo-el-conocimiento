import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/transform/data/transformers/audio_transcript_transformer.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_checkpoints.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';
import 'package:sinapsis/features/transform/domain/transformers/transform_context.dart';

import '../../../../support/fake_audio_transcriber.dart';
import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

void main() {
  final now = DateTime(2026, 9, 11, 10);
  late InMemoryFileStore files;
  late FakeAudioTranscriber transcriber;
  late AudioTranscriptTransformer transformer;

  setUp(() {
    files = InMemoryFileStore();
    transcriber = FakeAudioTranscriber();
    transformer = AudioTranscriptTransformer(
      transcriber: transcriber,
      files: files,
      ids: FakeIdGenerator(),
      clock: () => now,
    );
  });

  Future<KnowledgeItem> seed({
    SourceKind kind = SourceKind.audio,
    bool withFile = true,
  }) async {
    final path = withFile
        ? await files.save(
            bytes: Uint8List.fromList([0x49, 0x44, 0x33]),
            suggestedName: 'nota.mp3',
            id: 'src-1',
          )
        : null;

    return KnowledgeItem(
      id: 'item-1',
      title: 'Nota de voz',
      source: Source(
        id: 'src-1',
        kind: kind,
        capturedAt: now,
        originalFilePath: path,
      ),
      processingState: ProcessingState.pending,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('a qué se aplica', () {
    test('a un audio con archivo y sin contenido', () async {
      expect(transformer.canTransform(await seed()), isTrue);
    });

    test('a un video con archivo y sin contenido', () async {
      final item = await seed(kind: SourceKind.video);

      expect(transformer.canTransform(item), isTrue);
    });

    test('NO a algo que no es audio ni video', () async {
      final item = await seed(kind: SourceKind.document);

      expect(transformer.canTransform(item), isFalse);
    });

    test('NO a un audio sin archivo guardado', () async {
      final item = await seed(withFile: false);

      expect(transformer.canTransform(item), isFalse);
    });

    test('NO a uno que ya se transcribió', () async {
      // Sin esto, cada pasada de la cola repetiría la misma transcripción
      // sobre el mismo archivo.
      transcriber.text = 'hola, esto es una prueba';
      final item = await seed();
      final transcripto = await transformer.transform(item);

      expect(transformer.canTransform(transcripto), isFalse);
    });
  });

  group('lo que guarda', () {
    test('el texto transcripto queda como contenido buscable', () async {
      transcriber.text = 'Recordatorio: comprar leche y pan';
      final item = await seed();

      final result = await transformer.transform(item);

      expect(result.renditions, hasLength(1));
      expect(result.renditions.single.kind, RenditionKind.plainText);
      expect(result.searchableText, contains('comprar leche'));
    });

    test('sin texto transcripto, el elemento queda igual', () async {
      // Un video sin diálogo, música instrumental, silencio: no es un
      // error, es el caso normal.
      final item = await seed();

      expect(await transformer.transform(item), item);
    });

    test('se le pide transcribir la ruta absoluta, no la relativa que '
        'guarda la base', () async {
      final item = await seed();

      await transformer.transform(item);

      expect(transcriber.requested.single, startsWith('/memoria/'));
      expect(transcriber.requested.single, isNot(item.source.originalFilePath));
    });

    test('si el archivo ya no está, lo dice con claridad', () async {
      // Alguien vació el almacenamiento de la app desde los ajustes del
      // sistema. Es distinto de un audio corrupto y conviene distinguirlo.
      final item = await seed();
      await files.delete(item.source.originalFilePath!);

      expect(
        () => transformer.transform(item),
        throwsA(isA<MissingOriginalFileException>()),
      );
    });

    test('si el modelo no está descargado, lo dice con claridad', () async {
      transcriber.error = const WhisperModelNotReadyException();
      final item = await seed();

      expect(
        () => transformer.transform(item),
        throwsA(isA<WhisperModelNotReadyException>()),
      );
    });
  });

  test('los tramos se guardan y se retoman para este elemento, con el '
      'contexto de la cola (F21)', () async {
    final checkpoints = _MemoryCheckpoints();
    await checkpoints.save(
      'item-1',
      ProcessingCheckpointKind.transcriptWindow,
      position: 0,
      content: 'de antes',
    );
    final context = CancellableTransformContext(CancellationSignal());

    await AudioTranscriptTransformer(
      transcriber: transcriber,
      files: files,
      ids: FakeIdGenerator(),
      clock: () => now,
      checkpoints: checkpoints,
    ).transform(await seed(), context: context);

    final session = transcriber.sessions.single;
    expect(session.workKey, 'item-1');
    expect(identical(session.context, context), isTrue);
    expect(await session.transcribedSegments(), {0: 'de antes'});

    await session.saveSegment(1, 'nuevo');
    expect(
      await checkpoints.load(
        'item-1',
        ProcessingCheckpointKind.transcriptWindow,
      ),
      {0: 'de antes', 1: 'nuevo'},
    );
  });

  test('lo guardado con los tramos de 29 s de antes de F22 no se retoma: '
      'son otros tramos, y mezclarlos daría texto repetido', () async {
    final checkpoints = _MemoryCheckpoints();
    await checkpoints.save(
      'item-1',
      ProcessingCheckpointKind.transcriptSegment,
      position: 0,
      content: 'tramo viejo de 29 s',
    );

    await AudioTranscriptTransformer(
      transcriber: transcriber,
      files: files,
      ids: FakeIdGenerator(),
      clock: () => now,
      checkpoints: checkpoints,
    ).transform(await seed());

    expect(await transcriber.sessions.single.transcribedSegments(), isEmpty);
  });
}

/// El avance guardado, en memoria.
class _MemoryCheckpoints implements ProcessingCheckpoints {
  final _saved = <(String, ProcessingCheckpointKind), Map<int, String>>{};

  @override
  Future<Map<int, String>> load(
    String itemId,
    ProcessingCheckpointKind kind,
  ) async => {...?_saved[(itemId, kind)]};

  @override
  Future<void> save(
    String itemId,
    ProcessingCheckpointKind kind, {
    required int position,
    required String content,
  }) async => (_saved[(itemId, kind)] ??= {})[position] = content;
}
