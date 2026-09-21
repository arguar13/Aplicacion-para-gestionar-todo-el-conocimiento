import 'dart:math' as math;

import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';

/// Una propuesta de jerarquía (F13): [child] parece un subtema de [parent].
///
/// Es solo una PROPUESTA: la pantalla la ofrece y quien maneja el vocabulario
/// decide. Nada se mueve sin una confirmación.
class HierarchySuggestion {
  const HierarchySuggestion({required this.child, required this.parent});

  final VocabularyValueStat child;
  final VocabularyValueStat parent;
}

/// Las propuestas de jerarquía de un grupo de candidatos: para cada par en que
/// un valor es el otro con más palabras —«Roma» y «Roma republicana»—, el más
/// largo parece un subtema del más corto.
///
/// Son los mismos pares que F8 ofrece FUSIONAR: para «Roma» y «Roma antigua» a
/// veces la respuesta es que son lo mismo, y muchas otras que uno es un caso
/// del otro. Acá se ofrece lo segundo. Por palabras enteras, igual que la
/// detección: «Arte» no es el padre de «Artesanía».
///
/// Un valor tiene UN padre, así que si lo contienen varios se propone el más
/// específico —el de más palabras—: «Roma republicana tardía» va bajo «Roma
/// republicana», que a su vez irá bajo «Roma»; proponerlo también bajo «Roma»
/// solo sería ruido.
///
/// No se propone lo que no aporta o lo que sería pisar una decisión: un valor
/// que YA tiene padre no se ofrece mover —alguien lo puso ahí—, y tampoco se
/// ofrece poner un valor bajo uno que ya es hijo suyo. Lo que las palabras no
/// ven —un ciclo más lejos, pasar de cinco niveles— lo dice la vista previa de
/// mover, antes de confirmar.
List<HierarchySuggestion> hierarchySuggestionsFor(MergeCandidateGroup group) {
  final children = <String, VocabularyValueStat>{};
  final containers = <String, List<_Container>>{};
  for (final pair in group.pairs) {
    if (pair.reason != MergeCandidateReason.contained) continue;
    final firstWords = _wordCount(pair.first.label);
    final secondWords = _wordCount(pair.second.label);
    if (firstWords == secondWords) continue;
    final firstIsChild = firstWords > secondWords;
    final child = firstIsChild ? pair.first : pair.second;
    final parent = firstIsChild ? pair.second : pair.first;
    if (child.parentId != null || parent.parentId == child.id) continue;
    children[child.id] = child;
    (containers[child.id] ??= []).add((
      parent: parent,
      words: firstIsChild ? secondWords : firstWords,
    ));
  }

  final suggestions = <HierarchySuggestion>[];
  for (final entry in containers.entries) {
    final mostSpecific = entry.value.map((c) => c.words).reduce(math.max);
    // Dos padres que se escriben igual —«Roma» y «Róma»— son el mismo padre
    // repetido, y se ofrecen a fusionar en la misma tarjeta: se propone el más
    // usado, no los dos.
    final byText = <String, VocabularyValueStat>{};
    for (final container in entry.value) {
      if (container.words != mostSpecific) continue;
      final key = normalizeVocabularyLabel(container.parent.label);
      final current = byText[key];
      if (current == null || _moreUsed(container.parent, current)) {
        byText[key] = container.parent;
      }
    }
    for (final parent in byText.values) {
      suggestions.add(
        HierarchySuggestion(child: children[entry.key]!, parent: parent),
      );
    }
  }
  return suggestions;
}

/// Un valor que contiene a otro, con cuántas palabras tiene el que contiene.
typedef _Container = ({VocabularyValueStat parent, int words});

/// El más usado; a igual uso, el de menor id: un orden total.
bool _moreUsed(VocabularyValueStat a, VocabularyValueStat b) =>
    a.usage != b.usage ? a.usage > b.usage : a.id.compareTo(b.id) < 0;

/// Cuántas palabras tiene [label], contadas como las cuenta la detección de
/// candidatos: sobre el texto normalizado, cortando en todo lo que no sea una
/// letra o un número.
int _wordCount(String label) => normalizeVocabularyLabel(label)
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((word) => word.isNotEmpty)
    .length;
