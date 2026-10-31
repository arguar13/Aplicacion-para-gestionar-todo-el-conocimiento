import 'package:flutter/foundation.dart';

/// Los widgets de la pantalla de inicio de Android (F47, paso 7, decisión G).
enum HomeWidgetKind {
  /// «Para hoy · N tarjetas»: las tarjetas que tocan hoy en Repasar. Lleva a
  /// Repasar.
  dueToday('app.sinapsis.DueTodayWidget'),

  /// «Guardar rápido»: abre Guardar, listo para pegar o escribir.
  quickCapture('app.sinapsis.QuickCaptureWidget'),

  /// «Seguir escuchando»: lo último que se escuchó, con su título. Lleva al
  /// documento.
  continueListening('app.sinapsis.ContinueListeningWidget');

  const HomeWidgetKind(this.androidProvider);

  /// La clase de Kotlin que lo dibuja (`AppWidgetProvider`). El paquete de
  /// las clases es siempre `app.sinapsis`, también en los sabores con otro
  /// `applicationId`.
  final String androidProvider;

  /// El widget que dice [wireName] —su [name], lo que manda el lado de
  /// Android al tocar uno—, o `null` si no es ninguno.
  static HomeWidgetKind? fromWire(String? wireName) {
    for (final kind in values) {
      if (kind.name == wireName) return kind;
    }
    return null;
  }
}

/// Lo que muestra «Para hoy»: cuántas tarjetas tocan, y hasta cuándo vale la
/// cifra.
///
/// El widget se dibuja con la app cerrada, sin poder contar: pasado
/// [validUntil] —el comienzo del día de estudio siguiente— la cifra ya no es
/// la de hoy, y en vez de mentir dice «Tocá para ver lo de hoy».
@immutable
class DueToday {
  const DueToday({required this.count, required this.validUntil});

  final int count;
  final DateTime validUntil;

  @override
  bool operator ==(Object other) =>
      other is DueToday &&
      other.count == count &&
      other.validUntil == validUntil;

  @override
  int get hashCode => Object.hash(count, validUntil);

  @override
  String toString() => 'DueToday($count hasta $validUntil)';
}

/// Lo último que se escuchó: su título y dónde se abre.
@immutable
class ContinueListening {
  const ContinueListening({required this.title, required this.location});

  final String title;

  /// La dirección de la app (`/processed/…`, `/library/…`) de la pantalla
  /// desde donde se escuchó.
  final String location;

  @override
  bool operator ==(Object other) =>
      other is ContinueListening &&
      other.title == title &&
      other.location == location;

  @override
  int get hashCode => Object.hash(title, location);

  @override
  String toString() => 'ContinueListening("$title" en $location)';
}

/// Los widgets de la pantalla de inicio, del lado de la plataforma (F47,
/// paso 7): lo que muestran, agregarlos desde la app y los toques que abren
/// la app.
///
/// No sabe cuántas tarjetas hay ni qué se escuchó: eso lo cuenta quien lo
/// usa —`HomeWidgetsBinding`—. Acá solo hay lo que el sistema hace.
///
/// En Android es `AndroidHomeScreenWidgets` (con `home_widget`, decisión G);
/// en la web y en el escritorio, `NullHomeScreenWidgets`, que no hace nada y
/// dice que no hay widgets.
abstract interface class HomeScreenWidgets {
  /// Si esta plataforma tiene widgets. Si es `false`, Ajustes no los ofrece.
  bool get isSupported;

  /// Lo que muestra «Para hoy». El sistema lo vuelve a dibujar enseguida.
  Future<void> showDueToday(DueToday dueToday);

  /// Lo que muestra «Seguir escuchando»; `null`, que no se escuchó nada.
  ///
  /// Solo el título sale de la app: dónde se abre lo guarda la app, y un toque
  /// del widget solo dice «Seguir escuchando».
  Future<void> showContinueListening(ContinueListening? listening);

  /// Si el teléfono deja poner un widget desde la app (Android 8 en adelante,
  /// y si la pantalla de inicio lo permite).
  Future<bool> canAddFromApp();

  /// Le pide al teléfono poner [kind] en la pantalla de inicio: el sistema
  /// pregunta dónde, y la persona puede decir que no.
  Future<void> add(HomeWidgetKind kind);

  /// Cada toque a un widget con la app andando.
  Stream<HomeWidgetKind> get openRequests;

  /// Si la app se abrió tocando un widget y todavía no se atendió (el
  /// arranque en frío: nadie escuchaba [openRequests]). Devuelve el widget
  /// una sola vez por toque.
  Future<HomeWidgetKind?> takePendingOpen();
}
