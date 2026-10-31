import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/services/creation_passage.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';

/// Lo más que puede decir un tramo de enlace —un saludo, una pregunta, una
/// transición— sin cita: algo más largo ya dice algo, y lo que dice tiene que
/// salir del material.
const kPodcastMaxLinkWords = 30;

/// Lo menos que tiene una cita, en palabras: menos que esto está en cualquier
/// texto y no prueba nada. Una cita más corta vale si es larga en letras
/// ([kPodcastMinQuoteChars]): un nombre propio largo, un término técnico.
const kPodcastMinQuoteWords = 4;
const kPodcastMinQuoteChars = 24;

/// Hasta cuánto de un tramo quitado se guarda, para mostrarlo.
const kPodcastDiscardChars = 280;

/// Hasta cuánto de una cita se guarda.
const kPodcastQuoteChars = 400;

/// Un tramo tal como lo escribió la IA, antes de comprobarlo.
@immutable
class PodcastDraftSegment {
  const PodcastDraftSegment({
    required this.speaker,
    required this.text,
    this.kind,
    this.quotes = const [],
    this.longPause = false,
  });

  /// Quién habla, como lo dijo la IA: «A», «B», «host», un nombre…
  final String speaker;
  final String text;

  /// Lo que la IA dijo que es; `null` si no lo dijo (se trata como dato).
  final PodcastSegmentKind? kind;
  final List<PodcastDraftQuote> quotes;

  /// Si la IA pidió una pausa larga después.
  final bool longPause;
}

/// Una cita tal como la escribió la IA: las palabras y, si lo dijo, de qué
/// documento.
@immutable
class PodcastDraftQuote {
  const PodcastDraftQuote(this.quote, {this.source});

  final String quote;
  final String? source;
}

/// Lo que quedó al comprobar: los tramos que se sostienen, con sus citas
/// comprobadas, y los que se quitaron, con por qué.
@immutable
class PodcastCheck {
  const PodcastCheck({required this.segments, required this.discarded});

  final List<PodcastSegment> segments;
  final List<PodcastDiscard> discarded;

  /// Cuántas palabras se dicen en lo que quedó.
  int get words => segments.fold(0, (sum, s) => sum + s.words);

  /// Quiénes hablan en lo que quedó.
  Set<PodcastSpeaker> get speakers => {for (final s in segments) s.speaker};
}

/// Comprueba un guion contra el material que leyó la IA (F47, punto 5 del
/// plan: «solo con lo del material, con la cita de cada dato»), como F43
/// comprueba lo que escribe la IA: se queda con lo que se sostiene y quita lo
/// que no, en vez de confiar.
///
/// Por cada tramo:
///
/// - **Cada cita tiene que estar entera en el material** ([PassageIndex]):
///   sin mayúsculas, tildes ni signos, pero con todas sus palabras. Una cita
///   de menos de [kPodcastMinQuoteWords] palabras no prueba nada y no cuenta.
///   La que está sabe de qué documento es: el del tramo del material donde
///   aparece.
/// - **Un tramo que dice algo lleva al menos una cita que esté.** Sin
///   ninguna, se quita ([PodcastDiscardReason.noCitation]); con citas que no
///   están, también ([PodcastDiscardReason.quoteNotInMaterial]). Las citas
///   que no están se descartan aunque el tramo tenga otra buena.
/// - **Un enlace** —un saludo, una pregunta, una transición— no necesita
///   cita, si es corto ([kPodcastMaxLinkWords]) y no dice ninguna cifra: uno
///   más largo, o con cifras, se trata como dato.
/// - **Toda cifra del tramo tiene que estar en el material**: una fecha, una
///   cantidad, un porcentaje que no aparece en el texto es lo que más se
///   inventa. Si no está, se quita
///   ([PodcastDiscardReason.numberNotInMaterial]).
/// - **Quién habla**: en los formatos de una voz, todo lo dice la A; en la
///   conversación, cada tramo es de la A o de la B (`speakerOf`).
/// - **Los silencios**: un respiro si sigue la misma voz, una pausa si cambia
///   o si la IA pidió una larga (`podcastPauseAfter`).
class PodcastChecker {
  PodcastChecker(List<CreationMaterialReading> readings, {required this.format})
    : _readings = [
        for (final reading in readings)
          (reading: reading, index: PassageIndex(reading.text)),
      ],
      _numbers = {
        for (final reading in readings) ...podcastNumbersIn(reading.text),
      };

  final PodcastFormat format;
  final List<({CreationMaterialReading reading, PassageIndex index})> _readings;
  final Set<String> _numbers;

  /// Comprueba [drafts], en orden.
  PodcastCheck check(List<PodcastDraftSegment> drafts) {
    final speakers = _SpeakerMap(format);
    final kept = <(PodcastSegment, bool)>[];
    final discarded = <PodcastDiscard>[];
    for (final draft in drafts) {
      final text = draft.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      final citations = <PodcastCitation>[];
      for (final quote in draft.quotes) {
        final citation = _cite(quote);
        if (citation != null && !citations.contains(citation)) {
          citations.add(citation);
        }
      }
      final numbers = podcastNumbersIn(text);
      final link =
          draft.kind == PodcastSegmentKind.link &&
          countPodcastWords(text) <= kPodcastMaxLinkWords &&
          numbers.isEmpty;
      final reason = link
          ? null
          : citations.isEmpty
          ? (draft.quotes.any((q) => q.quote.trim().isNotEmpty)
                ? PodcastDiscardReason.quoteNotInMaterial
                : PodcastDiscardReason.noCitation)
          : numbers.every(_numbers.contains)
          ? null
          : PodcastDiscardReason.numberNotInMaterial;
      if (reason != null) {
        discarded.add(
          PodcastDiscard(
            reason: reason,
            text: _clip(text, kPodcastDiscardChars),
          ),
        );
        continue;
      }
      kept.add((
        PodcastSegment(
          speaker: speakers.of(draft.speaker),
          text: text,
          kind: link ? PodcastSegmentKind.link : PodcastSegmentKind.data,
          citations: List.unmodifiable(citations),
        ),
        draft.longPause,
      ));
    }
    return PodcastCheck(
      segments: [
        for (final (i, (segment, long)) in kept.indexed)
          _withPause(
            segment,
            next: i + 1 < kept.length ? kept[i + 1].$1.speaker : null,
            long: long,
          ),
      ],
      discarded: discarded,
    );
  }

  /// La cita de [draft] si está entera en el material, con el documento en
  /// que está; `null` si no está o es muy corta para probar algo. Si la IA
  /// nombró el documento, se busca primero ahí.
  PodcastCitation? _cite(PodcastDraftQuote draft) {
    final quote = draft.quote.replaceAll(RegExp(r'\s+'), ' ').trim();
    final bare = quote.replaceAll(RegExp(r'^[«"“‘\x27]+|[»"”’\x27]+$'), '');
    if (countPodcastWords(bare) < kPodcastMinQuoteWords &&
        bare.length < kPodcastMinQuoteChars) {
      return null;
    }
    final named = _foldTitle(draft.source);
    final ordered = [
      ..._readings.where((r) => _isNamed(r.reading, named)),
      ..._readings.where((r) => !_isNamed(r.reading, named)),
    ];
    for (final (:reading, :index) in ordered) {
      if (!index.containsWhole(bare)) continue;
      return PodcastCitation(
        quote: _clip(bare, kPodcastQuoteChars),
        documentId: reading.documentId,
        documentTitle: reading.title,
      );
    }
    return null;
  }

  static bool _isNamed(CreationMaterialReading reading, String? named) =>
      named != null && named.isNotEmpty && _foldTitle(reading.title) == named;
}

/// [segment] con el silencio que le toca antes de [next].
PodcastSegment _withPause(
  PodcastSegment segment, {
  required PodcastSpeaker? next,
  required bool long,
}) => PodcastSegment(
  speaker: segment.speaker,
  text: segment.text,
  kind: segment.kind,
  citations: segment.citations,
  // El último de una vuelta guarda su pausa larga si la pidió: al unir las
  // vueltas, la que no la pidió recibe la de su siguiente (`joinPodcast`).
  pauseAfter: next == null
      ? (long ? kPodcastLongPause : Duration.zero)
      : podcastPauseAfter(segment.speaker, next: next, long: long),
);

/// Une los tramos de las vueltas de un guion largo, en orden, y le da al
/// último de cada vuelta la pausa que le toca antes del primero de la que
/// sigue.
List<PodcastSegment> joinPodcastRounds(List<List<PodcastSegment>> rounds) {
  final all = [for (final round in rounds) ...round];
  return [
    for (final (i, segment) in all.indexed)
      if (i + 1 < all.length && segment.pauseAfter == Duration.zero)
        _withPause(segment, next: all[i + 1].speaker, long: false)
      else
        segment,
  ];
}

/// Las cifras de [text], con los separadores de miles y decimales quitados
/// —«1.200», «1,200» y «1200» son la misma—: lo que se compara entre un tramo
/// y el material.
Set<String> podcastNumbersIn(String text) => {
  for (final match in _number.allMatches(text))
    match.group(0)!.replaceAll(_separators, ''),
};

/// Una cifra: dígitos, con puntos, comas o espacios que no cortan (U+00A0,
/// U+202F) entre ellos.
final _number = RegExp(r'\d(?:[\d.,\u00A0\u202F]*\d)?');
final _separators = RegExp(r'[.,\u00A0\u202F]');

/// Quién habla en cada tramo, como lo dijo la IA, llevado a la A o la B.
class _SpeakerMap {
  _SpeakerMap(this.format);

  final PodcastFormat format;
  final _byName = <String, PodcastSpeaker>{};

  PodcastSpeaker of(String raw) {
    if (format.speakerCount == 1) return PodcastSpeaker.a;
    final name = _foldTitle(raw) ?? '';
    final known = _known[name.replaceAll(RegExp('[^a-z0-9]'), '')];
    if (known != null) return known;
    // Un nombre que no se conoce («Lucía», «Narrador»): el primero es la A, el
    // segundo la B, y los que sigan, la B.
    return _byName.putIfAbsent(
      name,
      () => _byName.values.contains(PodcastSpeaker.a)
          ? PodcastSpeaker.b
          : PodcastSpeaker.a,
    );
  }

  static const _known = <String, PodcastSpeaker>{
    'a': PodcastSpeaker.a,
    '1': PodcastSpeaker.a,
    'voza': PodcastSpeaker.a,
    'voz1': PodcastSpeaker.a,
    'speakera': PodcastSpeaker.a,
    'speaker1': PodcastSpeaker.a,
    'host': PodcastSpeaker.a,
    'anfitrion': PodcastSpeaker.a,
    'anfitriona': PodcastSpeaker.a,
    'conductor': PodcastSpeaker.a,
    'conductora': PodcastSpeaker.a,
    'presentador': PodcastSpeaker.a,
    'presentadora': PodcastSpeaker.a,
    'b': PodcastSpeaker.b,
    '2': PodcastSpeaker.b,
    'vozb': PodcastSpeaker.b,
    'voz2': PodcastSpeaker.b,
    'speakerb': PodcastSpeaker.b,
    'speaker2': PodcastSpeaker.b,
    'guest': PodcastSpeaker.b,
    'invitado': PodcastSpeaker.b,
    'invitada': PodcastSpeaker.b,
    'experto': PodcastSpeaker.b,
    'experta': PodcastSpeaker.b,
    'cohost': PodcastSpeaker.b,
  };
}

/// [title] para comparar: sin mayúsculas, sin tildes y con los espacios de a
/// uno; `null` si no hay.
String? _foldTitle(String? title) {
  if (title == null) return null;
  return title
      .toLowerCase()
      .replaceAll(RegExp('[áàâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp('[«»"“”‘’\']'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _clip(String text, int max) {
  if (text.length <= max) return text;
  final cut = text.substring(0, max - 1);
  final space = cut.lastIndexOf(' ');
  return '${space > max * 0.6 ? cut.substring(0, space) : cut}…';
}
