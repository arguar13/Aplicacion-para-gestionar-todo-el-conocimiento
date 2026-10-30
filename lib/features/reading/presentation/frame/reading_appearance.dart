import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';

/// Las cinco letras de lectura del marco (F47, paso 1, «Apariencia»), todas
/// viajando con la app —nada se baja al leer—, con su licencia OFL al lado en
/// `assets/fonts/`:
///
/// - [lora], la serif de libro, **la de entrada**: lo que se lee largo;
/// - [sourceSans], una sans humanista, abierta y de trazo cálido;
/// - [inter], la sans de la app, neutra y muy pareja;
/// - [nunito], redondeada y amable;
/// - [atkinson], la del Braille Institute: cada letra se distingue de las
///   parecidas, para leer sin esfuerzo con poca visión.
///
/// Las cuatro primeras ya venían (Inter con la app; las otras con «Lo
/// creado», F43); la quinta la trae `tool/fetch_reading_fonts.sh`.
enum ReadingFont {
  lora('Lora', serif: true),
  sourceSans('Source Sans 3'),
  // «Inter Creation» y no «Inter»: es el mismo archivo con todos los pesos
  // declarados —las palabras clave van en negrita, y en «Inter» la app la
  // sintetiza sobre el peso medio—.
  inter('Inter Creation'),
  nunito('Nunito'),
  atkinson('Atkinson Hyperlegible Next');

  const ReadingFont(this.family, {this.serif = false});

  /// La familia, como la declara pubspec.yaml.
  final String family;

  /// Si es una serif: la que se lee como un libro.
  final bool serif;

  /// La de entrada: una serif de lectura.
  static const fallback = ReadingFont.lora;

  /// Los pesos que cada familia declara en pubspec.yaml: la prueba de las
  /// letras comprueba que estén, para que el texto y su negrita no se
  /// sinteticen.
  static const Map<String, List<int>> declaredWeights = {
    'Lora': [400, 700],
    'Source Sans 3': [400, 700],
    'Inter Creation': [400, 700],
    'Nunito': [400, 800],
    'Atkinson Hyperlegible Next': [400, 700],
  };

  static ReadingFont fromStorage(String? name) =>
      values.firstWhere((font) => font.name == name, orElse: () => fallback);
}

/// El color de «Resaltado de lectura»: el fondo suave de la línea que suena
/// (F47, paso 1). Todos claros, con la letra oscura encima en cualquier modo
/// —se lee de un vistazo mientras se escucha—, y ninguno se confunde con los
/// tres de estudiar: el verde del resumen, el celeste de la síntesis y el
/// rosa de las palabras clave.
enum ReadingHighlight {
  /// El amarillo de siempre (F23).
  yellow(RenderedMarkdown.playingColor),
  peach(Color(0xFFFFC48C)),
  lilac(Color(0xFFD7C4FF)),
  lime(Color(0xFFE4F28A));

  const ReadingHighlight(this.color);

  final Color color;

  static const fallback = ReadingHighlight.yellow;

  static ReadingHighlight fromStorage(String? name) => values.firstWhere(
    (highlight) => highlight.name == name,
    orElse: () => fallback,
  );
}

/// El modo de lectura: los colores del marco y de lo que se lee, aparte del
/// tema de la app.
enum ReadingMode {
  /// Los de la app, que a su vez puede seguir al teléfono.
  system,
  light,
  dark,

  /// Papel cálido para leer largo: el Sepia de los temas de Ajustes (F39).
  sepia;

  static const fallback = ReadingMode.system;

  static ReadingMode fromStorage(String? name) =>
      values.firstWhere((mode) => mode.name == name, orElse: () => fallback);

  /// El tema con que se ve el marco, sobre [app], el de la app.
  ThemeData themeOver(ThemeData app) => switch (this) {
    ReadingMode.system => app,
    ReadingMode.light => AppThemeChoice.light.theme,
    ReadingMode.dark => AppThemeChoice.dark.darkTheme,
    ReadingMode.sepia => AppThemeChoice.sepia.theme,
  };
}

/// El tono de la página de un PDF o de una foto (F47, paso 1): se elige
/// aparte del modo, porque una página es una imagen y no se le cambian los
/// colores a sus letras.
enum ReadingPaper {
  /// Como es.
  original,

  /// Los claros pasan a oscuros y los oscuros a claros **sin cambiar de
  /// color** —se invierte y se da media vuelta al tono—: el papel blanco se
  /// vuelve casi negro, la letra negra casi blanca, y lo marcado sigue
  /// siendo verde, celeste o rosa.
  dark,

  /// Papel cálido: los tonos de una foto vieja.
  sepia;

  static const fallback = ReadingPaper.original;

  static ReadingPaper fromStorage(String? name) =>
      values.firstWhere((paper) => paper.name == name, orElse: () => fallback);

  /// La matriz de color que lo pinta, o `null` si se ve como es.
  List<double>? get matrix => switch (this) {
    ReadingPaper.original => null,
    // Invertir y girar el tono 180°: los dos cambios juntos dejan cada color
    // con su tono y con la luz al revés (la «inversión inteligente» de los
    // teléfonos).
    // Es `255 − H·v`, con H la media vuelta de `hue-rotate(180deg)` de CSS;
    // cada fila de H suma 1, así el blanco da negro y el negro, blanco.
    ReadingPaper.dark => const [
      0.574, -1.43, -0.144, 0, 255, //
      -0.426, -0.43, -0.144, 0, 255, //
      -0.426, -1.43, 0.856, 0, 255, //
      0, 0, 0, 1, 0,
    ],
    // El sepia de siempre (el de los filtros de CSS).
    ReadingPaper.sepia => const [
      0.393, 0.769, 0.189, 0, 0, //
      0.349, 0.686, 0.168, 0, 0, //
      0.272, 0.534, 0.131, 0, 0, //
      0, 0, 0, 1, 0,
    ],
  };
}

/// Cómo se lee: la letra, su tamaño, el color de lo que suena y el modo. **Una
/// sola para todos los lectores** —el original, el texto extraído, el
/// resumen, la síntesis y lo creado—, guardada entre reinicios.
@immutable
class ReadingAppearance {
  const ReadingAppearance({
    this.font = ReadingFont.fallback,
    this.scale = 1,
    this.highlight = ReadingHighlight.fallback,
    this.mode = ReadingMode.fallback,
    this.paper = ReadingPaper.fallback,
    this.aiRowOpen = true,
  });

  final ReadingFont font;

  /// Cuánto se agranda o achica la letra respecto de la de base, entre
  /// [ReadingAppearanceNotifier.minScale] y
  /// [ReadingAppearanceNotifier.maxScale].
  final double scale;

  final ReadingHighlight highlight;
  final ReadingMode mode;

  /// El tono de la página de un PDF o de una foto.
  final ReadingPaper paper;

  /// Si la fila de IA está a la vista debajo de la barra. Abierta de entrada:
  /// es donde se marca el resumen, la síntesis y las palabras clave.
  final bool aiRowOpen;

  ReadingAppearance copyWith({
    ReadingFont? font,
    double? scale,
    ReadingHighlight? highlight,
    ReadingMode? mode,
    ReadingPaper? paper,
    bool? aiRowOpen,
  }) => ReadingAppearance(
    font: font ?? this.font,
    scale: scale ?? this.scale,
    highlight: highlight ?? this.highlight,
    mode: mode ?? this.mode,
    paper: paper ?? this.paper,
    aiRowOpen: aiRowOpen ?? this.aiRowOpen,
  );

  /// La letra del texto que se lee sobre [theme]: la elegida, a su tamaño,
  /// con el interlineado holgado de un libro.
  TextStyle bodyStyle(ThemeData theme) {
    final base = theme.textTheme.bodyLarge?.fontSize ?? 16;
    return (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: font.family,
      fontSize: base * 1.06 * scale,
      height: 1.65,
      color: theme.colorScheme.onSurface,
    );
  }

  /// Los títulos con la misma letra que el texto, en serif si se lee en serif.
  TextStyle titleStyle(ThemeData theme, {double size = 26}) =>
      (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontFamily: font.family,
        fontSize: size,
        height: 1.18,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      );

  @override
  bool operator ==(Object other) =>
      other is ReadingAppearance &&
      other.font == font &&
      other.scale == scale &&
      other.highlight == highlight &&
      other.mode == mode &&
      other.paper == paper &&
      other.aiRowOpen == aiRowOpen;

  @override
  int get hashCode =>
      Object.hash(font, scale, highlight, mode, paper, aiRowOpen);
}

/// [ReadingAppearance] entre reinicios, en las preferencias del teléfono:
/// mismo criterio que `ThemeChoiceNotifier`.
///
/// El tamaño se guarda con la clave de antes (`reader_font_scale`, la de A− A+
/// de «Leer como libro» y de «Lectura» de «Lo creado»): quien ya había
/// agrandado la letra la sigue viendo grande.
class ReadingAppearanceNotifier extends StateNotifier<ReadingAppearance> {
  ReadingAppearanceNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_readInitial(prefs));

  @visibleForTesting
  static const scaleKey = 'reader_font_scale';
  @visibleForTesting
  static const fontKey = 'reading_font';
  @visibleForTesting
  static const highlightKey = 'reading_highlight';
  @visibleForTesting
  static const modeKey = 'reading_mode';
  @visibleForTesting
  static const paperKey = 'reading_paper';
  @visibleForTesting
  static const aiRowKey = 'reading_ai_row_open';

  /// Un paso de más o de menos no cambia mucho a simple vista; ocho pasos sí,
  /// sin llegar a un extremo donde el texto deje de caber cómodo en la
  /// columna.
  static const minScale = 0.8;
  static const maxScale = 1.6;
  static const scaleStep = 0.1;

  /// Cuántos puntos tiene el deslizador del tamaño, puntas incluidas.
  static int get scaleStops => ((maxScale - minScale) / scaleStep).round() + 1;

  final SharedPreferences _prefs;

  static ReadingAppearance _readInitial(SharedPreferences prefs) =>
      ReadingAppearance(
        font: ReadingFont.fromStorage(prefs.getString(fontKey)),
        scale: (prefs.getDouble(scaleKey) ?? 1).clamp(minScale, maxScale),
        highlight: ReadingHighlight.fromStorage(prefs.getString(highlightKey)),
        mode: ReadingMode.fromStorage(prefs.getString(modeKey)),
        paper: ReadingPaper.fromStorage(prefs.getString(paperKey)),
        aiRowOpen: prefs.getBool(aiRowKey) ?? true,
      );

  Future<void> setFont(ReadingFont font) async {
    state = state.copyWith(font: font);
    await _prefs.setString(fontKey, font.name);
  }

  /// El tamaño, llevado al paso más cercano dentro de los topes.
  Future<void> setScale(double value) async {
    final steps = ((value - minScale) / scaleStep).round();
    final snapped = double.parse(
      (minScale + steps * scaleStep)
          .clamp(minScale, maxScale)
          .toStringAsFixed(2),
    );
    if (snapped == state.scale) return;
    state = state.copyWith(scale: snapped);
    await _prefs.setDouble(scaleKey, snapped);
  }

  Future<void> increase() => setScale(state.scale + scaleStep);
  Future<void> decrease() => setScale(state.scale - scaleStep);

  Future<void> setHighlight(ReadingHighlight highlight) async {
    state = state.copyWith(highlight: highlight);
    await _prefs.setString(highlightKey, highlight.name);
  }

  Future<void> setMode(ReadingMode mode) async {
    state = state.copyWith(mode: mode);
    await _prefs.setString(modeKey, mode.name);
  }

  Future<void> setPaper(ReadingPaper paper) async {
    state = state.copyWith(paper: paper);
    await _prefs.setString(paperKey, paper.name);
  }

  Future<void> setAiRowOpen({required bool open}) async {
    state = state.copyWith(aiRowOpen: open);
    await _prefs.setBool(aiRowKey, open);
  }
}

/// La apariencia de lectura de todos los lectores.
final readingAppearanceProvider =
    StateNotifierProvider<ReadingAppearanceNotifier, ReadingAppearance>(
      (ref) => ReadingAppearanceNotifier(
        prefs: ref.watch(sharedPreferencesProvider),
      ),
    );

/// El color de lo que suena, el elegido en «Resaltado de lectura».
final readingHighlightColorProvider = Provider<Color>(
  (ref) =>
      ref.watch(readingAppearanceProvider.select((a) => a.highlight.color)),
);
