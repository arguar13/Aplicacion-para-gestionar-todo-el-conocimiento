import 'package:sinapsis/features/capture/domain/adapters/source_adapter.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';

/// Elige qué adaptador se ocupa de cada captura.
///
/// Pregunta en orden y se queda con el primero que acepta, así que el orden
/// de la lista es significativo: los adaptadores específicos van antes que
/// los generales — YouTube antes que "cualquier enlace", y el de texto suelto
/// al final.
///
/// El último de la lista tiene que aceptar cualquier cosa. Es lo que
/// convierte "no reconocí esto" en "lo guardo como nota" en vez de en un
/// error: alguien que pega algo raro prefiere tenerlo guardado tal cual antes
/// que perderlo.
class SourceAdapterRegistry {
  const SourceAdapterRegistry(this._adapters);

  final List<SourceAdapter> _adapters;

  SourceAdapter resolve(CaptureRequest request) {
    return _adapters.firstWhere(
      (adapter) => adapter.canHandle(request),
      orElse: () => throw StateError(
        'Ningún adaptador aceptó la captura. El último de la lista tiene que '
        'aceptar cualquier entrada; revisar cómo se construyó el registro.',
      ),
    );
  }
}
