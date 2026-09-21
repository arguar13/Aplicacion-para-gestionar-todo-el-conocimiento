import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';

/// Mide cuánto de la bóveda se podría recuperar y si hay disco para hacerlo.
///
/// Solo lee: no compacta ni cambia nada. Es lo que la pantalla de la bóveda
/// muestra («se pueden recuperar N MB») y lo que decide si ofrecer compactar.
// ignore: one_member_abstracts
abstract interface class CompactionAdvisor {
  /// La medición de ahora. Barata —unos `PRAGMA` y una consulta al sistema—,
  /// así que se puede repetir cada vez que se abre la pantalla.
  Future<CompactionAssessment> assess();
}
