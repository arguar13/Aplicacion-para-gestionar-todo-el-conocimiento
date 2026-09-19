import 'package:sinapsis/features/notes/domain/entities/cited_source.dart';

/// De dónde sale lo que dice una nota viva.
// ignore: one_member_abstracts
abstract interface class NoteSourcesRepository {
  /// Las fuentes que la nota [noteId] cita, ordenadas por título,
  /// actualizándose solas.
  ///
  /// Cuentan dos caminos. Directo: la nota tiene un vínculo `cites` hacia la
  /// fuente. A través de las atómicas: la nota enlaza una nota atómica —con
  /// cualquier vínculo que no sea una contradicción— y esa atómica se extrajo
  /// de la fuente. Una fuente que se cita de los dos modos aparece una vez, con
  /// los dos datos.
  ///
  /// Solo se siguen los vínculos que salen de la nota: es la nota la que dice
  /// qué usa. Una contradicción no cita —"esto no es cierto"— y no cuenta.
  Stream<List<CitedSource>> watchCitedSources(String noteId);
}
