import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/attachments/data/repositories/attachment_repository_impl.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/attachments/domain/repositories/attachment_repository.dart';

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
