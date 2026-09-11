import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';

/// Un archivo traído por el usuario: un PDF, un libro, un documento de Word,
/// una foto, un audio.
///
/// Hace algo que ningún otro adaptador hace: **copia el archivo al almacén**
/// antes de guardar nada. Los demás guardan un enlace, y el original sigue
/// estando en internet. Acá el archivo *es* la fuente — no hay ningún sitio al
/// que volver si se pierde— y además la ruta por la que llegó suele ser
/// temporal: el sistema la borra en cuanto la app que lo compartió termina.
///
/// El texto se extrae después, en la etapa de transformación. Acá se guarda
/// el archivo y lo que se puede saber sin abrirlo, que es de qué formato es y
/// cómo se llamaba.
class FileAdapter implements SourceAdapter {
  const FileAdapter({
    required FileStore files,
    required IdGenerator ids,
    required Clock clock,
  }) : _files = files,
       _ids = ids,
       _clock = clock;

  final FileStore _files;
  final IdGenerator _ids;
  final Clock _clock;

  /// Qué produce **por defecto**.
  ///
  /// La clase real depende del archivo: un PDF es un documento y una foto es
  /// una imagen. Esto es lo que la pantalla de captura muestra como
  /// anticipo antes de mirar los bytes; [adapt] resuelve la de verdad.
  @override
  SourceKind get producesKind => SourceKind.document;

  @override
  bool canHandle(CaptureRequest request) => request.asFile != null;

  @override
  Future<KnowledgeItem> adapt(CaptureRequest request) async {
    final file = request.asFile!;
    final now = _clock();
    final sourceId = _ids.next();

    // Se copia primero y se guarda después. Si la copia falla —disco lleno,
    // permisos— el elemento no llega a existir, en vez de quedar una fila
    // apuntando a un archivo que no está.
    final storedPath = await _files.save(
      bytes: file.bytes,
      suggestedName: file.name,
      id: sourceId,
    );

    final format = file.format;

    return KnowledgeItem(
      id: _ids.next(),
      title: request.title?.trim().isNotEmpty ?? false
          ? request.title!.trim()
          : titleFromFileName(file.name),
      subtitle: describeFormat(format),
      notes: request.note,
      source: Source(
        id: sourceId,
        kind: format.sourceKind,
        capturedAt: now,
        // Sin `url`: no hay ningún original en la web al que volver. Lo que
        // hace las veces de origen es el archivo guardado.
        originalFilePath: storedPath,
      ),
      processingState: ProcessingState.pending,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Un título provisional sacado del nombre del archivo.
///
/// Vale hasta que la extracción traiga el título real —el de los metadatos de
/// un EPUB, el de la primera línea de un PDF—. Mientras tanto tiene que dejar
/// la lista legible: `informe_final_v3_DEFINITIVO.pdf` se lee mucho mejor
/// como "Informe final v3 DEFINITIVO".
String titleFromFileName(String name) {
  final withoutExtension = p.basenameWithoutExtension(name).trim();
  if (withoutExtension.isEmpty) return 'Archivo sin nombre';

  final words = withoutExtension.replaceAll(RegExp('[-_]+'), ' ').trim();
  if (words.isEmpty) return 'Archivo sin nombre';

  return words[0].toUpperCase() + words.substring(1);
}

/// Cómo se nombra un formato en el subtítulo de la lista.
///
/// No pasa por el sistema de traducciones a propósito, igual que los títulos
/// provisionales: esto queda guardado en el elemento, no dibujado en la
/// pantalla. Si dependiera del idioma de la interfaz, cambiar de idioma
/// reescribiría lo que el usuario ya tiene guardado.
String describeFormat(FileFormat format) => switch (format) {
  FileFormat.pdf => 'PDF',
  FileFormat.epub => 'EPUB',
  FileFormat.docx => 'Word',
  FileFormat.plainText => 'Texto',
  FileFormat.markdown => 'Markdown',
  FileFormat.jpeg ||
  FileFormat.png ||
  FileFormat.gif ||
  FileFormat.webp ||
  FileFormat.heic => 'Imagen',
  FileFormat.mp3 ||
  FileFormat.ogg ||
  FileFormat.wav ||
  FileFormat.flac => 'Audio',
  FileFormat.mpeg4 => 'Video',
  FileFormat.unknown => 'Archivo',
};
