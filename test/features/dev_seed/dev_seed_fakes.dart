import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/features/dev_seed/domain/repositories/sample_library_ledger.dart';
import 'package:sinapsis/features/dev_seed/domain/services/sample_file_downloader.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

final _capturedAt = DateTime(2026, 10, 3, 9);

/// La captura de mentira: guarda en memoria lo que le piden y devuelve un
/// elemento pendiente, salvo para las direcciones o títulos de [failFor],
/// que devuelven un fallo como el de verdad.
class FakeCaptureItem implements UseCase<KnowledgeItem, CaptureRequest> {
  FakeCaptureItem({this.failFor = const {}});

  final Set<String> failFor;
  final requests = <CaptureRequest>[];

  @override
  Future<Either<Failure, KnowledgeItem>> call(CaptureRequest params) async {
    requests.add(params);
    final key = switch (params) {
      TextCapture(:final rawInput) => rawInput,
      FileCapture(:final title) => title ?? '',
    };
    if (failFor.contains(key)) {
      return left(const Failure.cache(message: 'No se pudo guardar.'));
    }
    final id = 'item-${requests.length}';
    return right(
      KnowledgeItem(
        id: id,
        title: key,
        source: Source(
          id: 'src-${requests.length}',
          kind: params is FileCapture
              ? params.file.format.sourceKind
              : SourceKind.webPage,
          capturedAt: _capturedAt,
        ),
        processingState: ProcessingState.pending,
        createdAt: _capturedAt,
        updatedAt: _capturedAt,
      ),
    );
  }
}

/// El repositorio de mentira: solo guarda, que es lo único que la carga le
/// pide —para las notas—.
class FakeLibraryRepository extends Fake implements LibraryRepository {
  final saved = <KnowledgeItem>[];

  @override
  Future<Either<Failure, KnowledgeItem>> save(KnowledgeItem item) async {
    saved.add(item);
    return right(item);
  }
}

/// Lo ya cargado, en memoria.
class InMemorySampleLibraryLedger implements SampleLibraryLedger {
  final ids = <String>{};

  @override
  Set<String> loadedIds() => {...ids};

  @override
  Future<void> markLoaded(String id) async => ids.add(id);
}

/// Los primeros bytes de cada tipo, para que el archivo bajado se reconozca
/// por su firma como el de verdad.
Uint8List bytesFor(SampleFileKind kind) => Uint8List.fromList([
  ...switch (kind) {
    SampleFileKind.pdf => ascii.encode('%PDF-1.7\n'),
    SampleFileKind.epub => [0x50, 0x4B, 0x03, 0x04],
    SampleFileKind.text => utf8.encode('Texto de ejemplo.\n'),
    SampleFileKind.audio => ascii.encode('ID3'),
    SampleFileKind.image => [0xFF, 0xD8, 0xFF, 0xE0],
  },
  ...List.filled(32, 0x20),
]);

/// El bajador de mentira: entrega en memoria los bytes de [bytesFor], salvo
/// lo que diga [overrides]; falla para los ids de [failFor]; y, para los de
/// [blockUntilCancelled], se queda esperando hasta que se cancele, como una
/// bajada lenta.
class FakeSampleFileDownloader implements SampleFileDownloader {
  FakeSampleFileDownloader({
    this.failFor = const {},
    this.blockUntilCancelled = const {},
    this.overrides = const {},
  });

  final Set<String> failFor;
  final Set<String> blockUntilCancelled;
  final Map<String, Uint8List> overrides;

  final downloaded = <String>[];
  final discarded = <String>[];
  int leftoversCleared = 0;

  /// Se completa cuando empieza una bajada que se queda esperando.
  final blocked = Completer<void>();

  @override
  Future<void> clearLeftovers() async => leftoversCleared++;

  @override
  Future<DownloadedSample> download(
    SampleFile resource, {
    required CancellationSignal cancellation,
  }) async {
    cancellation.throwIfCancelled();
    if (blockUntilCancelled.contains(resource.id)) {
      if (!blocked.isCompleted) blocked.complete();
      await cancellation.whenCancelled;
      throw const ProcessingCancelledException();
    }
    if (failFor.contains(resource.id)) {
      throw const SampleDownloadException('El servidor respondió 404.');
    }
    downloaded.add(resource.id);
    return DownloadedSample(
      file: CapturedFile(
        name: resource.fileName,
        bytes: overrides[resource.id] ?? bytesFor(resource.kind),
      ),
      discard: () async => discarded.add(resource.id),
    );
  }
}
