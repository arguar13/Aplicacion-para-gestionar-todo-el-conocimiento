import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/capture/data/adapters/file_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/plain_text_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/social_post_link_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/web_link_adapter.dart';
import 'package:sinapsis/features/capture/data/adapters/youtube_link_adapter.dart';
import 'package:sinapsis/features/capture/data/services/pdf_document_scan_assembler.dart';
import 'package:sinapsis/features/capture/data/services/receive_sharing_intent_listener.dart';
import 'package:sinapsis/features/capture/data/services/system_camera_chooser.dart';
import 'package:sinapsis/features/capture/data/services/system_file_chooser.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter_registry.dart';
import 'package:sinapsis/features/capture/domain/services/camera_chooser.dart';
import 'package:sinapsis/features/capture/domain/services/document_scan_assembler.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';
import 'package:sinapsis/features/capture/domain/services/shared_content_listener.dart';
import 'package:sinapsis/features/capture/domain/usecases/capture_item_usecase.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_compaction_providers.dart';

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

/// Cuánto espacio libre queda en la carpeta de la app, donde el almacén
/// guarda los originales: el límite real para guardar un archivo (F21).
/// Donde no se puede saber —la web— es `null`, y no se frena nada por no
/// saberlo.
///
/// Un provider propio para que las pruebas lo reemplacen: medirlo le
/// pregunta al sistema operativo, y en una prueba no hay a quién.
final captureFreeBytesProvider = Provider<Future<int?> Function()>((ref) {
  final probe = ref.watch(freeSpaceProbeProvider);
  return () async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return await probe.freeBytesAt(directory.path);
      // Sin carpeta de documentos —la web— no hay espacio que medir: se
      // sigue sin el control.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  };
});

final captureItemUseCaseProvider = Provider<CaptureItemUseCase>((ref) {
  return CaptureItemUseCase(
    registry: ref.watch(sourceAdapterRegistryProvider),
    repository: ref.watch(libraryRepositoryProvider),
    freeBytes: ref.watch(captureFreeBytesProvider),
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

/// Junta las páginas de un escaneo en un solo documento. Sin necesidad de
/// sobreescribirlo en las pruebas: a diferencia del selector de archivos o
/// la cámara, arma el PDF en el propio proceso de Dart, sin pedirle nada al
/// sistema operativo.
final documentScanAssemblerProvider = Provider<DocumentScanAssembler>(
  (ref) => const PdfDocumentScanAssembler(),
);

/// Lo que trae el botón de compartir de otra app.
///
/// Se sobreescribe en las pruebas: sin un sistema operativo real del otro
/// lado, el plugin no tiene con qué contestar.
final sharedContentListenerProvider = Provider<SharedContentListener>(
  (ref) => const ReceiveSharingIntentListener(),
);
