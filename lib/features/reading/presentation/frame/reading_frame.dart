import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_handoff.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_dock.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_ai_row.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance_sheet.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_audio.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_contents_sheet.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_more_sheet.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_player_slot.dart';
import 'package:sinapsis/features/text_notes/presentation/providers/text_note_providers.dart';
import 'package:sinapsis/features/text_notes/presentation/widgets/text_notes_list_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Qué se lee en un marco: lo que dicen la hoja de ⋮ y, si el cuerpo no lo
/// pone, el título grande de arriba.
@immutable
class ReadingDocumentInfo {
  const ReadingDocumentInfo({
    required this.title,
    required this.kindLabel,
    required this.kindIcon,
    this.subtitle,
    this.thumbnail,
    this.onRename,
  });

  final String title;

  /// El tipo, dicho en palabras: «PDF», «Resumen», «Texto · 6 páginas».
  final String kindLabel;
  final IconData kindIcon;

  /// Lo que va debajo del título, en chico: cuántas notas salieron de él.
  final String? subtitle;

  /// La miniatura de la hoja de ⋮; sin ella, el ícono del tipo.
  final Widget? thumbnail;

  /// ✎, para cambiarle el nombre; `null` si no se puede.
  final Future<void> Function(BuildContext context)? onRename;
}

/// Lo que cambia «Apariencia» en el cuerpo de un marco (F47, paso 1): en el
/// texto, la letra y su tamaño; en un PDF o una foto, el zoom y el tono de la
/// página. El modo y el color de lo que suena valen para los dos.
enum ReadingBodyKind {
  /// Texto que pinta la app: el extraído, el resumen, un libro paginado, una
  /// transcripción.
  text,

  /// Una página que se ve como es: un PDF, una foto o un escaneo.
  page,

  /// Una foto o un escaneo con el texto que se leyó en él: la página y la
  /// letra del texto.
  pageWithText,

  /// Lo que se ve como es —una página web en vista móvil, con su letra; un
  /// audio o un video—: solo cambian el modo y lo que suena.
  asIs,
}

/// Una entrada de «Contenido»: una sección del documento, un capítulo, una
/// fuente.
@immutable
class ReadingOutlineEntry {
  const ReadingOutlineEntry({
    required this.label,
    required this.onSelected,
    this.detail,
    this.depth = 0,
    this.key,
  });

  final String label;

  /// Debajo, en chico: la página, cuántas oraciones.
  final String? detail;

  /// Cuánto se sangra: 0 los de arriba, 1 sus partes.
  final int depth;

  /// Ir ahí. La hoja ya se cerró cuando se llama.
  final VoidCallback onSelected;

  final Key? key;
}

/// El zoom de una página (F47, paso 1): lo que el cuerpo —el PDF, la foto—
/// le deja mover a «Apariencia».
abstract interface class ReadingZoom {
  /// Cuánto se acercó, 1 si ocupa el ancho.
  ValueListenable<double> get level;

  void zoomIn();
  void zoomOut();

  /// Vuelve a que la página ocupe el ancho.
  void fit();
}

/// Lo que el cuerpo de un marco le cuenta a la barra: su índice, que arma
/// mientras se lee —los capítulos de un libro, los documentos de una
/// extracción—, su zoom, si es una página, y los textos con notas que
/// muestra (F45, paso 8b), para «Notas (N)» de ⋮. Lo encuentra con
/// [ReadingFrameController.maybeOf]; fuera de un marco no hay ninguno, y el
/// cuerpo se ve igual.
class ReadingFrameController extends ChangeNotifier {
  List<ReadingOutlineEntry> _outline = const [];
  ReadingZoom? _zoom;
  List<TextNoteSource> _noteSources = const [];

  List<ReadingOutlineEntry> get outline => _outline;
  ReadingZoom? get zoom => _zoom;

  /// Los textos con notas del cuerpo, en su orden; ninguno si el cuerpo no
  /// tiene un texto que las lleve.
  List<TextNoteSource> get noteSources => _noteSources;

  /// Los textos con notas que muestra el cuerpo. Avisa solo si cambió alguno
  /// —un `reveal` nuevo de cada cuadro se toma sin avisar—.
  set noteSources(List<TextNoteSource> sources) {
    final same =
        sources.length == _noteSources.length &&
        [
          for (var i = 0; i < sources.length; i++)
            sources[i].sameTextAs(_noteSources[i]),
        ].every((same) => same);
    _noteSources = List.unmodifiable(sources);
    if (!same) notifyListeners();
  }

  /// [sources] se fueron —el cuerpo se cerró—: si eran los registrados, ya
  /// no hay.
  void dropNoteSources(List<TextNoteSource> sources) {
    if (identical(sources, _noteSources) ||
        (sources.isNotEmpty && listEquals(sources, _noteSources))) {
      noteSources = const [];
    }
  }

  set outline(List<ReadingOutlineEntry> entries) {
    if (listEquals(entries, _outline)) return;
    _outline = List.unmodifiable(entries);
    notifyListeners();
  }

  set zoom(ReadingZoom? zoom) {
    if (identical(zoom, _zoom)) return;
    _zoom = zoom;
    notifyListeners();
  }

  /// [zoom] se fue: si era el registrado, ya no hay.
  void dropZoom(ReadingZoom zoom) {
    if (identical(zoom, _zoom)) this.zoom = null;
  }

  /// El del marco de arriba, o `null` fuera de uno.
  static ReadingFrameController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ReadingFrameScope>()?.controller;
}

/// Le da al marco de arriba los textos con notas de un cuerpo —[sources]—
/// para «Notas (N)» de ⋮ (F45, paso 8b), después de cada cuadro en que
/// cambian, y se los saca al irse. Fuera de un marco no hace nada.
class ReadingNotesOffer extends StatefulWidget {
  const ReadingNotesOffer({
    required this.sources,
    required this.child,
    super.key,
  });

  final List<TextNoteSource> sources;
  final Widget child;

  @override
  State<ReadingNotesOffer> createState() => _ReadingNotesOfferState();
}

class _ReadingNotesOfferState extends State<ReadingNotesOffer> {
  ReadingFrameController? _frame;
  List<TextNoteSource> _offered = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frame = ReadingFrameController.maybeOf(context);
  }

  @override
  void dispose() {
    _frame?.dropNoteSources(_offered);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame != null) {
      final sources = widget.sources;
      // Después del cuadro: avisarle al marco mientras se construye no se
      // puede.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) frame.noteSources = _offered = sources;
      });
    }
    return widget.child;
  }
}

class _ReadingFrameScope extends InheritedWidget {
  const _ReadingFrameScope({required this.controller, required super.child});

  final ReadingFrameController controller;

  @override
  bool updateShouldNotify(_ReadingFrameScope oldWidget) =>
      oldWidget.controller != controller;
}

/// **El marco de lectura** (F47, paso 1, decisión A; capturas 3 a 6 y 9): el
/// mismo para el original —un PDF, una página web, un libro, una foto, un
/// audio o un video—, el texto extraído, el resumen, la síntesis y lo
/// creado. Lo único que cambia es [body].
///
/// - **La barra de arriba, limpia**: ← a la izquierda y, a la derecha, cuatro
///   botones redondos con borde, del mismo tamaño —**Contenido**, **IA**,
///   **Aa** y **⋮**—. El título no va en la barra: va grande, en el cuerpo
///   ([showTitle] lo pone arriba si el cuerpo no lo trae).
/// - **La fila de IA**, debajo, que IA prende y apaga y que se recuerda: las
///   fichas de [aiRow] —Resumir · Sintetizar · Palabras clave, con su estado
///   y su avance—, **Preguntar a la IA** y **Podcast** ([podcastScope]). En
///   angosto se desplaza de costado. [aiRowPinned] la deja abierta mientras
///   se elige a mano.
/// - **El cuerpo**, con los colores del modo de lectura de «Apariencia».
/// - **Abajo, el lugar del reproductor** ([ReadingPlayerSlot]): «Escuchar»
///   si no suena nada; si suena, el lugar del reproductor anclado de toda la
///   app (F47, paso 2), que no tapa lo último que se lee. Sin el botón
///   flotante: el marco lo aparta (`ReadAloudDock`).
/// - **⋮** lleva, además de [menu], «Resumir» si hay [onSummarize] y
///   «Añadir a la cola» para lo que ofrece el cuerpo; y arriba de todo, el
///   audio de lo que ofrece el cuerpo (F47, paso 5): «Descargar audio»,
///   «Exportar audio» y «Borrar el audio descargado» ([readingAudioGroup]),
///   con la barra que dice cómo va la descarga ([ReadingAudioDownloadBar]).
///
/// Nada de lo que se ve depende de que haya animaciones: la fila aparece y
/// se va de una con «sin animaciones».
class ReadingFrame extends ConsumerStatefulWidget {
  const ReadingFrame({
    required this.info,
    required this.body,
    this.bodyKind = ReadingBodyKind.text,
    this.showTitle = true,
    this.aiRow,
    this.aiRowPinned = false,
    this.onAskAi,
    this.onSummarize,
    this.contents = const [],
    this.menu = const [],
    this.podcastScope,
    super.key,
  });

  final ReadingDocumentInfo info;
  final Widget body;
  final ReadingBodyKind bodyKind;

  /// Si el marco pone el título grande arriba del cuerpo. Un cuerpo que lo
  /// trae adentro —el texto de corrido, que lo desplaza con el resto— no lo
  /// repite.
  final bool showTitle;

  /// Las fichas de la fila de IA, con [ReadingAiStrip] y lo que el marco le
  /// suma al final —Preguntar a la IA y Podcast—; `null` si no hay qué
  /// marcar, y la fila lleva solo eso.
  final Widget Function(BuildContext context, List<Widget> trailing)? aiRow;

  /// La fila se queda abierta aunque IA la haya cerrado: se está eligiendo a
  /// mano, y la línea que lo dice está ahí.
  final bool aiRowPinned;

  /// «Preguntar a la IA»; sin esto, el chat se abre con la pregunta sobre
  /// [ReadingDocumentInfo.title] a medio escribir.
  final VoidCallback? onAskAi;

  /// «Resumir» de ⋮: lo mismo que la ficha de la fila de IA. `null` si no
  /// hay qué resumir.
  final VoidCallback? onSummarize;

  /// Las secciones propias de «Contenido» —las fuentes, las partes de un
  /// documento procesado—, además del índice que arma el cuerpo y de «Leer
  /// en voz alta».
  final List<ReadingContentsSection> contents;

  /// Los grupos de ⋮, en orden; el de lo que se borra va último.
  final List<ReadingMenuGroup> menu;

  /// Sobre qué se arma un podcast desde la ficha «Podcast» —el documento
  /// procesado que se lee, el recorte de lo creado—; `null` si no es de lo
  /// procesado, y la ficha queda apagada diciendo por qué.
  final CreationScope? podcastScope;

  @override
  ConsumerState<ReadingFrame> createState() => _ReadingFrameState();
}

class _ReadingFrameState extends ConsumerState<ReadingFrame> {
  final _controller = ReadingFrameController();
  List<TextNoteSource> _noteSources = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onBodyChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onBodyChanged)
      ..dispose();
    super.dispose();
  }

  /// El cuerpo cambió sus textos con notas: «Notas (N)» cuenta los nuevos.
  void _onBodyChanged() {
    final sources = _controller.noteSources;
    if (identical(sources, _noteSources)) return;
    final changed =
        sources.length != _noteSources.length ||
        [
          for (var i = 0; i < sources.length; i++)
            !sources[i].sameTextAs(_noteSources[i]),
        ].any((changed) => changed);
    _noteSources = sources;
    if (!changed || !mounted) return;
    // Un cuerpo que se va avisa mientras el árbol se desarma: ahí no se
    // puede volver a armar, y se espera al cuadro siguiente.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// «Notas (N)» (F45, paso 8b): la lista de las notas de lo que se lee, con
  /// N al día, sobre [host] —el marco, con los colores del modo de lectura—.
  /// Sin un texto con notas en el cuerpo, no está.
  ReadingMenuEntry? _notesEntry(BuildContext host, int count) {
    if (_noteSources.isEmpty) return null;
    return ReadingMenuEntry(
      key: const Key('reading-more-notes'),
      icon: Icons.sticky_note_2_outlined,
      label: AppLocalizations.of(host)!.f45S8bNotesMenu(count),
      onSelected: () => unawaited(
        // Los de ahora: un `reveal` de cada cuadro.
        showTextNotesList(host, ref, sources: _controller.noteSources),
      ),
    );
  }

  /// «Añadir a la cola» (F47, paso 2): lo que ofrece el cuerpo suena después
  /// de lo de ahora, y sin nada sonando empieza. Apagado si no hay nada que
  /// leer o si es lo que ya suena.
  ReadingMenuEntry _enqueueEntry(AppLocalizations l10n) {
    final offered = currentReadableOf(ref.read(readableRegistryProvider));
    final reading = ref.read(readAloudControllerProvider).document?.id;
    return ReadingMenuEntry(
      key: const Key('reading-more-enqueue'),
      icon: Icons.playlist_add_rounded,
      label: l10n.f47P2AddToQueue,
      onSelected: offered == null || offered.id == reading
          ? null
          : () => unawaited(
              ref.read(readAloudControllerProvider.notifier).enqueue(offered),
            ),
    );
  }

  void _askAi() {
    final onAskAi = widget.onAskAi;
    if (onAskAi != null) return onAskAi();
    askAiAbout(context, widget.info.title);
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(readingAppearanceProvider);
    final appTheme = Theme.of(context);
    final theme = appearance.mode.themeOver(appTheme);
    final aiOpen = appearance.aiRowOpen || widget.aiRowPinned;
    final trailing = [
      ReadingAskAiChip(onPressed: _askAi),
      ReadingPodcastChip(scope: widget.podcastScope),
    ];
    // N de «Notas (N)», al día mientras el marco está abierto.
    final noteCount = _noteSources.fold(
      0,
      (sum, source) =>
          sum +
          (ref.watch(textNoteCountProvider(source.target)).valueOrNull ?? 0),
    );
    // El audio descargado de lo que se lee, ya sabido al abrir ⋮.
    watchReadingAudio(
      ref,
      ref.watch(
        readableRegistryProvider.select(
          (offered) => currentReadableOf(offered)?.id,
        ),
      ),
    );

    return Theme(
      data: theme,
      child: ReadAloudDock(
        child: _ReadingFrameScope(
          controller: _controller,
          child: Builder(
            builder: (context) => Scaffold(
              key: const Key('reading-frame'),
              backgroundColor: theme.colorScheme.surface,
              body: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ReadingFrameBar(
                      aiOpen: aiOpen,
                      onContents: () => unawaited(
                        showReadingContents(
                          context,
                          controller: _controller,
                          sections: widget.contents,
                        ),
                      ),
                      onAi: () => unawaited(
                        ref
                            .read(readingAppearanceProvider.notifier)
                            .setAiRowOpen(open: !appearance.aiRowOpen),
                      ),
                      onAppearance: () => unawaited(
                        showReadingAppearance(
                          context,
                          bodyKind: widget.bodyKind,
                          controller: _controller,
                          appTheme: appTheme,
                        ),
                      ),
                      onMore: () => unawaited(
                        showReadingMore(
                          context,
                          info: widget.info,
                          groups: [
                            ?readingAudioGroup(context, ref),
                            if (widget.onSummarize case final summarize?)
                              ReadingMenuGroup([
                                ReadingMenuEntry(
                                  key: const Key('reading-more-summarize'),
                                  icon: Icons.notes_outlined,
                                  label: AppLocalizations.of(
                                    context,
                                  )!.f47P1MoreSummarize,
                                  onSelected: summarize,
                                ),
                              ]),
                            ReadingMenuGroup([
                              ?_notesEntry(context, noteCount),
                              _enqueueEntry(AppLocalizations.of(context)!),
                            ]),
                            ...widget.menu,
                          ],
                        ),
                      ),
                    ),
                    if (aiOpen)
                      Padding(
                        key: const Key('reading-ai-row'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child:
                            widget.aiRow?.call(context, trailing) ??
                            ReadingAiStrip(children: trailing),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.showTitle)
                            ReadingTitleHeader(info: widget.info),
                          Expanded(
                            child: ReadingPageTone(
                              bodyKind: widget.bodyKind,
                              child: widget.body,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const ReadingAudioDownloadBar(),
                    const ReadingPlayerSlot(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La barra del marco: ← y los cuatro botones redondos.
class ReadingFrameBar extends StatelessWidget {
  const ReadingFrameBar({
    required this.aiOpen,
    required this.onContents,
    required this.onAi,
    required this.onAppearance,
    required this.onMore,
    super.key,
  });

  final bool aiOpen;
  final VoidCallback onContents;
  final VoidCallback onAi;
  final VoidCallback onAppearance;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          const BackButton(key: Key('reading-frame-back')),
          const Spacer(),
          ReadingRoundButton(
            key: const Key('reading-frame-contents'),
            tooltip: l10n.f47P1FrameContents,
            onPressed: onContents,
            child: const Icon(Icons.toc_rounded),
          ),
          ReadingRoundButton(
            key: const Key('reading-frame-ai'),
            tooltip: l10n.f47P1FrameAi,
            selected: aiOpen,
            onPressed: onAi,
            child: Icon(
              aiOpen ? Icons.auto_awesome : Icons.auto_awesome_outlined,
            ),
          ),
          ReadingRoundButton(
            key: const Key('reading-frame-appearance'),
            tooltip: l10n.f47P1FrameAppearance,
            onPressed: onAppearance,
            child: const _Aa(),
          ),
          ReadingRoundButton(
            key: const Key('reading-frame-more'),
            tooltip: l10n.f47P1FrameMore,
            onPressed: onMore,
            child: const Icon(Icons.more_vert),
          ),
        ],
      ),
    );
  }
}

/// «Aa»: dibujado con letras y no con un ícono, del mismo tamaño que los
/// íconos de al lado aunque la letra del teléfono esté al doble.
class _Aa extends StatelessWidget {
  const _Aa();

  @override
  Widget build(BuildContext context) => Text(
    'Aa',
    textScaler: TextScaler.noScaling,
    style: TextStyle(
      fontFamily: ReadingFont.lora.family,
      fontSize: 18,
      height: 1,
      fontWeight: FontWeight.w700,
      color: IconTheme.of(context).color,
    ),
  );
}

/// Un botón redondo con borde de la barra del marco: todos del mismo tamaño,
/// con su nombre para el lector de pantalla. [selected] lo rellena con el
/// color de acento suave —la fila de IA a la vista—.
class ReadingRoundButton extends StatelessWidget {
  const ReadingRoundButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.selected,
    super.key,
  });

  /// El lado del botón; con el margen, ocupa 48 para el dedo.
  static const size = 44.0;

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = selected ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        tooltip: tooltip,
        isSelected: selected,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(size),
          minimumSize: const Size.square(size),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
          side: BorderSide(
            color: on ? scheme.secondaryContainer : scheme.outlineVariant,
          ),
          backgroundColor: on ? scheme.secondaryContainer : null,
          foregroundColor: on
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
        icon: child,
      ),
    );
  }
}

/// El título grande, arriba del cuerpo que no lo trae: el tipo en chico y el
/// título con la letra de lectura. Es el encabezado de la pantalla para el
/// lector de pantalla.
class ReadingTitleHeader extends ConsumerWidget {
  const ReadingTitleHeader({required this.info, super.key});

  final ReadingDocumentInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appearance = ref.watch(readingAppearanceProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: readingColumnWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.kindLabel.toUpperCase(),
                key: const Key('reading-frame-kind'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                header: true,
                child: Text(
                  info.title,
                  key: const Key('reading-frame-title'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: appearance.titleStyle(theme, size: 22),
                ),
              ),
              if (info.subtitle case final subtitle?) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  key: const Key('reading-frame-subtitle'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// El ancho cómodo de la columna de lectura: unas 70 letras por renglón con
/// la letra de entrada, como un libro; en un teléfono, el ancho de la
/// pantalla con sus márgenes.
const readingColumnWidth = 680.0;

/// Los márgenes de la columna de lectura: generosos, y un poco menos en un
/// teléfono angosto.
EdgeInsets readingColumnPadding(BuildContext context) {
  final narrow = MediaQuery.sizeOf(context).width < 480;
  return EdgeInsets.symmetric(horizontal: narrow ? 22 : 36);
}

/// El tono de la página en un PDF o una foto (F47, paso 1, «Apariencia»):
/// la original, oscura —los claros pasan a oscuros sin cambiar de color, así
/// lo marcado sigue diciendo qué es— o en sepia. En el texto y en la página
/// web no hace nada: ahí manda el modo de lectura.
class ReadingPageTone extends ConsumerWidget {
  const ReadingPageTone({
    required this.bodyKind,
    required this.child,
    super.key,
  });

  final ReadingBodyKind bodyKind;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bodyKind != ReadingBodyKind.page) return child;
    // Con el texto que se leyó al lado —una foto—, el cuerpo tiñe solo la
    // imagen (`ReadingPageTone` alrededor de ella): la letra va con el modo.
    final paper = ref.watch(readingAppearanceProvider.select((a) => a.paper));
    final matrix = paper.matrix;
    if (matrix == null) return child;
    return ColorFiltered(
      key: Key('reading-page-tone-${paper.name}'),
      colorFilter: ColorFilter.matrix(matrix),
      child: child,
    );
  }
}

/// Abre el chat con la pregunta sobre [title] a medio escribir: el chat sobre
/// este documento (F47, paso 1, «Preguntar a la IA»).
void askAiAbout(BuildContext context, String title) {
  final l10n = AppLocalizations.of(context)!;
  askInChat(
    context,
    ChatHandoff(question: l10n.f47P1AskAiDraft(title), send: false),
  );
}
