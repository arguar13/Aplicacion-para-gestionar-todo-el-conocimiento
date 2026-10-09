import 'package:meta/meta.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';

/// Desde cuántos días de intervalo una tarjeta se considera madura: el
/// criterio de Anki (`is:mature` es `ivl >= 21`). Por debajo, joven.
const kMatureIntervalDays = 21;

/// En qué estado está una tarjeta, para filtrar «Mis tarjetas» (F31, ola 2,
/// decisión 72).
///
/// Los estados de etapa ([newCards], [learning], [young], [mature]) y
/// [suspended] son una PARTICIÓN de la bóveda: una tarjeta cae en uno solo, y
/// la pausa gana (una nueva pausada está en «pausadas», no en «nuevas»). Es la
/// misma partición del reparto de las estadísticas, así que los números de un
/// lado y del otro suman lo mismo. [due] y [buried] son transversales: se
/// cruzan con las etapas.
enum CardBrowserStatus {
  /// Nunca se contestó, y no está pausada.
  newCards,

  /// Se aprende o se reaprende (vuelve en minutos), y no está pausada.
  learning,

  /// Se repasa en días, con menos de [kMatureIntervalDays] de intervalo.
  young,

  /// Se repasa en días, con [kMatureIntervalDays] o más.
  mature,

  /// Pausada: no entra en ninguna sesión.
  suspended,

  /// Ya toca repasarla —no nueva, no pausada, y le toca antes de que termine
  /// el día de estudio de hoy—. Incluye lo atrasado y lo que se aprende.
  due,

  /// Pospuesta hasta mañana.
  buried,
}

/// Por qué columna se ordena la lista.
enum CardBrowserSort {
  /// Cuándo toca repasarla.
  due,

  /// Cuándo se creó.
  created,

  /// El factor de facilidad: de las que más cuestan a las más fáciles.
  ease,

  /// El intervalo, en días.
  interval,

  /// Cuántas veces se olvidó (un «De nuevo» sobre un repaso).
  lapses,
}

/// Qué pedirle a «Mis tarjetas» (F31, ola 2, decisión 72): un recorte, un
/// estado, un texto y un orden. Es un valor: dos pedidos iguales son iguales.
@immutable
class CardBrowserQuery {
  const CardBrowserQuery({
    this.scope = const StudyScope.all(),
    this.status,
    this.text = '',
    this.sort = CardBrowserSort.due,
    this.descending = false,
  });

  /// Qué entra: todo, o un tema, una etiqueta, un cuaderno o un elemento.
  /// Es el MISMO `StudyScope` de la cola de estudio: una sola respuesta a
  /// «qué entra en Roma».
  final StudyScope scope;

  /// El estado a mostrar; `null` = todas.
  final CardBrowserStatus? status;

  /// Lo que se busca en el frente y en el dorso. Cada palabra tiene que estar
  /// (en cualquier orden); no distingue mayúsculas ni acentos.
  final String text;

  final CardBrowserSort sort;

  /// Al revés del orden natural de [sort].
  final bool descending;

  /// El pedido con algunos campos cambiados. [status] admite `null` para
  /// quitar el filtro, por eso se pasa envuelto (`() => null`).
  CardBrowserQuery copyWith({
    StudyScope? scope,
    CardBrowserStatus? Function()? status,
    String? text,
    CardBrowserSort? sort,
    bool? descending,
  }) => CardBrowserQuery(
    scope: scope ?? this.scope,
    status: status != null ? status() : this.status,
    text: text ?? this.text,
    sort: sort ?? this.sort,
    descending: descending ?? this.descending,
  );

  @override
  bool operator ==(Object other) =>
      other is CardBrowserQuery &&
      other.scope == scope &&
      other.status == status &&
      other.text == text &&
      other.sort == sort &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(scope, status, text, sort, descending);

  @override
  String toString() =>
      'CardBrowserQuery($scope, $status, "$text", $sort'
      '${descending ? ' desc' : ''})';
}
