import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_auto.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';

/// Un lugar de la lámina que lleva una ilustración con IA (decisión H): la
/// cabecera o un bloque.
@immutable
class InfographicSlot {
  const InfographicSlot._({
    required this.id,
    required this.blockIndex,
    required this.prompt,
    required this.aspect,
  });

  /// El id de la cabecera.
  static const headerId = 'header';

  /// El id del bloque [index] (su lugar en `Infographic.blocks`, que no
  /// cambia después de escrito).
  static String blockId(int index) => 'block-$index';

  /// `header` o `block-<n>`: con esto se guarda por qué no salió.
  final String id;

  /// El bloque, o `null` en la cabecera.
  final int? blockIndex;

  /// Qué dibujar, en una o dos oraciones: lo que escribió la IA o, si no
  /// escribió nada, lo que cuenta el bloque.
  final String prompt;

  /// La forma del lugar donde va.
  final IllustrationAspect aspect;

  bool get isHeader => blockIndex == null;

  @override
  bool operator ==(Object other) =>
      other is InfographicSlot &&
      other.id == id &&
      other.prompt == prompt &&
      other.aspect == aspect;

  @override
  int get hashCode => Object.hash(id, prompt, aspect);

  @override
  String toString() => 'InfographicSlot($id)';
}

/// Qué ilustraciones lleva una infografía con un diseño, y cómo se anotan en
/// su contenido (F43, paso 12). Todo determinista y sin IA: lo mismo decide
/// qué se pide al generar, qué falta después de cambiar el estilo en el visor
/// y qué se rehace de a una.
abstract final class InfographicIllustrationPlan {
  /// Los lugares de [sheet] con [design] que muestran una ilustración, en el
  /// orden en que se piden: la cabecera primero y después los bloques, de lo
  /// que más pesa a lo que menos.
  ///
  /// - **Un estilo con ilustraciones con IA** (Plastilina, Kawaii…) la
  ///   muestra en la cabecera y en cada bloque que se ve y tiene lugar para
  ///   ella: los hechos, los conceptos, los pasos y los hitos.
  /// - **Uno dibujado por la app** solo en los bloques que la pidieron
  ///   (`illustrationPrompt`) o ya tienen una; su cabecera no lleva.
  ///
  /// Las cifras, los gráficos, las citas y las comparaciones nunca: lo suyo
  /// es su número, su dibujo o su texto.
  static List<InfographicSlot> slotsFor(
    Infographic sheet,
    InfographicDesign design,
  ) {
    final arrangement = InfographicAuto.arrange(sheet, design);
    final illustrated = arrangement.style.isIllustrated;
    final shown = <int>[
      for (var i = 0; i < sheet.blocks.length; i++)
        if (arrangement.blocks.any((b) => identical(b, sheet.blocks[i]))) i,
    ];
    final blocks =
        [
          for (final i in shown)
            if (showsArt(sheet.blocks[i]) &&
                (illustrated || sheet.blocks[i].wantsIllustration))
              i,
        ]..sort((a, b) {
          final byLevel = sheet.blocks[a].level.value.compareTo(
            sheet.blocks[b].level.value,
          );
          return byLevel != 0 ? byLevel : a.compareTo(b);
        });
    return [
      if (illustrated)
        InfographicSlot._(
          id: InfographicSlot.headerId,
          blockIndex: null,
          prompt: _headerPrompt(sheet),
          // La cabecera de los estilos ilustrados es un recuadro al costado
          // del título: casi cuadrado en la vertical, más ancho en las otras.
          aspect: design.orientation == InfographicOrientation.portrait
              ? IllustrationAspect.square
              : IllustrationAspect.classic,
        ),
      for (final i in blocks)
        InfographicSlot._(
          id: InfographicSlot.blockId(i),
          blockIndex: i,
          prompt: _blockPrompt(sheet.blocks[i]),
          // Cada composición la recorta a su forma (un círculo, una franja):
          // el cuadrado es lo que mejor aguanta todos los recortes.
          aspect: IllustrationAspect.square,
        ),
    ];
  }

  /// Los de [slotsFor] que todavía no tienen su ilustración.
  static List<InfographicSlot> missing(
    Infographic sheet,
    InfographicDesign design,
  ) => [
    for (final slot in slotsFor(sheet, design))
      if (referenceOf(sheet, slot.id) == null) slot,
  ];

  /// Si [block] tiene un lugar para una ilustración en la lámina.
  static bool showsArt(InfographicBlock block) =>
      block is FactBlock ||
      block is ConceptBlock ||
      block is StepBlock ||
      block is EventBlock;

  /// La ilustración ya hecha del lugar [slotId], o `null`.
  static String? referenceOf(Infographic sheet, String slotId) {
    if (slotId == InfographicSlot.headerId) return sheet.illustrationRef;
    final index = _indexOf(slotId);
    if (index == null || index >= sheet.blocks.length) return null;
    return sheet.blocks[index].illustrationRef;
  }

  /// [sheet] con [reference] como la ilustración del lugar [slotId] (`null`
  /// la quita: vuelve el dibujo de la app).
  static Infographic withReference(
    Infographic sheet,
    String slotId,
    String? reference,
  ) {
    if (slotId == InfographicSlot.headerId) {
      return sheet.copyWith(illustrationRef: reference);
    }
    final index = _indexOf(slotId);
    if (index == null || index >= sheet.blocks.length) return sheet;
    final blocks = [...sheet.blocks];
    blocks[index] = _withRef(blocks[index], reference);
    return sheet.copyWith(blocks: blocks);
  }

  /// Todas las ilustraciones ya hechas de [sheet].
  static Set<String> references(Infographic sheet) => {
    ?sheet.illustrationRef,
    for (final block in sheet.blocks) ?block.illustrationRef,
  };

  static int? _indexOf(String slotId) {
    if (!slotId.startsWith('block-')) return null;
    return int.tryParse(slotId.substring('block-'.length));
  }

  static String _headerPrompt(Infographic sheet) {
    final asked = sheet.illustrationPrompt?.trim() ?? '';
    if (asked.isNotEmpty) return asked;
    return [
      sheet.title,
      if (sheet.subtitle.isNotEmpty) sheet.subtitle,
    ].join('. ');
  }

  static String _blockPrompt(InfographicBlock block) {
    final asked = block.illustrationPrompt?.trim() ?? '';
    if (asked.isNotEmpty) return asked;
    final detail = switch (block) {
      FactBlock(:final detail) ||
      ConceptBlock(:final detail) ||
      StepBlock(:final detail) ||
      EventBlock(:final detail) => detail,
      _ => '',
    };
    return [block.headline, if (detail.isNotEmpty) detail].join('. ');
  }

  static InfographicBlock _withRef(InfographicBlock b, String? reference) =>
      switch (b) {
        final StatBlock s => s.copyWith(illustrationRef: reference),
        final FactBlock s => s.copyWith(illustrationRef: reference),
        final StepBlock s => s.copyWith(illustrationRef: reference),
        final ComparisonBlock s => s.copyWith(illustrationRef: reference),
        final EventBlock s => s.copyWith(illustrationRef: reference),
        final ConceptBlock s => s.copyWith(illustrationRef: reference),
        final QuoteBlock s => s.copyWith(illustrationRef: reference),
        final ChartBlock s => s.copyWith(illustrationRef: reference),
      };
}
