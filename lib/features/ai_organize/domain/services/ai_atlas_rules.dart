import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/vocabulary_hierarchy.dart';
import 'package:sinapsis/core/domain/services/inline_link_parser.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_atlas.dart';
import 'package:sinapsis/features/ai_organize/domain/services/map_note_language.dart';

/// Las reglas del Atlas de la IA (F27), sin base ni modelo: a qué temas se le
/// pregunta al modelo, cómo se arma una nota mapa y cuándo una nota viva
/// creció lo suficiente para proponer subirle la madurez. Funciones puras: lo
/// que deciden se prueba con datos armados a mano.

// ---------------------------------------------------------------------------
// El árbol de temas
// ---------------------------------------------------------------------------

/// Cuántos temas del árbol ve el modelo como posibles padres: unos 40 temas,
/// con su camino, son unos 600 tokens —con las instrucciones y la respuesta
/// entran holgados en la ventana de 2048—. La bóveda más grande que se midió
/// tiene 2.164 temas: no se mandan todos, se mandan los más probables.
const kAtlasParentCandidates = 40;

/// Cuántos temas sueltos de un mismo elemento se le preguntan al modelo por
/// pasada: cada pregunta son segundos del modelo del teléfono. Los que queden
/// se miran cuando otro elemento los traiga.
const kAtlasPlacementsPerItem = 3;

/// Los posibles padres de [valueId], de más a menos probable, hasta [max].
///
/// Solo temas que ya son parte del árbol —con padre o con subtemas—: si la
/// persona nunca armó un árbol, la IA no empieza uno («el árbol tiene
/// raíces»). Y solo los que dejan lugar debajo: un tema en el quinto nivel no
/// puede tener hijos.
///
/// El orden, sin modelo:
///
/// 1. un tema cuyas palabras están todas en el nombre del suelto —«Roma» para
///    «Roma imperial»—, por palabras enteras como las tarjetas de F13: «Arte»
///    no es padre de «Artesanía»;
/// 2. los otros temas del mismo elemento que están en el árbol, y sus
///    ancestros: si «Las legiones» es de «Ejército» y de «Roma», «Roma»
///    probablemente va cerca de «Ejército»;
/// 3. el resto, de los niveles más altos a los más bajos.
///
/// A igual rango, por nombre: lo mismo da lo mismo.
List<String> rankParentCandidates(
  AtlasTopicTree tree,
  String valueId, {
  Iterable<String> coTopicIds = const [],
  int max = kAtlasParentCandidates,
}) {
  final topic = tree[valueId];
  if (topic == null) return const [];
  final words = _words(topic.label);
  final related = <String>{
    for (final id in coTopicIds)
      if (id != valueId && tree.isInTree(id)) ...[
        id,
        ...tree.tree.ancestorsOf(id),
      ],
  };

  int rank(AtlasTopic candidate) {
    final own = _words(candidate.label);
    if (own.isNotEmpty && own.length < words.length && words.containsAll(own)) {
      return 0;
    }
    return related.contains(candidate.id) ? 1 : 2;
  }

  final ranked =
      [
        for (final candidate in tree.topics)
          if (candidate.id != valueId &&
              tree.isInTree(candidate.id) &&
              tree.tree.depthOf(candidate.id) < kVocabularyMaxDepth)
            (
              id: candidate.id,
              rank: rank(candidate),
              depth: tree.tree.depthOf(candidate.id),
              key: normalizeVocabularyLabel(candidate.label),
            ),
      ]..sort((a, b) {
        final byRank = a.rank.compareTo(b.rank);
        if (byRank != 0) return byRank;
        final byDepth = a.depth.compareTo(b.depth);
        if (byDepth != 0) return byDepth;
        return a.key.compareTo(b.key);
      });
  return [for (final candidate in ranked.take(max)) candidate.id];
}

final _nonLetters = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

Set<String> _words(String label) => {
  for (final word in normalizeVocabularyLabel(label).split(_nonLetters))
    if (word.isNotEmpty) word,
};

// ---------------------------------------------------------------------------
// Las notas mapa
// ---------------------------------------------------------------------------

/// Desde cuántos elementos un tema recibe su nota mapa: el mismo umbral que
/// el Atlas usa para avisar que un tema tiene material de sobra
/// (`kAtlasManySources`, F13). Con menos, la lista de la rama en el Atlas ya
/// es el índice; con cinco o más, un punto de entrada escrito ayuda.
/// Cuentan los elementos de la rama entera —el tema y sus subtemas—, cada
/// uno una vez, sin las notas mapa.
const kAiMapNoteMinItems = 5;

/// Cuántos enlaces lleva, como mucho, una nota mapa de la IA: un índice de
/// miles de enlaces no se lee. Si hay más, se eligen las notas antes que las
/// fuentes —son lo que la persona trabajó— y lo más reciente antes que lo
/// viejo, y la nota dice cuántos quedaron afuera; el Atlas los muestra todos.
const kAiMapNoteMaxLinks = 80;

/// Cuántas notas mapa crea o actualiza la IA por elemento: cada una es una
/// llamada al modelo para la introducción. Un elemento nuevo suma material a
/// su tema y a todos sus ancestros; los que queden se hacen con el próximo.
const kAiMapNotesPerItem = 3;

/// Cuántos elementos ve el modelo para escribir la introducción, con su
/// fragmento: los primeros del índice, que ya están ordenados.
const kAiMapIntroEntries = 20;

/// Una sección del índice: un encabezado y lo que va debajo.
@immutable
class MapNoteSection {
  const MapNoteSection({required this.heading, required this.entries});

  final String heading;
  final List<TopicMaterial> entries;
}

/// Cómo queda el índice de un tema, antes de la introducción.
@immutable
class MapNotePlan {
  const MapNotePlan({
    required this.sections,
    required this.omitted,
    required this.language,
  });

  final List<MapNoteSection> sections;

  /// Cuántos elementos del tema no entraron.
  final int omitted;

  /// En qué idioma están sus textos fijos: los encabezados y cuántos
  /// quedaron afuera.
  final MapNoteLanguage language;

  /// Lo que lista, en el orden en que aparece.
  List<TopicMaterial> get entries => [
    for (final section in sections) ...section.entries,
  ];

  /// Los destinos de sus enlaces, normalizados como se resuelven
  /// (`normalizeLinkTitle`): con esto se sabe si entró algo nuevo.
  Set<String> get linkedTitles => {
    for (final entry in entries) normalizeLinkTitle(entry.title),
  };
}

/// Si [title] se puede escribir como `[[título]]` y resolverse: no vacío, de
/// una línea y sin corchetes dobles que cortarían el enlace.
bool isLinkableTitle(String title) {
  final trimmed = title.trim();
  return trimmed.isNotEmpty &&
      !trimmed.contains('[[') &&
      !trimmed.contains(']]') &&
      !trimmed.contains('\n');
}

/// El índice del tema [topicId] con [material], agrupado con criterio:
///
/// - **Por subtema**, si lo que hay está repartido en subtemas: una sección
///   por cada subtema directo con material, por nombre, con lo de toda su
///   rama; y una «General» al final con lo que tiene puesto el tema mismo.
///   Un elemento de dos subtemas va en el primero, por nombre: un índice no
///   repite.
/// - **Notas y fuentes**, si no.
///
/// Dentro de cada sección, las notas vivas, después las otras notas y al
/// final las fuentes, cada grupo por título. Un título que no se puede
/// enlazar, o que repite el de otro —los dos enlaces irían al mismo—, no se
/// lista. Los encabezados fijos —«Notas», «Fuentes», «General»— salen en
/// [language].
MapNotePlan planMapNote({
  required AtlasTopicTree tree,
  required String topicId,
  required List<TopicMaterial> material,
  required MapNoteLanguage language,
  int maxLinks = kAiMapNoteMaxLinks,
}) {
  final seen = <String>{};
  final linkable = [
    for (final entry in material)
      if (isLinkableTitle(entry.title) &&
          seen.add(normalizeLinkTitle(entry.title)))
        entry,
  ];
  final chosen =
      ([...linkable]..sort((a, b) {
            final byKind = _priority(a).compareTo(_priority(b));
            if (byKind != 0) return byKind;
            return b.updatedAt.compareTo(a.updatedAt);
          }))
          .take(maxLinks)
          .toList();
  final omitted = material.length - chosen.length;

  // El subtema directo de [topicId] bajo el que cae cada valor de la rama.
  final children = [...tree.tree.childrenOf(topicId)]
    ..sort(
      (a, b) => normalizeVocabularyLabel(
        tree[a]!.label,
      ).compareTo(normalizeVocabularyLabel(tree[b]!.label)),
    );
  final childOf = <String, String>{
    for (final child in children) ...{
      child: child,
      for (final descendant in tree.tree.descendantsOf(child))
        descendant: child,
    },
  };

  final byChild = <String, List<TopicMaterial>>{};
  final general = <TopicMaterial>[];
  for (final entry in chosen) {
    final under = [
      for (final valueId in entry.valueIds)
        if (childOf[valueId] case final child?) child,
    ];
    if (under.isEmpty) {
      general.add(entry);
    } else {
      final first = children.firstWhere(under.contains);
      (byChild[first] ??= []).add(entry);
    }
  }

  final List<MapNoteSection> sections;
  if (byChild.isEmpty) {
    final notes = [
      for (final entry in general)
        if (entry.isNote) entry,
    ];
    final sources = [
      for (final entry in general)
        if (!entry.isNote) entry,
    ];
    sections = [
      if (notes.isNotEmpty)
        MapNoteSection(
          heading: language.notesHeading,
          entries: _ordered(notes),
        ),
      if (sources.isNotEmpty)
        MapNoteSection(
          heading: language.sourcesHeading,
          entries: _ordered(sources),
        ),
    ];
  } else {
    sections = [
      for (final child in children)
        if (byChild[child] case final entries?)
          MapNoteSection(
            heading: tree[child]!.label,
            entries: _ordered(entries),
          ),
      if (general.isNotEmpty)
        MapNoteSection(
          heading: language.generalHeading,
          entries: _ordered(general),
        ),
    ];
  }
  return MapNotePlan(sections: sections, omitted: omitted, language: language);
}

/// Las notas vivas primero —son lo que la persona trabajó—, después las otras
/// notas y al final las fuentes.
int _priority(TopicMaterial entry) => switch (entry.noteKind) {
  NoteKind.living => 0,
  null => 2,
  _ => 1,
};

List<TopicMaterial> _ordered(List<TopicMaterial> entries) =>
    [...entries]..sort((a, b) {
      final byKind = _priority(a).compareTo(_priority(b));
      if (byKind != 0) return byKind;
      return normalizeVocabularyLabel(
        a.title,
      ).compareTo(normalizeVocabularyLabel(b.title));
    });

/// Los bloques de la nota mapa: la introducción —si el modelo escribió
/// algo—, cada sección con su encabezado y un `[[enlace]]` por elemento, y
/// cuántos quedaron afuera, en el idioma del plan. Los enlaces salen de
/// [plan], es decir de la bóveda: nunca del modelo.
List<ContentBlock> mapNoteBlocks(MapNotePlan plan, {String intro = ''}) => [
  if (intro.trim().isNotEmpty) ContentBlock.paragraph(text: intro.trim()),
  for (final section in plan.sections) ...[
    ContentBlock.heading(text: section.heading, level: 2),
    for (final entry in section.entries)
      ContentBlock.bulletItem(text: '[[${entry.title.trim()}]]'),
  ],
  if (plan.omitted > 0)
    ContentBlock.paragraph(text: plan.language.omitted(plan.omitted)),
];

/// Los destinos de los enlaces de una nota guardada en bloques, normalizados;
/// vacío si no tiene bloques o no se pueden leer.
Set<String> linkedTitlesOf(String? blocksContent) {
  if (blocksContent == null) return const {};
  final blocks = tryDecodeContentBlocks(blocksContent);
  if (blocks == null) return const {};
  return {
    for (final mention in extractInlineLinksFromBlocks(blocks))
      mention.normalizedTitle,
  };
}

// ---------------------------------------------------------------------------
// La madurez
// ---------------------------------------------------------------------------

/// Cuándo una nota viva semilla se propone «en desarrollo» (decisión A: solo
/// se propone). «Semilla» es «puede ser solo el fragmento que le dio
/// origen»; «en desarrollo», «ya tiene estructura propia». Los tres a la
/// vez:
///
/// - **largo**: unos 1.200 caracteres de texto propio —dos o tres párrafos,
///   unas 200 palabras—, más que el fragmento que suele originarla;
/// - **vínculos**: con al menos 2 elementos —ya no está sola—;
/// - **edad**: 3 días desde que nació: volvió a ella, no es el impulso del
///   primer día.
const kDevelopingMinChars = 1200;
const kDevelopingMinConnections = 2;
const kDevelopingMinAge = Duration(days: 3);

/// Cuándo una nota viva en desarrollo se propone «madura»: «trabajada a fondo:
/// conecta con lo que tiene que conectar y dice lo que tiene que decir».
///
/// - **largo**: unos 4.000 caracteres —unas 700 palabras—;
/// - **vínculos**: con al menos 5 elementos;
/// - **edad**: un mes desde que nació: madurar lleva tiempo.
const kMatureMinChars = 4000;
const kMatureMinConnections = 5;
const kMatureMinAge = Duration(days: 30);

/// La madurez que se le propone a una nota viva que está en [current], con
/// [textLength] caracteres de texto, [connections] vínculos y [age] de vida:
/// el nivel siguiente si cumple los tres umbrales, o `null`. Nunca salta un
/// nivel: de semilla a madura se pasa por en desarrollo, y es la persona la
/// que acepta cada paso.
NoteMaturity? grownMaturity({
  required NoteMaturity current,
  required int textLength,
  required int connections,
  required Duration age,
}) => switch (current) {
  NoteMaturity.seed
      when textLength >= kDevelopingMinChars &&
          connections >= kDevelopingMinConnections &&
          age >= kDevelopingMinAge =>
    NoteMaturity.developing,
  NoteMaturity.developing
      when textLength >= kMatureMinChars &&
          connections >= kMatureMinConnections &&
          age >= kMatureMinAge =>
    NoteMaturity.mature,
  _ => null,
};
