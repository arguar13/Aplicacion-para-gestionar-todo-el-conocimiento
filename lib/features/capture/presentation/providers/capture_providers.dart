import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/capture/data/adapters/file_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/plain_text_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/social_post_link_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/web_link_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/youtube_link_adapter.dart';
import 'package:sinapsis/features/capture/data/services/receive_sharing_intent_listener.dart';
import 'package:sinapsis/features/capture/data/services/system_camera_chooser.dart';
import 'package:sinapsis/features/capture/data/services/system_file_chooser.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter_registry.dart';
import 'package:sinapsis/features/capture/domain/services/camera_chooser.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';
import 'package:sinapsis/features/capture/domain/services/shared_content_listener.dart';
import 'package:sinapsis/features/capture/domain/usecases/capture_item_usecase.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';

/// El orden de esta lista es parte del comportamiento, no un detalle de
/// escritura: el registro se queda con el primero que acepte.
///
/// - YouTube y las publicaciones sociales antes que el enlace genérico,
///   porque los dos aceptarían la misma dirección y el específico sabe más.
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
    SocialPostLinkAdapter(ids: ids, clock: clock),
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

/// El selector de archivos del sistema.
///
/// Se sobreescribe en las pruebas: abrir el selector de verdad necesita un
/// sistema operativo con una ventana, y es lo único de este camino que no se
/// puede probar.
final fileChooserProvider = Provider<FileChooser>(
  (ref) => const SystemFileChooser(),
);

/// La cámara del sistema operativo.
///
/// Se sobreescribe en las pruebas, por la misma razón que
/// [fileChooserProvider]: abrirla de verdad necesita una cámara real detrás.
final cameraChooserProvider = Provider<CameraChooser>(
  (ref) => const SystemCameraChooser(),
);

/// Lo que trae el botón de compartir de otra app.
///
/// Se sobreescribe en las pruebas: sin un sistema operativo real del otro
/// lado, el plugin no tiene con qué contestar.
final sharedContentListenerProvider = Provider<SharedContentListener>(
  (ref) => const ReceiveSharingIntentListener(),
);
