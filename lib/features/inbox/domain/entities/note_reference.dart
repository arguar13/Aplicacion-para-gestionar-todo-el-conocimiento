import 'package:freezed_annotation/freezed_annotation.dart';

part 'note_reference.freezed.dart';

/// Una nota viva, tal como se lista para elegirla al "vincular a nota
/// viva" desde la Bandeja de entrada — una proyección mínima, no el
/// `KnowledgeItem` completo: acá no hace falta su fuente, sus formas ni
/// sus etiquetas, solo lo que hace falta para reconocerla en una lista.
@freezed
sealed class NoteReference with _$NoteReference {
  const factory NoteReference({
    required String id,
    required String title,
    String? subtitle,
  }) = _NoteReference;
}
