import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter.dart';

/// Elige qué exportador se ocupa de cada formato.
///
/// A diferencia del registro de transformadores, acá siempre hay exactamente
/// uno: [ExportFormat] es una lista cerrada de formatos que la propia app
/// ofrece, así que pedir uno que nadie sepa producir es un error de
/// programación, no una situación normal — por eso [resolve] lanza en vez de
/// devolver `null`.
class ExporterRegistry {
  const ExporterRegistry(this._exporters);

  final List<Exporter> _exporters;

  Exporter resolve(ExportFormat format) {
    for (final exporter in _exporters) {
      if (exporter.format == format) return exporter;
    }

    throw StateError('No hay un exportador registrado para $format.');
  }
}
