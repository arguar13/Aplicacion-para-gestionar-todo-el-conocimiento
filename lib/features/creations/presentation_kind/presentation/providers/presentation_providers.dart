import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/repositories/study_creation_repository.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_illustration_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/deck_pager.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/widgets/slide_view.dart';
import 'package:sinapsis/features/creations/presentation_kind/data/deck_illustrator.dart';
import 'package:sinapsis/features/creations/presentation_kind/data/presentation_generator.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';

/// Quien dibuja las ilustraciones de una presentación, en el almacén de las
/// de todos los tipos.
final deckIllustratorProvider = Provider<DeckIllustrator>(
  (ref) => DeckIllustrator(
    service: ref.watch(illustrationServiceProvider),
    files: ref.watch(creationIllustrationStoreProvider),
  ),
);

/// Quien genera las presentaciones: lo que suma la Presentación a
/// `creationGeneratorsProvider`. Lee sus dependencias al usarlas, como la
/// cola.
final presentationGeneratorProvider = Provider<CreationGenerator>(
  (ref) => PresentationGenerator(
    illustrator: () => ref.read(deckIllustratorProvider),
    files: () => ref.read(creationIllustrationStoreProvider),
  ),
);

/// Una ilustración guardada, lista para dibujar; `null` si el archivo ya no
/// está. De a una: rehacer una no vuelve a leer las demás.
final deckIllustrationImageProvider = FutureProvider.autoDispose
    .family<ImageProvider?, String>((ref, path) async {
      final bytes = await ref
          .watch(creationIllustrationStoreProvider)
          .read(path);
      return bytes == null ? null : MemoryImage(bytes);
    });

/// Las ilustraciones de [paths] que ya se leyeron, para dibujar el mazo:
/// mientras una se lee, su diapositiva muestra la de reserva.
SlideIllustrationResolver watchDeckIllustrations(
  WidgetRef ref,
  Set<String> paths,
) {
  final images = <String, ImageProvider>{
    for (final path in paths)
      if (ref.watch(deckIllustrationImageProvider(path)).valueOrNull
          case final image?)
        path: image,
  };
  return (reference) => images[reference];
}

/// Lo que se está mirando de una presentación en el visor: las notas a la
/// vista y el diseño, que la barra de arriba, el cuerpo y la pantalla
/// completa comparten.
@immutable
class PresentationViewerState {
  const PresentationViewerState({required this.design, this.notes = false});

  final DeckDesign design;

  /// Si se ven las notas del presentador.
  final bool notes;

  PresentationViewerState copyWith({DeckDesign? design, bool? notes}) =>
      PresentationViewerState(
        design: design ?? this.design,
        notes: notes ?? this.notes,
      );
}

/// El visor de una presentación —su id es el argumento—: el diseño elegido,
/// que se guarda en las opciones, aparte del contenido (decisión G), un
/// instante después del último cambio, y las notas a la vista.
///
/// Nunca vuelve a pedirle nada a la IA: cambiar la plantilla, la paleta o la
/// letra solo cambia cómo se dibuja lo que ya está.
class PresentationViewerController
    extends AutoDisposeFamilyNotifier<PresentationViewerState, String> {
  /// Cuánto se espera después del último cambio para guardarlo: el tono del
  /// color propio cambia muchas veces por segundo mientras se arrastra.
  static const saveDelay = Duration(milliseconds: 400);

  Timer? _pending;
  DeckDesign? _unsaved;

  /// Lo que hace falta para guardar, a mano desde el principio: al cerrar el
  /// visor se guarda lo pendiente, y ahí ya no se puede pedir nada.
  late StudyCreationRepository _repository;
  Map<String, Object?>? _options;

  /// Qué diapositiva se ve: lo comparten el visor, la tira de miniaturas, la
  /// pantalla completa y la hoja de diseño (que muestra la que se veía).
  final pager = DeckPagerController();

  @override
  PresentationViewerState build(String id) {
    _repository = ref.read(studyCreationRepositoryProvider);
    ref.onDispose(pager.dispose);
    var seeded = false;
    ref
      ..listen(studyCreationProvider(id), (_, next) {
        final creation = next.valueOrNull;
        if (creation == null) return;
        _options = creation.options;
        // Si se pidió antes de que la creación terminara de leerse, el diseño
        // y las notas salen de ella apenas llega —mientras nadie los tocó—.
        if (!seeded && !_touched) {
          seeded = true;
          state = initialOf(creation);
        }
      }, fireImmediately: true)
      ..onDispose(_flush);
    final creation = ref.read(studyCreationProvider(id)).valueOrNull;
    seeded = creation != null;
    return creation == null
        ? const PresentationViewerState(design: DeckDesign())
        : initialOf(creation);
  }

  /// Si la persona ya cambió algo: entonces nada lo pisa.
  var _touched = false;

  /// Cómo se abre [creation]: con su diseño y, en «Del presentador» —donde
  /// lo que se dice es la mitad de la presentación—, con las notas a la vista.
  static PresentationViewerState initialOf(StudyCreation creation) =>
      PresentationViewerState(
        design: designOf(creation),
        notes:
            PresentationOptions.of(creation.options).format ==
            DeckFormat.presenter,
      );

  /// El diseño guardado de [creation], con la plantilla que sugirió la IA si
  /// se eligió «Automática».
  static DeckDesign designOf(StudyCreation creation) => presentationDesignOf(
    creation.options,
    hint: PresentationContent.decode(creation.content).templateHint,
  );

  void toggleNotes() {
    _touched = true;
    state = state.copyWith(notes: !state.notes);
  }

  /// Cambia el diseño ya, en pantalla, y lo guarda en un momento.
  void setDesign(DeckDesign design) {
    if (design == state.design) return;
    _touched = true;
    state = state.copyWith(design: design);
    _unsaved = design;
    _pending?.cancel();
    _pending = Timer(saveDelay, _flush);
  }

  void _flush() {
    _pending?.cancel();
    _pending = null;
    final design = _unsaved;
    final options = _options;
    if (design == null || options == null) return;
    _unsaved = null;
    final saved = {...options, PresentationOptionKeys.design: design.toJson()};
    _options = saved;
    unawaited(_repository.amend(arg, options: saved));
  }
}

final presentationViewerProvider = NotifierProvider.autoDispose
    .family<PresentationViewerController, PresentationViewerState, String>(
      PresentationViewerController.new,
    );
