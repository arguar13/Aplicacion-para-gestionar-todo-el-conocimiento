import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/reference/domain/usecases/attach_reference_file_usecase.dart';

import '../../../../support/in_memory_file_store.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

/// Adjuntar un archivo a una fuente `SourceKind.reference` ya existente
/// (F15, D14): promueve la fuente y la deja en cola de procesamiento, sin
/// perder lo que ya tenía.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late InMemoryFileStore files;
  late AttachReferenceFileUseCase useCase;
  final now = DateTime(2026, 9, 24, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    files = InMemoryFileStore();
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      files: files,
      clock: () => now,
    );
    useCase = AttachReferenceFileUseCase(library: library, files: files);
  });

  tearDown(() => db.close());

  Future<String> aReference() async {
    final saved = await library.save(
      KnowledgeItem(
        id: 'item-1',
        title: 'Una referencia sin texto',
        source: Source(
          id: 'item-1',
          kind: SourceKind.reference,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return saved.getRight().toNullable()!.id;
  }

  final pdfBytes = Uint8List.fromList('%PDF-1.7 contenido'.codeUnits);

  test('promueve la referencia a document', () async {
    final itemId = await aReference();

    final result = await useCase(
      itemId,
      CapturedFile(name: 'articulo.pdf', bytes: pdfBytes),
    );

    final saved = result.getRight().toNullable()!;
    expect(saved.source.kind, SourceKind.document);
  });

  test('guarda el archivo y apunta originalFilePath ahí', () async {
    final itemId = await aReference();

    final result = await useCase(
      itemId,
      CapturedFile(name: 'articulo.pdf', bytes: pdfBytes),
    );

    final saved = result.getRight().toNullable()!;
    expect(saved.source.originalFilePath, isNotNull);
    final stored = await files.read(saved.source.originalFilePath!);
    expect(stored, pdfBytes);
  });

  test('queda pendiente de procesar', () async {
    final itemId = await aReference();

    final result = await useCase(
      itemId,
      CapturedFile(name: 'articulo.pdf', bytes: pdfBytes),
    );

    expect(
      result.getRight().toNullable()!.processingState,
      ProcessingState.pending,
    );
  });

  test('no pierde el título ni la identidad del elemento', () async {
    final itemId = await aReference();

    final result = await useCase(
      itemId,
      CapturedFile(name: 'articulo.pdf', bytes: pdfBytes),
    );

    final saved = result.getRight().toNullable()!;
    expect(saved.id, itemId);
    expect(saved.title, 'Una referencia sin texto');
  });

  test('un elemento que no existe: fallo, sin tocar nada', () async {
    final result = await useCase(
      'no-existe',
      CapturedFile(name: 'articulo.pdf', bytes: pdfBytes),
    );

    expect(result.isLeft(), isTrue);
  });
}
