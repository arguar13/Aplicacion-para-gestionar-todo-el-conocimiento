import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_locale.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

/// Las pestañas de la biblioteca de voces (F47, paso 3).
enum VoiceLibraryTab {
  all,
  favorites,

  /// Las clonadas y las creadas (paso 4).
  mine,
}

/// Lo que se eligió en Filtrar de la biblioteca de voces (F47, paso 3).
///
/// Dentro de un mismo rasgo, cualquiera de lo elegido —«México» o «España»—;
/// entre rasgos, todos —español **y** mujer—. Una voz que no dice un rasgo no
/// pasa un filtro de ese rasgo: si se pidió «mujer», una voz de la que no se
/// sabe el género no aparece, porque nadie dijo que lo sea.
@immutable
class VoiceFilter {
  const VoiceFilter({
    this.languages = const {},
    this.accents = const {},
    this.purposes = const {},
    this.timbres = const {},
    this.styles = const {},
    this.genders = const {},
    this.ages = const {},
  });

  /// Idiomas: `es`, `en`.
  final Set<String> languages;

  /// Acentos con su región, normalizados: `es-AR`.
  final Set<String> accents;
  final Set<VoicePurpose> purposes;
  final Set<VoiceTimbre> timbres;
  final Set<VoiceStyle> styles;
  final Set<VoiceGender> genders;
  final Set<VoiceAge> ages;

  /// Cuántas cosas se eligieron: la insignia del botón Filtrar.
  int get count =>
      languages.length +
      accents.length +
      purposes.length +
      timbres.length +
      styles.length +
      genders.length +
      ages.length;

  bool get isEmpty => count == 0;

  bool matches(VoiceProfile voice) =>
      _pass(languages, voice.language) &&
      _pass(accents, voice.locale) &&
      _passAny(purposes, voice.purposes) &&
      _pass(timbres, voice.timbre) &&
      _passAny(styles, voice.styles) &&
      _pass(genders, voice.gender) &&
      _pass(ages, voice.age);

  static bool _pass<T>(Set<T> chosen, T? value) =>
      chosen.isEmpty || (value != null && chosen.contains(value));

  static bool _passAny<T>(Set<T> chosen, Set<T> values) =>
      chosen.isEmpty || values.any(chosen.contains);

  /// El mismo filtro, con [language] puesto o sacado. Sacar un idioma saca
  /// también sus acentos: «México» sin «español» no filtraría nada que se
  /// viera.
  VoiceFilter toggleLanguage(String language) {
    final languages = _toggle(this.languages, language);
    final accents = languages.contains(language)
        ? this.accents
        : {
            for (final accent in this.accents)
              if (accentLanguage(accent) != language) accent,
          };
    return _copy(languages: languages, accents: accents);
  }

  VoiceFilter toggleAccent(String accent) =>
      _copy(accents: _toggle(accents, accent));

  VoiceFilter togglePurpose(VoicePurpose purpose) =>
      _copy(purposes: _toggle(purposes, purpose));

  VoiceFilter toggleTimbre(VoiceTimbre timbre) =>
      _copy(timbres: _toggle(timbres, timbre));

  VoiceFilter toggleStyle(VoiceStyle style) =>
      _copy(styles: _toggle(styles, style));

  VoiceFilter toggleGender(VoiceGender gender) =>
      _copy(genders: _toggle(genders, gender));

  VoiceFilter toggleAge(VoiceAge age) => _copy(ages: _toggle(ages, age));

  static Set<T> _toggle<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  VoiceFilter _copy({
    Set<String>? languages,
    Set<String>? accents,
    Set<VoicePurpose>? purposes,
    Set<VoiceTimbre>? timbres,
    Set<VoiceStyle>? styles,
    Set<VoiceGender>? genders,
    Set<VoiceAge>? ages,
  }) => VoiceFilter(
    languages: languages ?? this.languages,
    accents: accents ?? this.accents,
    purposes: purposes ?? this.purposes,
    timbres: timbres ?? this.timbres,
    styles: styles ?? this.styles,
    genders: genders ?? this.genders,
    ages: ages ?? this.ages,
  );

  @override
  bool operator ==(Object other) =>
      other is VoiceFilter &&
      setEquals(other.languages, languages) &&
      setEquals(other.accents, accents) &&
      setEquals(other.purposes, purposes) &&
      setEquals(other.timbres, timbres) &&
      setEquals(other.styles, styles) &&
      setEquals(other.genders, genders) &&
      setEquals(other.ages, ages);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(languages),
    Object.hashAllUnordered(accents),
    Object.hashAllUnordered(purposes),
    Object.hashAllUnordered(timbres),
    Object.hashAllUnordered(styles),
    Object.hashAllUnordered(genders),
    Object.hashAllUnordered(ages),
  );
}

/// Las voces de [tab] que pasan [filter]: lo que muestra la lista, y cuántas
/// dice el pie de Filtrar («Ver N voces»).
List<VoiceProfile> voicesIn(
  List<VoiceProfile> voices, {
  required VoiceLibraryTab tab,
  required VoiceFilter filter,
  required Set<String> favorites,
}) => [
  for (final voice in voices)
    if (_inTab(voice, tab, favorites) && filter.matches(voice)) voice,
];

bool _inTab(VoiceProfile voice, VoiceLibraryTab tab, Set<String> favorites) =>
    switch (tab) {
      VoiceLibraryTab.all => true,
      VoiceLibraryTab.favorites => favorites.contains(voice.id),
      VoiceLibraryTab.mine =>
        voice.origin == VoiceOrigin.cloned ||
            voice.origin == VoiceOrigin.created,
    };

/// Qué se puede elegir en cada rasgo de Filtrar: solo lo que tiene alguna voz
/// de la lista. Un rasgo que ninguna voz dice —el timbre, mientras no haya
/// voces creadas— no se muestra: un filtro que siempre da cero confunde.
///
/// Los acentos, de los idiomas elegidos en el filtro —o de todos, sin
/// ninguno—, y solo los que dicen de dónde son.
@immutable
class VoiceFilterOptions {
  factory VoiceFilterOptions.of(List<VoiceProfile> voices, VoiceFilter filter) {
    final languages = <String>{};
    final accents = <String>{};
    final purposes = <VoicePurpose>{};
    final timbres = <VoiceTimbre>{};
    final styles = <VoiceStyle>{};
    final genders = <VoiceGender>{};
    final ages = <VoiceAge>{};
    for (final voice in voices) {
      languages.add(voice.language);
      if (accentRegion(voice.locale) != null &&
          (filter.languages.isEmpty ||
              filter.languages.contains(voice.language))) {
        accents.add(voice.locale);
      }
      purposes.addAll(voice.purposes);
      if (voice.timbre case final timbre?) timbres.add(timbre);
      styles.addAll(voice.styles);
      if (voice.gender case final gender?) genders.add(gender);
      if (voice.age case final age?) ages.add(age);
    }
    // Lo elegido se sigue viendo aunque ya no tenga voces —para poder
    // sacarlo—.
    return VoiceFilterOptions._(
      languages: _sorted({...languages, ...filter.languages}),
      accents: _sorted({...accents, ...filter.accents}),
      purposes: _inOrder(VoicePurpose.values, {
        ...purposes,
        ...filter.purposes,
      }),
      timbres: _inOrder(VoiceTimbre.values, {...timbres, ...filter.timbres}),
      styles: _inOrder(VoiceStyle.values, {...styles, ...filter.styles}),
      genders: _inOrder(VoiceGender.values, {...genders, ...filter.genders}),
      ages: _inOrder(VoiceAge.values, {...ages, ...filter.ages}),
    );
  }

  const VoiceFilterOptions._({
    required this.languages,
    required this.accents,
    required this.purposes,
    required this.timbres,
    required this.styles,
    required this.genders,
    required this.ages,
  });

  final List<String> languages;
  final List<String> accents;
  final List<VoicePurpose> purposes;
  final List<VoiceTimbre> timbres;
  final List<VoiceStyle> styles;
  final List<VoiceGender> genders;
  final List<VoiceAge> ages;

  static List<String> _sorted(Set<String> values) => values.toList()..sort();

  static List<T> _inOrder<T>(List<T> order, Set<T> present) => [
    for (final value in order)
      if (present.contains(value)) value,
  ];
}

/// «Te puede interesar» (F47, paso 3): hasta [limit] voces de [language] —el
/// idioma de lo que se lee— con buena calidad, las neuronales primero y, en
/// cada calidad, las que ya están en el teléfono antes que las que hay que
/// bajar. Sin idioma conocido, ninguna: recomendar a ciegas no ayuda.
List<VoiceProfile> recommendedVoices(
  List<VoiceProfile> voices, {
  required String? language,
  required Set<String> installed,
  int limit = 3,
}) {
  if (language == null) return const [];
  final candidates = [
    for (final voice in voices)
      if (voice.language == language && (voice.quality?.isGood ?? false)) voice,
  ];
  int rank(VoiceProfile voice) =>
      (voice.quality == VoiceQuality.high ? 0 : 2) +
      (installed.contains(voice.id) ? 0 : 1);
  candidates.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : a.label.compareTo(b.label);
  });
  return candidates.take(limit).toList();
}
