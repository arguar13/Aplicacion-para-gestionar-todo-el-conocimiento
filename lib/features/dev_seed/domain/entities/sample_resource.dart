import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/storage/file_format.dart';

/// Un recurso de la biblioteca de ejemplo: algo real y público que se carga
/// por el mismo camino que si el usuario lo hubiera guardado a mano.
///
/// Sellado y no una sola clase con campos opcionales, por la misma razón que
/// `CaptureRequest`: un enlace, un archivo y una nota se cargan de formas que
/// no se parecen —uno se captura por su dirección, otro se baja primero y el
/// tercero se escribe—, y con campos opcionales serían construibles un
/// enlace sin dirección o una nota con archivo.
sealed class SampleResource {
  const SampleResource({
    required this.id,
    required this.title,
    required this.why,
  });

  /// Identificador estable, propio de la lista: es lo que se recuerda para
  /// no cargar dos veces lo mismo. No cambia aunque cambie el título o la
  /// dirección, así que nunca se reusa uno para otra cosa.
  final String id;

  /// Cómo se presenta en la lista y en el informe. En un archivo y en una
  /// nota es también el título con que se guarda; en un enlace, el que trae
  /// la página o el video al procesarse gana sobre este.
  final String title;

  /// Qué parte de la app prueba: por qué está en la lista.
  final String why;

  /// Cuánto se baja de internet por él, aproximado: lo que pesa el archivo,
  /// la página o el audio del video. Es lo que suma la confirmación.
  int get approxBytes;
}

/// Qué clase de enlace es: decide qué adaptador lo reconoce al capturarlo.
enum SampleLinkKind {
  /// Una página web: se archiva y se lee en modo lectura.
  webArticle,

  /// Un video de YouTube: transcripción y, después, la bajada del audio.
  youtubeVideo,
}

/// Algo que se captura por su dirección, como cuando se pega un enlace.
final class SampleLink extends SampleResource {
  const SampleLink({
    required super.id,
    required super.title,
    required super.why,
    required this.kind,
    required this.url,
    required this.approxBytes,
    this.channel,
    this.minutes,
  });

  final SampleLinkKind kind;
  final String url;

  /// El canal de un video, tal como lo informa YouTube.
  final String? channel;

  /// Cuánto dura un video, en minutos.
  final int? minutes;

  @override
  final int approxBytes;
}

/// Qué clase de archivo se espera: lo que se comprueba en los bytes al
/// bajarlo, antes de guardar nada.
enum SampleFileKind {
  pdf({FileFormat.pdf}),
  epub({FileFormat.epub}),
  text({FileFormat.plainText, FileFormat.markdown}),
  audio({FileFormat.mp3, FileFormat.ogg, FileFormat.wav, FileFormat.flac}),
  image({FileFormat.jpeg, FileFormat.png, FileFormat.gif, FileFormat.webp});

  const SampleFileKind(this.formats);

  /// Los formatos que cuentan como este tipo. Un servidor que devuelve una
  /// página de error con un 200 entrega HTML donde se esperaba un PDF:
  /// guardarlo como si fuera el PDF dejaría en la biblioteca un documento
  /// que no se puede leer.
  final Set<FileFormat> formats;
}

/// Algo que se baja primero y se guarda como archivo, como si el usuario lo
/// hubiera elegido con el selector del sistema.
final class SampleFile extends SampleResource {
  const SampleFile({
    required super.id,
    required super.title,
    required super.why,
    required this.kind,
    required this.url,
    required this.fileName,
    required this.approxBytes,
  });

  final SampleFileKind kind;
  final String url;

  /// El nombre con que llega, extensión incluida: es lo que distingue un
  /// texto plano de un Markdown, que no tienen firma en los bytes.
  final String fileName;

  @override
  final int approxBytes;
}

/// Una nota escrita para el ejemplo, de bloques y con `[[enlaces]]` entre
/// ellas y hacia lo que se carga.
final class SampleNote extends SampleResource {
  const SampleNote({
    required super.id,
    required super.title,
    required super.why,
    required this.blocks,
  });

  final List<ContentBlock> blocks;

  /// Se escribe en el teléfono: no baja nada.
  @override
  int get approxBytes => 0;
}
