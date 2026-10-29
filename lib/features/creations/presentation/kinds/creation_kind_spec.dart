import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un texto de la interfaz que se dice en el idioma de la app.
typedef CreationText = String Function(AppLocalizations l10n);

/// Las piezas comunes de la hoja de personalizar (F43, punto 3 del plan) que
/// un tipo pide. Las dibuja la hoja, igual para todos; el tipo solo dice
/// cuáles lleva.
enum CreationField {
  /// «Seleccionar idioma», en español por defecto.
  language,

  /// «Fuentes: N fuentes ▾», para destildar documentos del recorte. La llevan
  /// todos: sin fuentes no hay nada que crear.
  sources,

  /// «Describí lo que querés crear», con un ejemplo de guía tenue.
  description,

  /// El tema, con las fichas de los temas sugeridos («+ Moisés y Faraón»),
  /// sacados de las palabras clave del recorte.
  topic,
}

/// Lo que guardan las piezas comunes en las opciones de una creación: las
/// claves que leen los generadores de la ola 3.
abstract final class CreationOptionKeys {
  /// El texto de «Describí lo que querés crear» (`String`).
  static const description = 'description';

  /// El tema elegido o escrito (`String`).
  static const topic = 'topic';

  /// La cuenta que dibuja las ilustraciones, si en el aviso «Con tu IA
  /// actual» se eligió otra (`String`, el id de `IllustrationAccount`).
  static const imageAccountId = 'imageAccountId';
}

/// Una opción propia de un tipo, dicha como dato: la hoja la dibuja con las
/// piezas de las capturas (los segmentados con ✓, los interruptores, las
/// fichas) y la guarda en las opciones con su [key].
@immutable
sealed class CreationOptionSpec {
  const CreationOptionSpec({
    required this.key,
    required this.label,
    this.visibleWhen,
  });

  /// La clave en `StudyCreation.options`: lo que lee el generador del tipo.
  final String key;

  /// Su título en la hoja.
  final CreationText label;

  /// Si se muestra con las opciones de ahora: una que depende de otra —el
  /// texto de «Una propia» solo con esa plantilla elegida—. Sin esto, siempre.
  final bool Function(Map<String, Object?> options)? visibleWhen;

  /// Su valor de fábrica.
  Object? get defaultValue;

  bool isVisible(Map<String, Object?> options) =>
      visibleWhen?.call(options) ?? true;
}

/// Un valor posible de una opción con valores.
@immutable
class CreationChoice {
  const CreationChoice(this.value, this.label);

  /// Lo que se guarda: estable, nunca el texto traducido.
  final String value;
  final CreationText label;
}

/// Una de varias: los segmentados con ✓ («Menos · ✓ Estándar · Más»), o un
/// desplegable si son muchas ([asMenu]: las dieciséis plantillas).
final class CreationChoiceOption extends CreationOptionSpec {
  const CreationChoiceOption({
    required super.key,
    required super.label,
    required this.choices,
    required this.initial,
    this.asMenu = false,
    super.visibleWhen,
  });

  final List<CreationChoice> choices;
  final String initial;
  final bool asMenu;

  @override
  String get defaultValue => initial;

  /// El valor de [options] si es uno de [choices]; si no —uno de una versión
  /// vieja, uno tocado a mano—, el de fábrica.
  String valueIn(Map<String, Object?> options) {
    final value = options[key];
    return choices.any((c) => c.value == value) ? value! as String : initial;
  }
}

/// Algunas de varias, al menos una: los tipos de pregunta del cuestionario.
final class CreationMultiChoiceOption extends CreationOptionSpec {
  const CreationMultiChoiceOption({
    required super.key,
    required super.label,
    required this.choices,
    required this.initial,
    super.visibleWhen,
  });

  final List<CreationChoice> choices;
  final List<String> initial;

  @override
  List<String> get defaultValue => initial;

  /// Los valores de [options] que son de [choices], en el orden de
  /// [choices]; ninguno válido, los de fábrica.
  List<String> valuesIn(Map<String, Object?> options) {
    final raw = options[key];
    final chosen = raw is List ? raw.whereType<String>().toSet() : <String>{};
    final valid = [
      for (final c in choices)
        if (chosen.contains(c.value)) c.value,
    ];
    return valid.isEmpty ? initial : valid;
  }
}

/// Sí o no: «Incluir imágenes», «Ilustraciones con IA».
final class CreationToggleOption extends CreationOptionSpec {
  const CreationToggleOption({
    required super.key,
    required super.label,
    this.hint,
    this.initial = false,
    this.illustrations = false,
    super.visibleWhen,
  });

  final CreationText? hint;
  final bool initial;

  /// Si es el de «Ilustraciones con IA» (decisión H): prendido, la hoja
  /// muestra la tarjeta «Con tu IA actual» con las imágenes que pide, y
  /// «Seguir sin ilustraciones» lo apaga.
  final bool illustrations;

  @override
  bool get defaultValue => initial;

  bool valueIn(Map<String, Object?> options) {
    final value = options[key];
    return value is bool ? value : initial;
  }
}

/// Un texto libre: la plantilla propia de un informe.
final class CreationTextOption extends CreationOptionSpec {
  const CreationTextOption({
    required super.key,
    required super.label,
    this.hint,
    this.maxLines = 3,
    super.visibleWhen,
  });

  final CreationText? hint;
  final int maxLines;

  @override
  String get defaultValue => '';
}

/// Lo que la hoja le da a las opciones propias de un tipo que se dibujan a
/// mano ([CreationKindSpec.optionsBuilder]): las de ahora, cómo cambiarlas y
/// sobre qué se crea.
@immutable
class CreationOptionsContext {
  const CreationOptionsContext({
    required this.kind,
    required this.scope,
    required this.options,
    required this.set,
    this.sources = const [],
  });

  final StudyCreationKind kind;
  final CreationScope scope;

  /// Las opciones de ahora, con las de fábrica ya puestas.
  final Map<String, Object?> options;

  /// Cambia una opción: la hoja se vuelve a dibujar y la estimación se rehace.
  final void Function(String key, Object? value) set;

  /// Las fuentes del recorte, una vez leídas (vacía mientras tanto).
  final List<CreationSource> sources;
}

/// Las opciones propias de un tipo, dibujadas a mano: un carrusel de estilos
/// con muestra, la galería de plantillas. Van debajo de las de
/// [CreationKindSpec.options].
typedef CreationOptionsBuilder =
    Widget Function(BuildContext context, CreationOptionsContext options);

/// El visor de una creación lista: lo que va debajo de la barra común del
/// visor (←, el título, «Ver N fuentes» con las fuentes como chips y ⋮).
typedef CreationViewerBuilder =
    Widget Function(BuildContext context, StudyCreation creation);

/// Los botones propios de un visor en la barra común: compartir, exportar,
/// pantalla completa.
typedef CreationViewerActionsBuilder =
    List<Widget> Function(BuildContext context, StudyCreation creation);

/// El archivo de una creación, para «Compartir» y «Descargar»: un PDF, un
/// PNG, un Markdown, un CSV… lo arma el tipo, con su diseño.
@immutable
class CreationExportFile {
  const CreationExportFile({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  /// Con su extensión: `Éxodo.pdf`.
  final String fileName;
  final Uint8List bytes;

  /// `application/pdf`, `image/png`, `text/markdown`…
  final String mimeType;
}

/// Arma el archivo de [creation] —ya lista— para compartirlo o descargarlo;
/// `null` si no hay nada que exportar (o se canceló algo que preguntó).
typedef CreationExporter =
    Future<CreationExportFile?> Function(
      BuildContext context,
      WidgetRef ref,
      StudyCreation creation,
    );

/// El color propio del ícono de un tipo (como los de NotebookLM Studio): uno
/// vivo para los temas claros y su par más luminoso para los oscuros. Se
/// ajusta solo para que se lea sobre la superficie de cada tema
/// ([resolve]).
@immutable
class CreationAccent {
  const CreationAccent({required this.light, required this.dark});

  final Color light;
  final Color dark;

  /// El de [brightness], llevado hasta 3:1 sobre [surface] —lo que pide WCAG
  /// para un ícono— si un tema con nombre lo deja corto.
  Color resolve(Brightness brightness, Color surface) =>
      CreationContrast.ensure(
        brightness == Brightness.dark ? dark : light,
        surface,
        minimum: 3,
      );

  /// El de este tema, sobre su superficie de tarjetas.
  Color of(BuildContext context) {
    final theme = Theme.of(context);
    return resolve(theme.brightness, theme.colorScheme.surfaceContainerHigh);
  }
}

/// Cómo es un tipo de creación en Repasar (F43): su tarjeta de crear, su hoja
/// de personalizar, cuánto estima que consume y su visor.
///
/// **El registro de la ola 3.** Cada tipo arranca con el suyo de fábrica
/// (`defaultCreationKindSpec`), que ya deja la pantalla funcionando de punta a
/// punta: la tarjeta, la hoja con las opciones del plan y «visor en camino».
/// Quien construye un tipo suma, en su carpeta, un proveedor con el suyo —casi
/// siempre el de fábrica con su visor— y UNA línea en
/// `creationKindSpecsProvider`:
///
/// ```dart
/// final mindMapKindSpecProvider = Provider<CreationKindSpec>(
///   (ref) => defaultCreationKindSpec(StudyCreationKind.mindMap).copyWith(
///     viewerBuilder: (context, creation) => MindMapViewer(creation: creation),
///   ),
/// );
/// ```
@immutable
class CreationKindSpec {
  const CreationKindSpec({
    required this.kind,
    required this.accent,
    required this.sheetTitle,
    this.tileLabel,
    this.icon,
    this.fields = const {CreationField.language, CreationField.sources},
    this.options = const [],
    this.optionsBuilder,
    this.extraDefaults = const {},
    this.descriptionHint,
    this.expectedOutputTokens,
    this.illustrations,
    this.viewerBuilder,
    this.viewerActions,
    this.exporter,
  });

  final StudyCreationKind kind;

  /// El color de su ícono.
  final CreationAccent accent;

  /// El título de su hoja: «Personalizar la presentación».
  final CreationText sheetTitle;

  /// El nombre en su tarjeta de crear; sin esto, el de su tipo
  /// (`studyCreationKindLabel`).
  final CreationText? tileLabel;

  /// Su ícono; sin esto, el de su tipo (`studyCreationKindIcon`).
  final IconData? icon;

  /// Las piezas comunes que lleva su hoja.
  final Set<CreationField> fields;

  /// Sus opciones, como dato, en el orden en que se muestran.
  final List<CreationOptionSpec> options;

  /// Opciones dibujadas a mano, debajo de [options].
  final CreationOptionsBuilder? optionsBuilder;

  /// Valores de fábrica de lo que pone [optionsBuilder] (los de [options] ya
  /// salen de cada una).
  final Map<String, Object?> extraDefaults;

  /// El ejemplo tenue de «Describí lo que querés crear».
  final CreationText? descriptionHint;

  /// Cuánto se estima que escribe la IA con estas opciones, para «Uso de IA»
  /// y para reservarle lugar en la ventana. Sin esto, 2.000 tokens. Las de
  /// extraer no escriben nada.
  final int Function(Map<String, Object?> options)? expectedOutputTokens;

  /// Cuántas ilustraciones pide con estas opciones (decisión H); sin esto,
  /// ninguna.
  final int Function(Map<String, Object?> options)? illustrations;

  /// Su visor; sin esto, «visor en camino».
  final CreationViewerBuilder? viewerBuilder;

  /// Los botones propios de su visor en la barra común.
  final CreationViewerActionsBuilder? viewerActions;

  /// Su archivo, para «Compartir» y «Descargar» en «Lo creado» (el menú de
  /// mantener apretado y el botón que aparece al deslizar). Sin esto, esas
  /// dos no se ofrecen: nunca un botón que no hace nada.
  final CreationExporter? exporter;

  /// Lo que la IA escribe por defecto, si el tipo no dice otra cosa.
  static const defaultOutputTokens = 2000;

  /// El nombre de su tarjeta.
  String label(AppLocalizations l10n) =>
      tileLabel?.call(l10n) ?? studyCreationKindLabel(l10n, kind);

  /// Su ícono.
  IconData get iconData => icon ?? studyCreationKindIcon(kind);

  /// Si le pide algo a la IA: todas menos las de extraer.
  bool get usesAi => kind.usesAi;

  /// Si su hoja puede pedir ilustraciones con IA.
  bool get offersIllustrations =>
      options.any((o) => o is CreationToggleOption && o.illustrations);

  /// Las opciones de fábrica: las de cada una de [options] y [extraDefaults].
  Map<String, Object?> get defaults => {
    for (final option in options) option.key: option.defaultValue,
    ...extraDefaults,
  };

  /// [saved] —lo último que se eligió— sobre las de fábrica: lo que no se
  /// guardó, o ya no es válido, queda de fábrica.
  Map<String, Object?> withDefaults(Map<String, Object?> saved) {
    final merged = {...defaults, ...saved};
    for (final option in options) {
      merged[option.key] = switch (option) {
        final CreationChoiceOption o => o.valueIn(merged),
        final CreationMultiChoiceOption o => o.valuesIn(merged),
        final CreationToggleOption o => o.valueIn(merged),
        CreationTextOption() =>
          merged[option.key] is String ? merged[option.key] : '',
      };
    }
    return merged;
  }

  /// Cuánto escribe la IA con [options].
  int outputTokensFor(Map<String, Object?> options) =>
      usesAi ? (expectedOutputTokens?.call(options) ?? defaultOutputTokens) : 0;

  /// Cuántas ilustraciones pide con [options]: ninguna si el interruptor de
  /// ilustraciones está apagado.
  int illustrationsFor(Map<String, Object?> options) {
    final toggles = [
      for (final o in this.options)
        if (o is CreationToggleOption && o.illustrations) o,
    ];
    if (toggles.isEmpty || !toggles.any((t) => t.valueIn(options))) return 0;
    return illustrations?.call(options) ?? 0;
  }

  CreationKindSpec copyWith({
    CreationAccent? accent,
    CreationText? sheetTitle,
    CreationText? tileLabel,
    IconData? icon,
    Set<CreationField>? fields,
    List<CreationOptionSpec>? options,
    CreationOptionsBuilder? optionsBuilder,
    Map<String, Object?>? extraDefaults,
    CreationText? descriptionHint,
    int Function(Map<String, Object?> options)? expectedOutputTokens,
    int Function(Map<String, Object?> options)? illustrations,
    CreationViewerBuilder? viewerBuilder,
    CreationViewerActionsBuilder? viewerActions,
    CreationExporter? exporter,
  }) => CreationKindSpec(
    kind: kind,
    accent: accent ?? this.accent,
    sheetTitle: sheetTitle ?? this.sheetTitle,
    tileLabel: tileLabel ?? this.tileLabel,
    icon: icon ?? this.icon,
    fields: fields ?? this.fields,
    options: options ?? this.options,
    optionsBuilder: optionsBuilder ?? this.optionsBuilder,
    extraDefaults: extraDefaults ?? this.extraDefaults,
    descriptionHint: descriptionHint ?? this.descriptionHint,
    expectedOutputTokens: expectedOutputTokens ?? this.expectedOutputTokens,
    illustrations: illustrations ?? this.illustrations,
    viewerBuilder: viewerBuilder ?? this.viewerBuilder,
    viewerActions: viewerActions ?? this.viewerActions,
    exporter: exporter ?? this.exporter,
  );
}
