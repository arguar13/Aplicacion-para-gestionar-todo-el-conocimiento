import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/network/host_gate.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/attachments/data/repositories/attachment_repository_impl.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/attachments/domain/repositories/attachment_repository.dart';
import 'package:sinapsis/features/attachments/domain/services/archive_expander.dart';
import 'package:sinapsis/features/attachments/domain/services/linked_file_fetcher.dart';
import 'package:sinapsis/features/attachments/presentation/providers/platform_linked_file_fetcher.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';

/// El «Contenido» de los elementos (F30).
final attachmentRepositoryProvider = Provider<AttachmentRepository>(
  (ref) => AttachmentRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Los archivos del «Contenido» de un elemento, en vivo.
final attachmentsProvider = StreamProvider.autoDispose
    .family<List<Attachment>, String>(
      (ref, itemId) =>
          ref.watch(attachmentRepositoryProvider).watchAttachments(itemId),
    );

/// La lista de trabajo de un elemento, en vivo: lo que falta, lo que quedó
/// afuera.
final attachmentDownloadsProvider = StreamProvider.autoDispose
    .family<List<AttachmentDownload>, String>(
      (ref, itemId) =>
          ref.watch(attachmentRepositoryProvider).watchDownloads(itemId),
    );

/// De a una bajada por servidor, para toda la app: dos elementos de la misma
/// página bajando a la vez tampoco le piden de a dos al mismo servidor.
final downloadHostGateProvider = Provider<HostGate>(
  (ref) => HostGate(clock: ref.watch(clockProvider)),
);

/// Quien baja lo que enlaza una página, o `null` donde no se puede (la web).
final linkedFileFetcherProvider = Provider<LinkedFileFetcher?>(
  (ref) => createLinkedFileFetcher(
    files: ref.watch(fileStoreProvider),
    hosts: ref.watch(downloadHostGateProvider),
    freeBytes: ref.watch(captureFreeBytesProvider),
    options: BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: const {
        'User-Agent': 'Sinapsis/0.1 (+lector de contenido personal)',
      },
    ),
  ),
);

/// Quien descomprime los `.zip` del «Contenido», o `null` en la web.
final archiveExpanderProvider = Provider<ArchiveExpander?>(
  (ref) => createArchiveExpander(files: ref.watch(fileStoreProvider)),
);
