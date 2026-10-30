import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';

/// Lo que se crea desde «Crear» (F45, paso 7b, mejora 14, decisión G): un
/// solo lugar, en vez de cuatro —el ✨ de la nota derivada y el ícono del
/// cuestionario arriba, «Organizar con IA» y «Buscar fechas con IA» en ⋮, y
/// la ruedita y el «+» de «Tarjetas de repaso» abajo—.
///
/// En el orden de la hoja: primero lo que hace la IA, después lo que se hace
/// a mano.
enum CreateKind {
  /// Que la IA organice el documento: temas, vínculos y tarjetas.
  organize,

  /// Que la IA proponga tarjetas de repaso de su texto, para elegir cuáles
  /// guardar.
  flashcards,

  /// Que la IA arme un cuestionario de opción múltiple.
  quiz,

  /// Que la IA escriba una nota derivada —guía de estudio, preguntas
  /// abiertas, esquema o cronología—, con cada afirmación anclada.
  derivedNote,

  /// Que la IA busque las fechas del texto para la línea de tiempo.
  dates,

  /// Una tarjeta a mano, en la forma que se elija.
  card,

  /// Una nota escrita a mano, en las notas del documento.
  note,

  /// Un vínculo a mano con otro documento.
  link;

  /// Si lo hace la IA —el grupo «Con IA»— o la persona —«A mano»—.
  bool get withAi => switch (this) {
    organize || flashcards || quiz || derivedNote || dates => true,
    card || note || link => false,
  };

  /// Si lo hace la cola de la IA de fondo, que sigue aunque se cierre la
  /// pantalla, y no esta pantalla: organizar y buscar fechas.
  bool get queued => this == organize || this == dates;
}

/// Por qué algo de «Crear» no se puede hacer ahora: la fila se ve apagada y
/// lo dice, en vez de desaparecer.
enum CreateBlock {
  /// Sin texto del que sacar nada.
  noText,

  /// El elemento todavía se está procesando: lo que se cree saldría de un
  /// texto que va a cambiar.
  notReady,

  /// La fuente del documento procesado está en la papelera: primero se
  /// restaura.
  sourceInTrash,

  /// El documento procesado perdió su fuente.
  sourceGone,
}

/// Sobre qué se crea desde «Crear»: un documento procesado o una nota propia
/// de la Biblioteca. Una fuente no: queda de consulta, y lo que se crea sale
/// de su documento procesado (F41, decisión K).
@immutable
class CreateTarget {
  /// Un documento procesado ([document]), con su elemento ([item]): lo que
  /// se crea sale de su texto procesado.
  CreateTarget.processed({
    required ProcessedDocument document,
    required this.item,
  }) : processed = true,
       _blocks = {
         // Sin texto no hay fechas que buscar.
         if (document.summary.isEmpty) CreateKind.dates: CreateBlock.noText,
         // Una nota va a la sección Notas, que se arma contra la fuente
         // viva (`ProcessSourceUseCase`).
         CreateKind.note: ?switch (document.source) {
           null => CreateBlock.sourceGone,
           ProcessedSourceLink(inTrash: true) => CreateBlock.sourceInTrash,
           _ => null,
         },
       },
       sourceItemId = switch (document.source) {
         ProcessedSourceLink(:final itemId, inTrash: false) => itemId,
         _ => null,
       };

  /// Una nota propia de la Biblioteca. Lo que se escribe a mano va en la
  /// nota misma, así que «Nota» no se ofrece.
  CreateTarget.note(this.item)
    : processed = false,
      sourceItemId = null,
      _blocks = {
        // Organizar a medio procesar sería vincular y hacer tarjetas de un
        // texto que va a cambiar, como en la cola de la IA.
        if (item.processingState != ProcessingState.ready) ...{
          CreateKind.organize: CreateBlock.notReady,
          CreateKind.dates: CreateBlock.notReady,
        } else if (!_hasWrittenText(item))
          CreateKind.dates: CreateBlock.noText,
      };

  final KnowledgeItem item;

  /// Si [item] es un documento procesado.
  final bool processed;

  /// La fuente viva del documento procesado, donde se arma su nota a mano;
  /// `null` si no tiene o está en la papelera.
  final String? sourceItemId;

  final Map<CreateKind, CreateBlock> _blocks;

  /// Lo que la hoja ofrece, en su orden.
  List<CreateKind> get offered => [
    for (final kind in CreateKind.values)
      if (kind != CreateKind.note || processed) kind,
  ];

  /// Por qué [kind] no se puede ahora, o `null` si se puede.
  CreateBlock? blockOf(CreateKind kind) => _blocks[kind];

  @override
  bool operator ==(Object other) =>
      other is CreateTarget &&
      other.item == item &&
      other.processed == processed &&
      other.sourceItemId == sourceItemId &&
      mapEquals(other._blocks, _blocks);

  @override
  int get hashCode => Object.hash(
    item,
    processed,
    sourceItemId,
    Object.hashAllUnordered(_blocks.entries.map((e) => (e.key, e.value))),
  );
}

/// Si alguna forma del elemento tiene algo escrito: lo que pide buscar fechas.
/// Mira hasta la primera letra, no el texto entero.
bool _hasWrittenText(KnowledgeItem item) =>
    item.renditions.any((r) => r.searchableText?.contains(_notBlank) ?? false);

final _notBlank = RegExp(r'\S');
