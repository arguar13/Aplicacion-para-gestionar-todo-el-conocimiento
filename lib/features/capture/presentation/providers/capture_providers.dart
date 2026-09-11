import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/capture/data/adapters/file_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/plain_text_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/web_link_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/youtube_link_adapter.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter_registry.dart';
import 'package:sinapsis/features/capture/domain/usecases/capture_item_usecase.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';

/// El orden de esta lista es parte del comportamiento, no un detalle de
/// escritura: el registro se queda con el primero que acepte.
///
/// - YouTube antes que el enlace genérico, porque los dos aceptarían la misma
///   dirección y el específico sabe más.
/// - El de archivos antes que los de texto: es el único que mira si la
///   captura trae un archivo, y los demás miran el texto, que en ese caso
///   está vacío.
/// - El de texto suelto al final, porque acepta cualquier texto. Es el que
///   convierte "no reconocí esto" en "lo guardo como nota".
final sourceAdapterRegistryProvider = Provider<SourceAdapterRegistry>((ref) {
  final ids = ref.watch(idGeneratorProvider);
  final clock = ref.watch(clockProvider);

  return SourceAdapterRegistry([
    FileAdapter(files: ref.watch(fileStoreProvider), ids: ids, clock: clock),
    YouTubeLinkAdapter(ids: ids, clock: clock),
    WebLinkAdapter(ids: ids, clock: clock),
    PlainTextAdapter(ids: ids, clock: clock),
  ]);
});

final captureItemUseCaseProvider = Provider<CaptureItemUseCase>((ref) {
  return CaptureItemUseCase(
    registry: ref.watch(sourceAdapterRegistryProvider),
    repository: ref.watch(libraryRepositoryProvider),
  );
});
