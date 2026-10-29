import 'package:meta/meta.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/deck_illustration_style.dart';

/// Las claves propias de la Presentación en las opciones de una creación
/// (F43, paso 11), además de las de fábrica (`CreationOptionValues`).
abstract final class PresentationOptionKeys {
  /// El estilo de las ilustraciones: `DeckIllustrationStyle.id`.
  static const illustrationStyle = 'illustrationStyle';

  /// El diseño elegido en el visor (`DeckDesign.toJson`): se guarda en las
  /// opciones, aparte del contenido que escribió la IA (decisión G).
  static const design = 'deckDesign';
}

/// Lo que se eligió en la hoja de la Presentación, ya leído con tolerancia:
/// lo que falta o no se entiende toma el valor de fábrica.
@immutable
class PresentationOptions {
  const PresentationOptions({
    this.format = DeckFormat.detailed,
    this.short = false,
    this.template,
    this.illustrations = false,
    this.illustrationStyle = DeckIllustrationStyle.template,
    this.description = '',
    this.imageAccountId,
  });

  factory PresentationOptions.of(Map<String, Object?> options) {
    final description = options[CreationOptionKeys.description];
    final account = options[CreationOptionKeys.imageAccountId];
    return PresentationOptions(
      format:
          options[CreationOptionValues.format] == CreationOptionValues.presenter
          ? DeckFormat.presenter
          : DeckFormat.detailed,
      short: options[CreationOptionValues.length] == CreationOptionValues.short,
      template: templateOf(options[CreationOptionValues.template]),
      illustrations: options[CreationOptionValues.illustrations] == true,
      illustrationStyle:
          DeckIllustrationStyle.fromId(
            options[PresentationOptionKeys.illustrationStyle],
          ) ??
          DeckIllustrationStyle.template,
      description: description is String ? description.trim() : '',
      imageAccountId: account is String && account.isNotEmpty ? account : null,
    );
  }

  final DeckFormat format;

  /// «Corta» en vez de «Estándar».
  final bool short;

  /// La plantilla elegida; `null` es «Automática»: la elige la IA según el
  /// tema (`PresentationContent.templateHint`).
  final DeckTemplateId? template;

  /// «Ilustraciones con IA».
  final bool illustrations;
  final DeckIllustrationStyle illustrationStyle;

  /// Lo que se escribió en «Describí lo que querés crear».
  final String description;

  /// La cuenta que dibuja, si en «Con tu IA actual» se eligió otra.
  final String? imageAccountId;

  /// Cuántas diapositivas se le piden a la IA: una corta son unas ocho; una
  /// estándar, unas catorce.
  int get slideTarget => short ? shortSlides : standardSlides;

  static const shortSlides = 8;
  static const standardSlides = 14;

  /// Cuántas ilustraciones se dibujan como mucho: más o menos la mitad de
  /// las diapositivas. Es la cifra que muestra «Con tu IA actual», y el
  /// generador no la pasa: lo que se avisó es lo que se gasta.
  int get maxIllustrations => short ? 4 : 7;

  /// Cuánto se estima que escribe la IA: unas 220 palabras de JSON por
  /// diapositiva, y casi otro tanto de notas en «Del presentador».
  int get expectedOutputTokens =>
      slideTarget * (format == DeckFormat.presenter ? 330 : 225);

  /// El diseño con que se abre la primera vez: la plantilla elegida o, en
  /// «Automática», la que eligió la IA ([hint]); si tampoco, Editorial.
  DeckDesign initialDesign({DeckTemplateId? hint}) =>
      DeckDesign(template: template ?? hint ?? DeckTemplateId.editorial);

  /// La plantilla guardada en [raw]: su `id` (lo que se guarda) o, por lo
  /// que guardaba la hoja de fábrica, el nombre del valor; «auto» o algo que
  /// no se entiende, `null`.
  static DeckTemplateId? templateOf(Object? raw) {
    final byId = DeckTemplateId.fromId(raw);
    if (byId != null) return byId;
    for (final id in DeckTemplateId.values) {
      if (id.name == raw) return id;
    }
    return null;
  }
}

/// El diseño guardado de una presentación: el que se eligió en el visor o,
/// si nunca se tocó, el que sale de las opciones de la hoja y de lo que
/// sugirió la IA.
DeckDesign presentationDesignOf(
  Map<String, Object?> options, {
  DeckTemplateId? hint,
}) {
  final saved = options[PresentationOptionKeys.design];
  if (saved is Map) return DeckDesign.parse(saved);
  return PresentationOptions.of(options).initialDesign(hint: hint);
}
