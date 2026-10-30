import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_filter.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

/// Una voz creada (paso 4), para los rasgos que el catálogo no dice.
const _created = VoiceProfile(
  id: 'creada:1',
  voice: NarrationVoice(name: 'creada:1', locale: 'es-AR'),
  origin: VoiceOrigin.created,
  locale: 'es-AR',
  name: 'Relator',
  gender: VoiceGender.male,
  purposes: {VoicePurpose.narrate},
  timbre: VoiceTimbre.deep,
  styles: {VoiceStyle.energetic},
  age: VoiceAge.young,
);

void main() {
  final offline = offlineVoiceProfiles(OfflineVoiceCatalog.voices);
  final device = deviceVoiceProfiles(const [
    NarrationVoice(name: 'es-us-x-esd-network', locale: 'es-US'),
    NarrationVoice(name: 'es-us-x-esd-local', locale: 'es_US'),
    NarrationVoice(name: 'Mónica', locale: 'es-ES'),
  ]);
  final all = [...device, ...offline, _created];

  List<String> ids(List<VoiceProfile> voices) =>
      voices.map((v) => v.id).toList();

  group('las voces del teléfono (F47, paso 3)', () {
    test('las de código se numeran por acento, primero las sin conexión', () {
      expect(device[0].number, 1);
      expect(device[0].voice.name, 'es-us-x-esd-local');
      expect(device[0].needsInternet, isFalse);
      expect(device[1].number, 2);
      expect(device[1].needsInternet, isTrue);
      expect(device[2].name, 'Mónica');
      expect(device.map((v) => v.locale), ['es-US', 'es-US', 'es-ES']);
      expect(device.every((v) => v.origin == VoiceOrigin.device), isTrue);
    });
  });

  group('Filtrar (F47, paso 3)', () {
    test('sin nada elegido, pasan todas', () {
      const filter = VoiceFilter();
      expect(filter.isEmpty, isTrue);
      expect(
        voicesIn(
          all,
          tab: VoiceLibraryTab.all,
          filter: filter,
          favorites: const {},
        ),
        hasLength(all.length),
      );
    });

    test('dentro de un rasgo, cualquiera; entre rasgos, todos', () {
      final filter = const VoiceFilter()
          .toggleLanguage('es')
          .toggleAccent('es-MX')
          .toggleAccent('es-AR');
      final shown = voicesIn(
        all,
        tab: VoiceLibraryTab.all,
        filter: filter,
        favorites: const {},
      );
      expect(filter.count, 3);
      expect(shown.map((v) => v.locale).toSet(), {'es-MX', 'es-AR'});
      expect(ids(shown), contains('vits-piper-es_AR-daniela-high#0'));
      expect(ids(shown), contains('creada:1'));

      final women = filter.toggleGender(VoiceGender.female);
      // Daniela no dice su género: no pasa «mujer».
      expect(
        voicesIn(
          all,
          tab: VoiceLibraryTab.all,
          filter: women,
          favorites: const {},
        ),
        isEmpty,
      );
    });

    test('sacar un idioma saca sus acentos', () {
      final filter = const VoiceFilter()
          .toggleLanguage('es')
          .toggleAccent('es-AR')
          .toggleLanguage('en')
          .toggleAccent('en-GB')
          .toggleLanguage('es');
      expect(filter.languages, {'en'});
      expect(filter.accents, {'en-GB'});
    });

    test('los rasgos que dice una voz creada se filtran', () {
      for (final filter in [
        const VoiceFilter().togglePurpose(VoicePurpose.narrate),
        const VoiceFilter().toggleTimbre(VoiceTimbre.deep),
        const VoiceFilter().toggleStyle(VoiceStyle.energetic),
        const VoiceFilter().toggleAge(VoiceAge.young),
      ]) {
        expect(
          ids(
            voicesIn(
              all,
              tab: VoiceLibraryTab.all,
              filter: filter,
              favorites: const {},
            ),
          ),
          ['creada:1'],
        );
      }
    });

    test('Favoritas y Mías', () {
      const favorites = {'vits-piper-es_AR-daniela-high#0'};
      expect(
        ids(
          voicesIn(
            all,
            tab: VoiceLibraryTab.favorites,
            filter: const VoiceFilter(),
            favorites: favorites,
          ),
        ),
        favorites.toList(),
      );
      expect(
        ids(
          voicesIn(
            all,
            tab: VoiceLibraryTab.mine,
            filter: const VoiceFilter(),
            favorites: favorites,
          ),
        ),
        ['creada:1'],
      );
    });

    test('solo se ofrece lo que alguna voz dice, y lo elegido se sigue '
        'viendo', () {
      final catalogOnly = VoiceFilterOptions.of(offline, const VoiceFilter());
      expect(catalogOnly.timbres, isEmpty);
      expect(catalogOnly.purposes, isEmpty);
      expect(catalogOnly.genders, VoiceGender.values);
      expect(catalogOnly.languages, containsAll(['es', 'en', 'pt', 'fr']));
      // Los acentos, solo los que dicen de dónde son: el «es» de Kokoro no.
      expect(catalogOnly.accents, isNot(contains('es')));
      expect(catalogOnly.accents, containsAll(['es-AR', 'es-ES', 'es-MX']));

      final spanish = VoiceFilterOptions.of(
        offline,
        const VoiceFilter().toggleLanguage('es'),
      );
      expect(spanish.accents, ['es-AR', 'es-ES', 'es-MX']);

      final stale = VoiceFilterOptions.of(
        offline,
        const VoiceFilter().toggleTimbre(VoiceTimbre.clear),
      );
      expect(stale.timbres, [VoiceTimbre.clear]);
    });
  });

  group('«Te puede interesar» (F47, paso 3)', () {
    test('las del idioma de lo que se lee, con buena calidad: primero las '
        'altas, y en cada una las que ya están', () {
      final recommended = recommendedVoices(
        all,
        language: 'es',
        installed: const {'vits-piper-es_ES-davefx-medium#0'},
      );
      expect(ids(recommended), [
        'vits-piper-es_MX-claude-high#0',
        'vits-piper-es_AR-daniela-high#0',
        'vits-piper-es_ES-davefx-medium#0',
      ]);
      expect(recommended.every((v) => v.quality?.isGood ?? false), isTrue);
    });

    test('sin idioma conocido, ninguna', () {
      expect(
        recommendedVoices(all, language: null, installed: const {}),
        isEmpty,
      );
    });
  });
}
