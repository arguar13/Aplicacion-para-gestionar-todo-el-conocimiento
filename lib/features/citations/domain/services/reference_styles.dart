import 'package:sinapsis/features/citations/domain/services/reference_style.dart';
import 'package:sinapsis/features/citations/domain/services/styles/apa7_style.dart';
import 'package:sinapsis/features/citations/domain/services/styles/ieee_style.dart';
import 'package:sinapsis/features/citations/domain/services/styles/mla9_style.dart';

/// Los estilos de cita que la app ofrece, en el orden en que se ofrecen (F15).
///
/// Agregar un estilo es escribir su clase y sumarla a esta lista: ningún otro
/// lugar de la app los nombra.
const kReferenceStyles = ReferenceStyleRegistry([
  Apa7Style(),
  Mla9Style(),
  IeeeStyle(),
]);
