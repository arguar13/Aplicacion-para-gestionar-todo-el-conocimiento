import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// Si [item] es una fuente de la Biblioteca, que queda de consulta (F41,
/// decisión K): se estudia en su documento procesado, no en ella.
///
/// Una fuente es todo lo que entró de afuera —un documento, un libro, una
/// página, una publicación, una imagen, un audio, un video, una referencia—.
/// Su detalle deja de ofrecer lo que es estudiarla y trabajar con la IA sobre
/// ella:
///
/// - el resumen, la síntesis y las palabras clave para leer, y el mosaico
///   «Resumir»;
/// - el Mapa y las Tarjetas de repaso;
/// - «Organizar con IA», «Buscar fechas con IA» y lo que la IA organizó;
/// - la nota derivada y el quiz;
/// - «Borrar archivo, quedarme con el texto»: de la Biblioteca nada se borra.
///
/// Eso vive en su documento procesado. Una nota propia no es una fuente:
/// conserva todo, porque no tiene documento procesado. Un documento procesado
/// tampoco llega acá: tiene su propia pantalla.
bool isConsultationSource(KnowledgeItem item) =>
    item.source.kind != SourceKind.manualNote;
