import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';

part 'slide_deck.freezed.dart';

/// Los dos formatos de la hoja de la Presentación (F43, punto 4).
enum DeckFormat {
  /// Las diapositivas se leen solas: más texto en cada una.
  detailed('detailed'),

  /// Las diapositivas acompañan a quien habla: poco texto, y lo que hay que
  /// decir en las notas.
  presenter('presenter');

  const DeckFormat(this.jsonName);

  final String jsonName;
}

/// Un mazo de diapositivas: el contenido que escribe la IA (decisión G). Se
/// guarda como JSON en «Lo creado» —ver `SlideDeckJson`—, y el diseño va
/// aparte, en `DeckDesign`.
@freezed
abstract class SlideDeck with _$SlideDeck {
  const factory SlideDeck({
    required String title,
    @Default('') String subtitle,
    @Default(DeckFormat.detailed) DeckFormat format,
    @Default(<Slide>[]) List<Slide> slides,
  }) = _SlideDeck;
}
