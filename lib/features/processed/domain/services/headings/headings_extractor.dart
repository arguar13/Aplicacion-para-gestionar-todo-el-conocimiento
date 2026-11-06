import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/services/headings/processed_headings.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';

/// El puerto por donde se guardan los títulos de un documento procesado en
/// el Índice (F46, paso 2): recibe lo que Procesado tiene del documento —sus
/// páginas de «Texto», su clase de texto y, si es un PDF, lo que se leyó del
/// archivo antes de la transacción— y devuelve sus títulos, listos para
/// guardar, en el orden en que se leen.
///
/// En la app es [ReadingHeadingsExtractor]: el lector del paso 1,
/// `readProcessedHeadings`, en otro hilo si el texto es largo. Las pruebas
/// del Índice le ponen un doble que responde lo que necesitan —o falla—, sin
/// depender de cómo se leen los títulos, que prueba el paso 1.
///
/// **El contrato** (el de `readProcessedHeadings`):
///
/// - no lee ni escribe la base, ni ningún archivo: se lo llama adentro de la
///   transacción que guarda el texto, y lo que lleva tiempo —el PDF— ya se
///   leyó antes;
/// - devuelve los títulos con su orden, su nivel corrido, su tramo y su página
///   del texto, y la página del PDF si la sabe; sin títulos, una sola entrada
///   «Texto completo»; sin texto, ninguna;
/// - si falla, lanza: el texto se guarda igual y el documento queda «sin
///   indexar» hasta que el relleno lo reintenta. Nunca devuelve algo a medias.
///
/// Lo que devuelve pasa por `settleHeadings` antes de guardarse: lo que no
/// cumpla lo de arriba se corrige o se deja afuera, y la base nunca recibe
/// algo inválido.
// ignore: one_member_abstracts
abstract interface class HeadingsExtractor {
  Future<List<ProcessedHeading>> headingsOf(ProcessedHeadingsSource source);
}

/// [HeadingsExtractor] con el lector del paso 1 (`readProcessedHeadings`):
/// en este hilo si el texto es corto, y en otro si es un libro
/// ([runProcessedWork], el mismo umbral con que se pagina y se estudia).
class ReadingHeadingsExtractor implements HeadingsExtractor {
  const ReadingHeadingsExtractor({ProcessedWorker worker = runProcessedWork})
    : _worker = worker;

  final ProcessedWorker _worker;

  @override
  Future<List<ProcessedHeading>> headingsOf(ProcessedHeadingsSource source) =>
      _worker(
        readProcessedHeadings,
        source,
        size: source.pages.fold(0, (sum, page) => sum + page.length),
      );
}
