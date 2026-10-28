import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_dates_finder.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/organize_text.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_draft.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_input.dart';
import 'package:sinapsis/features/timeline/domain/repositories/dated_event_repository.dart';
import 'package:sinapsis/features/timeline/domain/services/dated_events_extractor.dart';
import 'package:sinapsis/features/timeline/domain/services/dated_passage_selector.dart';

/// Los hechos fechados de un elemento, puestos por la IA en la línea de tiempo
/// (F40, decisión B): directo, con su cita y su ✨, sin pasar por la Bandeja.
/// Deshacer la pasada los saca.
///
/// **El modelo nunca ve el texto entero.** Un buscador sin IA marca las
/// oraciones con una fecha escrita (`selectDatedParts`), y solo esas, con la
/// anterior de contexto, se reparten en pedidos del tamaño que lee el modelo
/// elegido en ese momento. Un texto sin fechas no manda nada: ni una llamada.
/// Cada pedido se guarda al terminar, así que los hechos aparecen en la línea a
/// medida que se leen.
///
/// **Retomable.** Si el modelo deja de contestar a mitad de un libro —sin
/// cuota, sin conexión—, la cola retoma el paso en la misma pasada. Lo que ya
/// leyó no se vuelve a pagar: el paso recuerda hasta dónde llegó en esa pasada
/// y sigue del siguiente pasaje. Es memoria de la sesión, como el resto de lo
/// que la cola retoma; perdida (la app se cerró), empieza de nuevo y la base no
/// repite lo que ya está (`addFromAi`).
///
/// El texto es el mismo que abre la lectura (`extractableRendition`: lo
/// extraído de un PDF o un libro, la transcripción, el OCR de una foto, la
/// página web), para que la posición de la cita caiga en el lugar. Una nota de
/// bloques no tiene ese texto: se lee el que se busca, y los hechos quedan con
/// su cita pero sin posición —sin «Abrir en el documento»—.
///
/// De un documento procesado (F41, paso 6) se lee solo lo que la persona
/// eligió al triar ([OrganizeTextReader]), y el hecho queda colgado del
/// procesado —la línea de tiempo se arma con eso—, pero su cita apunta a la
/// fuente, en su lugar, si sale de una parte copiada sin editar: «Abrir en el
/// documento» lleva al original justo ahí.
///
/// Es también el que busca **solo** las fechas que pide la persona
/// ([AiDatesFinder]): los mismos hechos, con la misma regla.
class AutoDatesStep implements AiOrganizeStep, AiDatesFinder {
  AutoDatesStep({
    required DatedEventsExtractor extractor,
    required DatedEventRepository events,
    OrganizeTextReader texts = const OwnTextReader(),
  }) : _extractor = extractor,
       _events = events,
       _texts = texts;

  final DatedEventsExtractor _extractor;
  final DatedEventRepository _events;
  final OrganizeTextReader _texts;

  /// Lo que se leyó de cada elemento, para no leerlo dos veces: la cola
  /// pregunta [mentionsDates] y enseguida pide [findDates] con el mismo
  /// elemento. Se va con él.
  final _plans = Expando<Future<_Plan>>();

  /// Hasta dónde se leyó cada pasada que se cortó esperando al modelo.
  final _resume = <String, _Reached>{};

  @override
  AiOrganizeToggle get toggle => AiOrganizeToggle.dates;

  @override
  Future<AiStepReport> organize(KnowledgeItem item, {required String runId}) =>
      findDates(item, runId: runId);

  @override
  Future<bool> mentionsDates(KnowledgeItem item) async =>
      (await _planOf(item)).parts.isNotEmpty;

  @override
  Future<AiStepReport> findDates(
    KnowledgeItem item, {
    required String runId,
  }) async {
    final plan = await _planOf(item);
    final parts = plan.parts;
    final reached = _reachedFor(runId, plan.textId, plan.length);
    final task = AiTaskHandle.current;
    var added = 0;
    try {
      for (final (index, part) in parts.indexed) {
        // Lo que falta de este pedido, o nada si ya se leyó entero.
        var rest = reached == null ? part : _after(part, reached.until);
        if (rest == null) continue;
        task?.parts(index, parts.length);
        while (rest != null) {
          final outcome = await _extractor.datedEventsOf(rest);
          added += await _save(item, runId, plan.text, outcome.events);
          // Al menos uno: el contrato lo garantiza, pero un pedido que no
          // avanza dejaría la cola girando sobre lo mismo.
          final analyzed = outcome.analyzed.clamp(1, rest.passages.length);
          _resume[runId] = (
            textId: plan.textId,
            length: plan.length,
            until: rest.passages[analyzed - 1].end,
          );
          rest = rest.after(analyzed);
        }
        task?.parts(index + 1, parts.length);
      }
      // Terminó: nada que retomar.
      _resume.remove(runId);
      return AiStepReport(applied: added);
    } on Object catch (e) {
      // Salvo que el modelo no pueda contestar por ahora: ahí la cola retoma
      // el paso en esta pasada y tiene que encontrar hasta dónde llegó.
      if (aiModelWaitFor(e) == null) _resume.remove(runId);
      rethrow;
    }
  }

  /// Los pedidos de [item]: su texto partido en lo que hay que preguntarle al
  /// modelo, del tamaño que lee el modelo elegido ahora.
  Future<_Plan> _planOf(KnowledgeItem item) =>
      _plans[item] ??= _planFor(item, _extractor.datedPartCharBudget);

  Future<_Plan> _planFor(KnowledgeItem item, int maxChars) async {
    final text = await _texts.textOf(item);
    final parts = text.text.trim().isEmpty
        ? const <DatedTextPart>[]
        : await _select(text.text, maxChars: maxChars, markdown: text.markdown);
    return _Plan(text: text, textId: text.ownRenditionId, parts: parts);
  }

  /// `selectDatedParts` sin trabar la interfaz: recorre todo el texto, y el de
  /// un libro grande son segundos. Uno corto se lee acá, que mandarlo a otro
  /// hilo costaría más que leerlo.
  static Future<List<DatedTextPart>> _select(
    String text, {
    required int maxChars,
    required bool markdown,
  }) {
    if (text.length < _inlineChars) {
      return Future.value(
        selectDatedParts(text, maxChars: maxChars, markdown: markdown),
      );
    }
    return compute(_selectIn, (
      text: text,
      maxChars: maxChars,
      markdown: markdown,
    ));
  }

  /// Hasta cuántos caracteres se lee sin otro hilo.
  static const _inlineChars = 40000;

  /// Hasta dónde llegó la pasada [runId] antes de cortarse, si es del mismo
  /// texto; `null` si empieza de cero. Si el texto cambió mientras esperaba
  /// —se volvió a extraer—, las posiciones ya no valen.
  _Reached? _reachedFor(String runId, String? textId, int length) {
    final reached = _resume[runId];
    if (reached == null) return null;
    if (reached.textId == textId && reached.length == length) {
      return reached;
    }
    _resume.remove(runId);
    return null;
  }

  /// Los pasajes de [part] que quedan después de [until], o `null` si ninguno.
  /// Cuenta los que terminan después, no los que empiezan: dos pasajes
  /// cortados de un mismo tramo largo pueden tocarse, y repetir uno es barato
  /// donde saltearlo perdería hechos.
  static DatedTextPart? _after(DatedTextPart part, int until) {
    final left = [
      for (final passage in part.passages)
        if (passage.end > until) passage,
    ];
    return left.isEmpty ? null : DatedTextPart(left);
  }

  /// Guarda los hechos [drafts] de la pasada y devuelve cuántos quedaron. La
  /// cita va donde [text] diga que se puede abrir ese mismo texto
  /// ([OrganizeText.cite]): en una forma del elemento, en la fuente de un
  /// procesado, o en ningún lado. El repositorio descarta lo repetido, lo que
  /// la persona ya quitó y lo que no es válido.
  Future<int> _save(
    KnowledgeItem item,
    String runId,
    OrganizeText text,
    List<DatedEventDraft> drafts,
  ) async {
    if (drafts.isEmpty) return 0;
    return (await _events.addFromAi(
      itemId: item.id,
      runId: runId,
      drafts: [
        for (final draft in drafts)
          if (text.cite(draft.start, draft.end) case final citation)
            DatedEventInput(
              title: draft.title,
              date: draft.date,
              end: draft.endDate,
              renditionId: citation?.renditionId,
              startOffset: citation?.start,
              endOffset: citation?.end,
              excerpt: draft.excerpt,
            ),
      ],
    )).orThrowStep('guardar los hechos fechados');
  }
}

/// Lo que se le va a preguntar al modelo de un elemento: sus pedidos, y de qué
/// texto son —el texto mismo, su forma y su largo—.
class _Plan {
  const _Plan({required this.text, required this.textId, required this.parts});

  /// Lo que se lee, con cómo citar lo que se encuentra en él.
  final OrganizeText text;

  /// La forma del elemento de la que sale el texto, para reconocerlo al
  /// retomar; `null` si no sale de una —una nota de bloques, un procesado—.
  final String? textId;
  final List<DatedTextPart> parts;

  int get length => text.text.length;
}

/// Lo que necesita [_selectIn] para armar los pedidos en otro hilo.
typedef _SelectArgs = ({String text, int maxChars, bool markdown});

List<DatedTextPart> _selectIn(_SelectArgs args) => selectDatedParts(
  args.text,
  maxChars: args.maxChars,
  markdown: args.markdown,
);

/// Hasta dónde se leyó una pasada: el texto —su forma y su largo— y el final
/// del último pasaje que contestó el modelo.
typedef _Reached = ({String? textId, int length, int until});
