import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_draft.dart';
import 'package:sinapsis/features/timeline/domain/services/dated_passage_selector.dart';

/// Quien lee los pasajes con fechas de un documento y cuenta los hechos que
/// hay en ellos (F40): el modelo elegido en Ajustes.
///
/// Interfaz propia, como `StudyMarker`: quien arma la línea de tiempo no tiene
/// por qué saber de motores, ventanas ni turnos.
abstract interface class DatedEventsExtractor {
  /// Cuántos caracteres de pasajes conviene darle por pedido: lo que entra en
  /// la ventana del modelo elegido, con lugar para lo que contesta. Es el
  /// tamaño con el que se arman los pedidos (`selectDatedParts`).
  int get datedPartCharBudget;

  /// Los hechos fechados que hay en [part].
  ///
  /// Si el pedido entero no entra en la ventana —el texto cuenta más tokens
  /// de lo común—, lee solo los primeros pasajes: [DatedEventsOutcome.analyzed]
  /// dice cuántos, al menos uno, y `DatedTextPart.after` arma lo que falta.
  ///
  /// Lanza si el modelo no está listo o falla —sin conexión, sin cuota—:
  /// quien llama ya comprobó que estaba listo, y lo leído hasta ahí queda.
  Future<DatedEventsOutcome> datedEventsOf(DatedTextPart part);
}

/// Lo que dio un pedido: cuántos de sus pasajes se leyeron, desde el primero,
/// y los hechos que se encontraron en ellos, ya con su cita ubicada en el
/// texto entero y verificada contra lo que el texto dice.
@immutable
class DatedEventsOutcome {
  const DatedEventsOutcome({required this.analyzed, required this.events});

  final int analyzed;
  final List<DatedEventDraft> events;
}
