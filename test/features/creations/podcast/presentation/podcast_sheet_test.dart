import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/podcast_kind.dart';
import 'package:sinapsis/features/creations/podcast/presentation/podcast_entry.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/narration/data/voices/offline_voice_files.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/speech_audio_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/on_device_harness.dart';
import '../../../narration/data/audio/speech_audio_fakes.dart';
import '../../presentation/repasar_harness.dart';

/// F47, paso 6: la tarjeta «Podcast» de Repasar y su hoja —el formato, el
/// idioma, la duración, «¿De qué trata?» con sus propuestas, su enfoque
/// propio y «+», y «Elegí las voces»—, en la app de verdad con su router, a
/// 360 dp con la letra al doble, en claro y en oscuro, con el lector de
/// pantalla.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;

  const voices = [
    NarrationVoice(name: 'es-ar-x-esd-local', locale: 'es-AR'),
    NarrationVoice(name: 'es-es-x-eed-local', locale: 'es-ES'),
    NarrationVoice(name: 'es-es-x-eee-network', locale: 'es-ES'),
    NarrationVoice(name: 'en-us-x-iol-local', locale: 'en-US'),
  ];
  const sofia = 'device:es-AR:es-ar-x-esd-local';
  const jorge = 'device:es-ES:es-es-x-eed-local';

  /// Quienes hacen las voces, de mentira: las del teléfono y, en el grupo
  /// de las sin conexión, las de la biblioteca.
  late FakeVoiceRenderer device;
  late FakeVoiceRenderer offline;

  Future<void> create({List<Override> extra = const []}) async {
    device = FakeVoiceRenderer(prefix: 'device:');
    offline = FakeVoiceRenderer(prefix: 'offline:');
    harness = await RepasarHarness.create(
      specs: [podcastKindSpec()],
      suggestedTopics: const ['Moisés y Faraón', 'Alianza', 'Plagas', 'Sinaí'],
      overrides: [
        narrationVoicesProvider.overrideWith((ref) async => voices),
        speechVoiceRenderersProvider.overrideWith(
          (ref) => [
            device,
            if (ref.watch(offlineVoicesAvailableProvider)) offline,
          ],
        ),
        ...extra,
      ],
    );
    await harness.processed('p-1', 'Éxodo — Comentario');
    await harness.processed('p-2', 'Génesis');
  }

  setUp(create);

  final tile = find.byKey(const ValueKey('creation-kind-podcast'));

  Future<void> openSheet(
    WidgetTester tester, {
    Size size = const Size(420, 1600),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) async {
    await harness.openRepasar(
      tester,
      size: size,
      theme: theme,
      textScale: textScale,
    );
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('review-entry')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Map<String, Object?> lastOptions() => harness.queue.requests.last.options;

  testWidgets('la tarjeta «Podcast» está en la grilla de crear, al lado de '
      'Tabla de datos, y abre su hoja', (tester) async {
    await harness.openRepasar(tester);

    expect(tile, findsOneWidget);
    expect(find.text(es.f47P6KindPodcast), findsOneWidget);
    double top(StudyCreationKind kind) => tester
        .getTopLeft(find.byKey(ValueKey('creation-kind-${kind.storageKey}')))
        .dy;
    expect(top(StudyCreationKind.podcast), top(StudyCreationKind.dataTable));

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text(es.f47P6SheetTitle), findsOneWidget);
  });

  testWidgets('la hoja trae el formato, el idioma, la duración, «¿De qué '
      'trata?» con tres propuestas y las voces', (tester) async {
    await openSheet(tester);

    for (final label in [
      es.f43StudioLanguage,
      es.f43StudioOptFormat,
      es.f47P6FormatBrief,
      es.f47P6FormatLesson,
      es.f47P6FormatStory,
      es.f47P6FormatConversation,
      es.f43StudioOptDuration,
      es.f47P6LengthShort,
      es.f47P6LengthMedium,
      es.f47P6LengthLong,
      es.f47P6About,
      es.f47P6Proposals,
      es.f47P6AddSource,
      es.f47P6Voices,
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    // Tres propuestas del material, no más.
    expect(find.text('Moisés y Faraón'), findsOneWidget);
    expect(find.text('Alianza'), findsOneWidget);
    expect(find.text('Plagas'), findsOneWidget);
    expect(find.text('Sinaí'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('creation-topic')))
          .decoration
          ?.hintText,
      es.f47P6AboutHint,
    );
  });

  testWidgets('en Conversación, dos voces distintas del idioma, sin las que '
      'leen por internet; en Breve, una', (tester) async {
    await openSheet(tester);

    expect(find.byKey(const ValueKey('podcast-voice-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('podcast-voice-b')), findsOneWidget);
    expect(find.text(es.f47P6VoiceHost), findsOneWidget);
    expect(find.text(es.f47P6VoiceExpert), findsOneWidget);
    // Se eligieron solas: una para cada persona, distintas.
    expect(find.text('Voz 1 · Español (Argentina)'), findsOneWidget);
    expect(find.text('Voz 2 · Español (España)'), findsOneWidget);

    await tapInSheet(tester, find.byKey(const ValueKey('podcast-voice-a')));
    // Las del idioma, sin la que lee por internet ni la inglesa.
    expect(
      find.byKey(const ValueKey('podcast-voice-option-$jorge')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('podcast-voice-option-device:es-ES:es-es-x-eee-network'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('podcast-voice-option-device:en-US:en-us-x-iol-local'),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('podcast-voice-option-$jorge')));
    await tester.pumpAndSettle();
    // Las dos con la misma voz: se avisa.
    expect(find.text(es.f47P6VoicesSame), findsOneWidget);

    await tapInSheet(
      tester,
      find.byKey(const ValueKey('creation-option-format-brief')),
    );
    expect(find.byKey(const ValueKey('podcast-voice-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('podcast-voice-b')), findsNothing);
    expect(find.text(es.f47P6Voice), findsOneWidget);
    expect(find.text(es.f47P6VoicesSame), findsNothing);
  });

  testWidgets('la voz sigue al idioma del podcast', (tester) async {
    await openSheet(tester);

    await tapInSheet(tester, find.byKey(const Key('creation-language')));
    await tester.tap(find.byKey(const ValueKey('picker-item-en')).last);
    await tester.pumpAndSettle();

    expect(find.text('Voz 1 · English (United States)'), findsNWidgets(2));
    // Es la única del idioma: las dos la comparten, y se dice sin alarma.
    expect(find.text(es.f47P6VoicesSame), findsNothing);
    expect(find.text(es.f47P6VoicesOnlyOne), findsOneWidget);

    await tapInSheet(tester, find.byKey(const Key('creation-language')));
    await tester.tap(find.byKey(const ValueKey('picker-item-pt')).last);
    await tester.pumpAndSettle();
    expect(find.text(es.f47P6VoicesNone), findsOneWidget);
    expect(find.text(es.f47P6VoiceDefault), findsNWidgets(2));
  });

  testWidgets('«Generar ahora» pide el podcast a la cola con lo elegido, y '
      'las voces como dato', (tester) async {
    await openSheet(tester);

    await tapInSheet(
      tester,
      find.byKey(const ValueKey('creation-option-length-long')),
    );
    await tapInSheet(
      tester,
      find.byKey(const ValueKey('creation-suggested-Alianza')),
    );
    await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));

    final request = harness.queue.requests.single;
    expect(request.kind, StudyCreationKind.podcast);
    expect(request.sourceIds.toSet(), {'p-1', 'p-2'});
    expect(lastOptions()['format'], PodcastFormat.conversation.storageKey);
    expect(lastOptions()['length'], PodcastLength.long.storageKey);
    expect(lastOptions()['topic'], 'Alianza');
    expect(lastOptions()['voices'], [
      {'speaker': 'a', 'voiceId': sofia},
      {'speaker': 'b', 'voiceId': jorge},
    ]);
    expect(find.text(es.f43StudioQueuedSnack), findsOneWidget);
  });

  testWidgets('el enfoque propio va con el pedido', (tester) async {
    await openSheet(tester);

    await tester.enterText(
      find.byKey(const Key('creation-topic')),
      'Cómo cambia Moisés',
    );
    await tapInSheet(tester, find.byKey(const Key('creation-generate-later')));

    expect(lastOptions()['topic'], 'Cómo cambia Moisés');
    expect(harness.queue.requests.single.runNow, isFalse);
  });

  testWidgets('«+ Sumar otro documento» suma uno que no está en el recorte', (
    tester,
  ) async {
    harness.container.read(repasarScopeProvider.notifier).state =
        const CreationScope.document('p-1');
    await openSheet(tester);
    expect(find.text(es.f43StudioSources(1)), findsOneWidget);

    await tapInSheet(tester, find.byKey(const Key('creation-sources-add')));
    expect(find.byKey(const Key('creation-scope-picker')), findsOneWidget);
    await tapInSheet(
      tester,
      find.byKey(const ValueKey('creation-scope-option-document:p-2')),
    );

    expect(find.byKey(const Key('creation-scope-picker')), findsNothing);
    expect(find.text(es.f43StudioSources(2)), findsOneWidget);
    // Se ve en la lista, y destildarlo lo saca.
    expect(
      find.byKey(const ValueKey('creation-source-option-p-2')),
      findsOneWidget,
    );

    await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
    final request = harness.queue.requests.single;
    expect(request.sourceIds, ['p-1', 'p-2']);
    // El recorte sigue siendo el documento: lo sumado es de esta creación.
    expect(request.scope, const CreationScope.document('p-1'));
  });

  testWidgets('destildar lo sumado lo saca', (tester) async {
    harness.container.read(repasarScopeProvider.notifier).state =
        const CreationScope.document('p-1');
    await openSheet(tester);
    await tapInSheet(tester, find.byKey(const Key('creation-sources-add')));
    await tapInSheet(
      tester,
      find.byKey(const ValueKey('creation-scope-option-document:p-2')),
    );

    await tapInSheet(
      tester,
      find.byKey(const ValueKey('creation-source-option-p-2')),
    );

    expect(find.text(es.f43StudioSources(1)), findsOneWidget);
    await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
    expect(harness.queue.requests.single.sourceIds, ['p-1']);
  });

  testWidgets('startPodcast, el punto de entrada del marco de lectura, abre '
      'la misma hoja sobre el documento', (tester) async {
    await harness.openRepasar(tester);
    final context = tester.element(find.byKey(const Key('review-entry')));

    final opened = startPodcast(context, const CreationScope.document('p-2'));
    await tester.pumpAndSettle();
    expect(find.text(es.f47P6SheetTitle), findsOneWidget);

    await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
    await opened;
    final request = harness.queue.requests.single;
    expect(request.kind, StudyCreationKind.podcast);
    expect(request.scope, const CreationScope.document('p-2'));
    expect(request.sourceIds, ['p-2']);
  });

  group('las voces de la biblioteca (F47, paso 6b)', () {
    final daniela = OfflineVoiceCatalog.voices.firstWhere(
      (v) => v.locale == 'es-AR',
    );
    final mexico = OfflineVoiceCatalog.voices.firstWhere(
      (v) => v.locale == 'es-MX',
    );
    final danielaId = SpeechVoiceIds.offline(daniela.id);
    final mexicoId = SpeechVoiceIds.offline(mexico.id);
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('voces');
      addTearDown(() => root.deleteSync(recursive: true));
      await create(
        extra: [
          offlineVoicesAvailableProvider.overrideWithValue(true),
          offlineVoiceFilesProvider.overrideWithValue(
            OfflineVoiceFiles(
              transfer: FakeModelTransfer(),
              rootDirectory: () async => root,
            ),
          ),
          offlineSpeechSynthesizerProvider.overrideWithValue(null),
          installedVoicePackagesProvider.overrideWith(
            (ref) => Stream.value({daniela.package.id}),
          ),
        ],
      );
      for (final voice in OfflineVoiceCatalog.voices) {
        if (voice.package != daniela.package) {
          offline.missing.add(SpeechVoiceIds.offline(voice.id));
        }
      }
    });

    testWidgets('primero la sin conexión bajada, después las del teléfono, y '
        'las que falta bajar, con su tamaño; las de otro idioma, no', (
      tester,
    ) async {
      await openSheet(tester);

      // Se eligieron solas, de las que ya pueden generar: Daniela y una del
      // teléfono.
      expect(find.text('${daniela.name} · Español (Argentina)'), findsWidgets);
      await tapInSheet(tester, find.byKey(const ValueKey('podcast-voice-a')));
      expect(
        find.byKey(ValueKey('podcast-voice-option-$danielaId')),
        findsOneWidget,
      );
      final toDownload = find.byKey(ValueKey('podcast-voice-option-$mexicoId'));
      expect(toDownload, findsOneWidget);
      expect(
        find.descendant(
          of: toDownload,
          matching: find.textContaining(
            es.f47P6bToDownload('').replaceAll('()', '').trim(),
          ),
        ),
        findsOneWidget,
      );
      final english = OfflineVoiceCatalog.voices.firstWhere(
        (v) => v.language == 'en',
      );
      expect(
        find.byKey(
          ValueKey(
            'podcast-voice-option-${SpeechVoiceIds.offline(english.id)}',
          ),
        ),
        findsNothing,
      );

      // Elegir una que falta bajar la deja, y ofrece bajarla ahí mismo.
      await tester.tap(toDownload);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('podcast-voice-download-a')),
        findsOneWidget,
      );
      expect(find.text(es.f47P6bVoiceToDownload(mexico.name)), findsOneWidget);
      expect(find.byKey(Key('voice-download-${mexico.id}')), findsOneWidget);

      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
      expect(lastOptions()['voices'], [
        // La otra persona sigue con la que tenía: la del teléfono que se le
        // dio al abrir, porque Daniela era de la primera.
        {'speaker': 'a', 'voiceId': mexicoId},
        {'speaker': 'b', 'voiceId': sofia},
      ]);
    });

    testWidgets('con una voz que cobra (el enganche del paso 4), antes de '
        'pedirlo se dice el costo; sin aceptar, no se pide nada', (
      tester,
    ) async {
      offline.prices[danielaId] = const SpeechAudioPrice(
        per1000Characters: 0.3,
        currency: 'USD',
      );
      await openSheet(tester);

      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
      expect(find.byKey(const Key('speech-audio-cost')), findsOneWidget);
      expect(find.text(es.f47P6bCostTitle), findsOneWidget);
      // Medio: 8 min a 150 palabras, de a 6 caracteres, la mitad para cada
      // voz.
      expect(find.textContaining('${8 * 150 * 6 ~/ 2}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('speech-audio-cost-cancel')));
      await tester.pumpAndSettle();
      expect(harness.queue.requests, isEmpty);

      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
      await tester.tap(find.byKey(const Key('speech-audio-cost-go')));
      await tester.pumpAndSettle();
      expect(harness.queue.requests, hasLength(1));
    });

    testWidgets('con voces gratis, no se pregunta nada', (tester) async {
      await openSheet(tester);
      await tapInSheet(tester, find.byKey(const Key('creation-generate-now')));
      expect(find.byKey(const Key('speech-audio-cost')), findsNothing);
      expect(harness.queue.requests, hasLength(1));
    });
  });

  testWidgets('donde nadie sabe hacer las voces, se dice que el audio no se '
      'genera ahí', (tester) async {
    await create(
      extra: [speechVoiceRenderersProvider.overrideWith((ref) => const [])],
    );
    await openSheet(tester);
    expect(find.text(es.f47P6bNoAudioHere), findsOneWidget);
  });

  for (final theme in [AppThemeChoice.light, AppThemeChoice.dark]) {
    testWidgets('a 360 dp con la letra al doble, en ${theme.name}, entra '
        'entera y se lee con el lector de pantalla', (tester) async {
      final handle = tester.ensureSemantics();
      await openSheet(
        tester,
        size: const Size(360, 780),
        theme: theme,
        textScale: 2,
      );

      final voicesSection = find.byKey(const Key('podcast-voices'));
      await tester.ensureVisible(voicesSection);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(voicesSection, findsOneWidget);
      // Cada voz dice de quién es y cuál quedó.
      expect(
        find.bySemanticsLabel(
          RegExp('${es.f47P6VoiceHost}: Voz 1 · Español \\(Argentina\\)'),
        ),
        findsOneWidget,
      );
      // Las cuatro opciones del formato, sin cortarse.
      for (final format in PodcastFormat.values) {
        final option = find.byKey(
          ValueKey('creation-option-format-${format.storageKey}'),
        );
        await tester.ensureVisible(option);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(option).right,
          lessThanOrEqualTo(360),
          reason: format.name,
        );
      }
      handle.dispose();
    });
  }
}
