import 'package:meta/meta.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';

/// Lo que se dibuja de una infografía con un diseño, ya decidido: el estilo
/// y la composición de verdad (sin «Automático»), y los bloques que se ven
/// con el detalle elegido y que entran en esa composición.
@immutable
class InfographicArrangement {
  const InfographicArrangement({
    required this.style,
    required this.composition,
    required this.blocks,
    required this.showDetails,
  });

  final InfographicStyleId style;
  final InfographicComposition composition;

  /// En el orden en que los escribió la IA.
  final List<InfographicBlock> blocks;

  /// Si los bloques llevan su detalle (en «Conciso», no).
  final bool showDetails;
}

/// Las decisiones de «Automático» y «Automática», y lo que se ve con cada
/// detalle (F43, «Plantillas → Infografía»). Todo determinista: la misma
/// infografía con el mismo diseño se arma siempre igual —la miniatura de la
/// galería y la lámina grande coinciden—, y nada vuelve a la IA.
abstract final class InfographicAuto {
  /// El estilo, la composición y los bloques de [sheet] con [design].
  static InfographicArrangement arrange(
    Infographic sheet,
    InfographicDesign design,
  ) {
    final visible = visibleBlocks(sheet, design.detail);
    final composition = design.composition == InfographicComposition.auto
        ? compositionFor(sheet, visible)
        : design.composition;
    return InfographicArrangement(
      style: design.style == InfographicStyleId.auto
          ? styleFor(sheet)
          : design.style,
      composition: composition,
      blocks: fitCapacity(visible, capacity(composition, design.orientation)),
      showDetails: design.detail != InfographicDetail.concise,
    );
  }

  /// Los bloques que se ven con [detail]: en «Conciso», lo esencial; en
  /// «Estándar», también lo de apoyo; en «Detallado», todo. Nunca menos de
  /// tres (o de los que haya): si faltan, entran los que más pesan.
  static List<InfographicBlock> visibleBlocks(
    Infographic sheet,
    InfographicDetail detail,
  ) {
    final threshold = switch (detail) {
      InfographicDetail.concise => 1,
      InfographicDetail.standard => 2,
      InfographicDetail.detailed => 3,
    };
    final blocks = sheet.blocks;
    final keep = {
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].level.value <= threshold) i,
    };
    final minimum = blocks.length < 3 ? blocks.length : 3;
    if (keep.length < minimum) {
      for (final i in _byWeight(blocks)) {
        if (keep.length >= minimum) break;
        keep.add(i);
      }
    }
    return [
      for (var i = 0; i < blocks.length; i++)
        if (keep.contains(i)) blocks[i],
    ];
  }

  /// Los primeros [max] de [blocks] por peso, en su orden original.
  static List<InfographicBlock> fitCapacity(
    List<InfographicBlock> blocks,
    int max,
  ) {
    if (blocks.length <= max) return blocks;
    final keep = _byWeight(blocks).take(max).toSet();
    return [
      for (var i = 0; i < blocks.length; i++)
        if (keep.contains(i)) blocks[i],
    ];
  }

  /// Los índices de [blocks], de lo que más pesa a lo que menos; entre dos
  /// del mismo nivel, primero el que va antes.
  static List<int> _byWeight(List<InfographicBlock> blocks) =>
      List<int>.generate(blocks.length, (i) => i)..sort((a, b) {
        final byLevel = blocks[a].level.value.compareTo(blocks[b].level.value);
        return byLevel != 0 ? byLevel : a.compareTo(b);
      });

  /// Cuántos bloques entran en [composition] con [orientation] sin que la
  /// letra quede chica.
  static int capacity(
    InfographicComposition composition,
    InfographicOrientation orientation,
  ) {
    final portrait = orientation == InfographicOrientation.portrait;
    final square = orientation == InfographicOrientation.square;
    return switch (composition) {
      InfographicComposition.auto || InfographicComposition.bento => 9,
      InfographicComposition.columns => portrait || square ? 6 : 8,
      InfographicComposition.zigzag => square ? 5 : 6,
      InfographicComposition.timeline => square ? 6 : 7,
      InfographicComposition.process => portrait || square ? 6 : 8,
      InfographicComposition.radial => portrait || square ? 6 : 8,
      InfographicComposition.comparison => 5,
      InfographicComposition.pyramid => 5,
      InfographicComposition.statPanel => 8,
      InfographicComposition.conceptMap => 8,
    };
  }

  /// La composición que mejor cuenta [visible]: la que sugirió la IA si el
  /// contenido la sostiene, o la que dicen los tipos de bloque.
  static InfographicComposition compositionFor(
    Infographic sheet,
    List<InfographicBlock> visible,
  ) {
    final counts = _Counts(visible);
    final hinted = _compositionHint(sheet.compositionHint);
    if (hinted != null && supports(hinted, visible)) return hinted;
    final n = counts.total;
    if (counts.comparisons >= 1 && n - counts.comparisons <= 4) {
      return InfographicComposition.comparison;
    }
    if (counts.events >= 3 && counts.events * 2 >= n) {
      return InfographicComposition.timeline;
    }
    if (counts.steps >= 3 && counts.steps * 2 >= n) {
      return InfographicComposition.process;
    }
    if (counts.numeric >= 3 && counts.numeric * 2 >= n) {
      return InfographicComposition.statPanel;
    }
    if (counts.concepts >= 4 && counts.concepts * 5 >= n * 3) {
      return InfographicComposition.conceptMap;
    }
    final ideas = counts.facts + counts.concepts;
    if (n <= 4 && ideas == n) return InfographicComposition.columns;
    if (ideas == n && n <= 6 && counts.illustrated >= 3) {
      return InfographicComposition.zigzag;
    }
    if (ideas == n && n >= 5 && n <= 7) return InfographicComposition.radial;
    return InfographicComposition.bento;
  }

  /// Si [composition] tiene con qué armarse con [visible]: una cronología
  /// sin hitos o un panel de cifras sin números no se eligen solos.
  static bool supports(
    InfographicComposition composition,
    List<InfographicBlock> visible,
  ) {
    final c = _Counts(visible);
    return switch (composition) {
      InfographicComposition.auto => false,
      InfographicComposition.bento || InfographicComposition.columns => true,
      InfographicComposition.timeline => c.events >= 3,
      InfographicComposition.process => c.steps >= 3,
      InfographicComposition.comparison => c.comparisons >= 1,
      InfographicComposition.statPanel => c.numeric >= 2,
      InfographicComposition.conceptMap => c.concepts + c.facts >= 4,
      InfographicComposition.zigzag => c.total >= 3 && c.total <= 7,
      InfographicComposition.radial => c.total >= 3 && c.total <= 8,
      InfographicComposition.pyramid => c.total >= 3 && c.total <= 6,
    };
  }

  /// El estilo de «Automático»: el que sugirió la IA según el tema, o el que
  /// dicen los bloques.
  static InfographicStyleId styleFor(Infographic sheet) {
    final hinted = _styleHint(sheet.styleHint);
    if (hinted != null && hinted != InfographicStyleId.auto) return hinted;
    final c = _Counts(sheet.blocks);
    if (c.total > 0 && c.numeric * 2 >= c.total) return InfographicStyleId.data;
    if (c.events >= 3) return InfographicStyleId.editorial;
    if (c.steps >= 3) return InfographicStyleId.corporate;
    if (c.comparisons >= 1) return InfographicStyleId.swiss;
    if (c.concepts >= 4) return InfographicStyleId.geometric;
    if (c.quotes >= 1) return InfographicStyleId.parchment;
    return InfographicStyleId.bento;
  }

  static InfographicComposition? _compositionHint(String? hint) {
    if (hint == null) return null;
    return InfographicComposition.fromJsonName(hint) ??
        _compositionAliases[hint.replaceAll('_', '')];
  }

  static const Map<String, InfographicComposition> _compositionAliases = {
    'bloques': InfographicComposition.bento,
    'grid': InfographicComposition.bento,
    'cuadricula': InfographicComposition.bento,
    'columnas': InfographicComposition.columns,
    'zigzag': InfographicComposition.zigzag,
    'lineadetiempo': InfographicComposition.timeline,
    'cronologia': InfographicComposition.timeline,
    'proceso': InfographicComposition.process,
    'pasos': InfographicComposition.process,
    'steps': InfographicComposition.process,
    'comparacion': InfographicComposition.comparison,
    'versus': InfographicComposition.comparison,
    'piramide': InfographicComposition.pyramid,
    'hierarchy': InfographicComposition.pyramid,
    'jerarquia': InfographicComposition.pyramid,
    'statpanel': InfographicComposition.statPanel,
    'panel': InfographicComposition.statPanel,
    'paneldecifras': InfographicComposition.statPanel,
    'cifras': InfographicComposition.statPanel,
    'stats': InfographicComposition.statPanel,
    'dashboard': InfographicComposition.statPanel,
    'conceptmap': InfographicComposition.conceptMap,
    'mapadeconceptos': InfographicComposition.conceptMap,
    'mapaconceptual': InfographicComposition.conceptMap,
    'mindmap': InfographicComposition.conceptMap,
  };

  static InfographicStyleId? _styleHint(String? hint) {
    if (hint == null) return null;
    return InfographicStyleId.fromId(hint) ??
        _styleAliases[hint.replaceAll('_', '')];
  }

  static const Map<String, InfographicStyleId> _styleAliases = {
    'geometrico': InfographicStyleId.geometric,
    'minimalsuizo': InfographicStyleId.swiss,
    'suizo': InfographicStyleId.swiss,
    'minimal': InfographicStyleId.swiss,
    'pizarra': InfographicStyleId.chalkboard,
    'neonoscuro': InfographicStyleId.neon,
    'pergamino': InfographicStyleId.parchment,
    'corporativo': InfographicStyleId.corporate,
    'infantil': InfographicStyleId.kids,
    'datos': InfographicStyleId.data,
    'plastilina': InfographicStyleId.clay,
    'acuarela': InfographicStyleId.watercolor,
    'isometrico': InfographicStyleId.isometric,
    'fotografico': InfographicStyleId.photo,
  };
}

class _Counts {
  _Counts(List<InfographicBlock> blocks) : total = blocks.length {
    for (final block in blocks) {
      switch (block) {
        case StatBlock() || ChartBlock():
          numeric++;
        case FactBlock():
          facts++;
        case StepBlock():
          steps++;
        case ComparisonBlock():
          comparisons++;
        case EventBlock():
          events++;
        case ConceptBlock():
          concepts++;
        case QuoteBlock():
          quotes++;
      }
      if (block.wantsIllustration) illustrated++;
    }
  }

  final int total;
  int numeric = 0;
  int facts = 0;
  int steps = 0;
  int comparisons = 0;
  int events = 0;
  int concepts = 0;
  int quotes = 0;
  int illustrated = 0;
}
