import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/widgets/custom_text_field.dart';
import 'package:sinapsis/core/design/widgets/primary_button.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/blocks/presentation/providers/note_template_providers.dart';
import 'package:sinapsis/features/blocks/presentation/screens/block_editor_screen.dart';
import 'package:sinapsis/features/blocks/presentation/widgets/template_picker_sheet.dart';
import 'package:sinapsis/features/capture/data/adapters/file_adapter.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/camera_chooser.dart';
// Solo para el enlace [DocumentScanAssembler] del comentario de
// `_fileToSubmit`; el análisis estático no ve esa referencia dentro de un
// doc comment.
// ignore: unused_import
import 'package:sinapsis/features/capture/domain/services/document_scan_assembler.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_notifier.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_state.dart';
import 'package:sinapsis/features/capture/presentation/providers/shared_content_controller.dart';
import 'package:sinapsis/features/duplicates/presentation/providers/duplicate_providers.dart';
import 'package:sinapsis/features/duplicates/presentation/widgets/duplicate_warning_dialog.dart';
import 'package:sinapsis/features/library/presentation/providers/library_query_notifier.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_field.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// De qué se trata lo que se está por guardar, elegido a propósito antes de
/// mostrar ningún campo.
///
/// Es una decisión de la interfaz, no del dominio: por debajo, seguir siendo
/// [CaptureRequest.text] o [CaptureRequest.file] no cambia, y quién reconoce
/// de verdad qué se guardó sigue siendo el registro de adaptadores — elegir
/// "Video" acá no le miente al sistema si lo pegado termina siendo otra cosa,
/// solo elige qué campo mostrar y con qué texto de ayuda. Ese reparto es lo
/// que evita el problema que tenía la pantalla anterior: un único formulario
/// con todo a la vista todo el tiempo, aunque quien guarda un libro no tenga
/// ningún uso para un cuadro de texto enorme.
enum _CaptureKind {
  video,
  post,
  webPage,
  book,
  image,
  audio,
  pasteText,

  /// Sacar una foto en el momento, en vez de elegir una que ya existe. Al
  /// final de la lista a propósito: es la opción más nueva, y las que
  /// vienen desde antes ya tienen un orden que quien usa la app aprendió.
  camera;

  IconData get icon => switch (this) {
    _CaptureKind.video => Icons.smart_display_outlined,
    _CaptureKind.post => Icons.forum_outlined,
    _CaptureKind.webPage => Icons.article_outlined,
    _CaptureKind.book => Icons.menu_book_outlined,
    _CaptureKind.image => Icons.image_outlined,
    _CaptureKind.audio => Icons.graphic_eq,
    _CaptureKind.pasteText => Icons.content_paste,
    _CaptureKind.camera => Icons.photo_camera_outlined,
  };

  String label(AppLocalizations l10n) => switch (this) {
    _CaptureKind.video => l10n.captureTypeVideo,
    _CaptureKind.post => l10n.captureTypePost,
    _CaptureKind.webPage => l10n.captureTypeWebPage,
    _CaptureKind.book => l10n.captureTypeBook,
    _CaptureKind.image => l10n.captureTypeImage,
    _CaptureKind.audio => l10n.captureTypeAudio,
    _CaptureKind.pasteText => l10n.captureTypePasteText,
    _CaptureKind.camera => l10n.captureTypeCamera,
  };

  /// Si este paso pide un enlace en una sola línea.
  bool get isLink => switch (this) {
    _CaptureKind.video || _CaptureKind.post || _CaptureKind.webPage => true,
    _ => false,
  };

  /// Si este paso trae un archivo —del selector del sistema o de la
  /// cámara— y por eso muestra la tarjeta de "archivo elegido" en vez de un
  /// campo de texto.
  bool get isFile => switch (this) {
    _CaptureKind.book ||
    _CaptureKind.image ||
    _CaptureKind.audio ||
    _CaptureKind.camera => true,
    _ => false,
  };

  /// Si este paso trae el archivo sacándole una foto a algo, en vez de
  /// eligiéndolo del almacenamiento del dispositivo. Decide qué acción
  /// dispara al elegir la tarjeta, y qué botón mostrar mientras no haya
  /// ninguna foto todavía.
  bool get isCamera => this == _CaptureKind.camera;
}

/// A qué [_CaptureKind] corresponde cada [SourceKind], para preseleccionar
/// el paso correcto cuando algo llega ya reconocido —compartido desde otra
/// app, o soltado sobre la pantalla— en vez de obligar a elegir de nuevo
/// algo que ya se sabe.
_CaptureKind _kindFor(SourceKind kind) => switch (kind) {
  SourceKind.youtube || SourceKind.video => _CaptureKind.video,
  SourceKind.socialPost => _CaptureKind.post,
  SourceKind.webPage => _CaptureKind.webPage,
  // Una referencia no llega por acá; si se la completa con su archivo, es un
  // libro o un artículo que se sube.
  SourceKind.document || SourceKind.reference => _CaptureKind.book,
  SourceKind.image => _CaptureKind.image,
  SourceKind.audio => _CaptureKind.audio,
  SourceKind.manualNote => _CaptureKind.pasteText,
};

/// Si hay una cámara de verdad detrás de `ImageSource.camera` en esta
/// plataforma — ver el comentario de `image_picker` en `pubspec.yaml`.
/// Windows, macOS y Linux resuelven el paquete igual, pero ninguno tiene una
/// implementación real de la cámara: ofrecer la tarjeta ahí terminaría en un
/// botón que revienta al tocarlo, así que se la saca de la grilla en vez de
/// mostrarla deshabilitada.
bool get _cameraIsSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Meter algo en la bóveda.
///
/// El primer paso es elegir de qué se trata, con botones — video,
/// publicación, página web, libro, imagen, audio, texto para pegar, o una
/// nota propia. Recién ahí aparece lo que hace falta para guardar *eso*: un
/// campo de enlace angosto para un video, el selector de archivos para un
/// libro, el cuadro grande solo para cuando de verdad se va a pegar un
/// texto largo. Mostrar los ocho caminos a la vez —como hacía el cuadro
/// único de antes— es ruido para los siete octavos que no se van a usar en
/// esa captura.
///
/// Lo que sí se conserva del diseño anterior es la honestidad sobre lo que
/// se entendió: con un enlace pegado, se sigue mostrando en vivo "se va a
/// guardar como X" antes de guardar nada, porque quien elige "Video" y pega
/// un enlace que en realidad es de una publicación merece saberlo antes de
/// apretar el botón, no después.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _inputController = TextEditingController();
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();

  /// `null` mientras se está eligiendo qué tipo de cosa es. Una vez elegido,
  /// decide qué campo se ve.
  _CaptureKind? _kind;

  /// El archivo elegido, si hay uno.
  ///
  /// Vive en la pantalla y no en el notifier porque es estado de la
  /// pantalla: mientras no se apriete guardar, no le incumbe a nadie más. Lo
  /// que sí sale de acá es que la captura pasa a ser de archivo y no de
  /// texto.
  CapturedFile? _file;

  /// Las fotos que se sacaron en esta sesión de escaneo, en el orden en que
  /// se sacaron. Solo tiene sentido mientras [_kind] es
  /// [_CaptureKind.camera]: los demás pasos que traen un archivo (Libro,
  /// Imagen, Audio) siguen usando [_file] solo, porque ahí no existe la
  /// noción de "una página más" — se elige un archivo que ya existe, no se
  /// arma uno nuevo a fuerza de fotos.
  ///
  /// Una sola foto se guarda tal cual, como imagen; dos o más se combinan
  /// en un solo documento PDF al guardar — ver [_fileToSubmit].
  final List<Uint8List> _scannedPages = [];

  /// Si hay algo arrastrado encima de la pantalla ahora mismo, para dibujar
  /// el borde que avisa que soltar acá va a funcionar.
  var _isDraggingFile = false;

  /// El tema en el que va a quedar lo que se guarde, o `null` para "sin
  /// clasificar".
  ///
  /// Arranca en el tema en el que está parada la biblioteca: quien está
  /// mirando "Filosofía" y aprieta guardar casi siempre trae algo para
  /// "Filosofía", y si no, cambiarlo es un toque. Se lee una sola vez, en
  /// `initState`: lo que se elija después en el formulario no tiene por qué
  /// volver a la biblioteca. Sobrevive a "Cambiar tipo" a propósito: el tema
  /// no depende de si lo que se guarda es un video o un libro.
  String? _spaceId;

  @override
  void initState() {
    super.initState();
    _spaceId = ref.read(libraryQueryNotifierProvider).spaceId;
    // Lo escrito decide qué se muestra abajo, así que hay que redibujar a
    // medida que se escribe.
    _inputController.addListener(_onInputChanged);

    // Diferido al post-frame por la regla de Riverpod de no tocar providers
    // mientras se construye el árbol de widgets: takeNext() modifica la
    // cola, y hacerlo acá adentro revienta con "Tried to modify a provider
    // while the widget tree was building".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefillFromSharedContent();
    });
  }

  /// Si algo llegó compartido desde otra app, lo deja cargado para revisar
  /// —tal cual si el usuario lo hubiera pegado o elegido a mano— y elige
  /// por su cuenta el paso que corresponde, para que no haga falta
  /// atravesar el selector de tipo con algo que ya se sabe qué es.
  ///
  /// Se pide una sola vez, acá: [SharedContentController.takeNext] ya lo
  /// saca de la cola al llamarlo, así que no hay riesgo de que una
  /// reconstrucción de esta pantalla lo vuelva a ofrecer o pise algo que el
  /// usuario ya esté escribiendo.
  void _prefillFromSharedContent() {
    final request = ref
        .read(sharedContentControllerProvider.notifier)
        .takeNext();
    if (request == null) return;

    setState(() {
      switch (request) {
        case TextCapture(:final rawInput):
          _inputController.text = rawInput;
          final detected = _detectedKind;
          _kind = detected != null
              ? _kindFor(detected)
              : _CaptureKind.pasteText;
        case FileCapture(:final file):
          _file = file;
          _kind = _kindFor(file.format.sourceKind);
      }
    });
  }

  @override
  void dispose() {
    _inputController
      ..removeListener(_onInputChanged)
      ..dispose();
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onInputChanged() => setState(() {});

  /// Qué va a guardar la app con lo que hay escrito ahora.
  ///
  /// Se le pregunta al mismo registro de adaptadores que hará el trabajo de
  /// verdad, y no a una copia de las reglas escrita para la interfaz: dos
  /// versiones de la misma lógica terminan discrepando, y entonces la
  /// pantalla promete una cosa y la app guarda otra.
  SourceKind? get _detectedKind {
    final input = _inputController.text.trim();
    if (input.isEmpty) return null;

    return ref
        .read(sourceAdapterRegistryProvider)
        .resolve(CaptureRequest.text(rawInput: input))
        .producesKind;
  }

  void _selectKind(_CaptureKind kind) {
    setState(() => _kind = kind);
    if (kind.isCamera) {
      unawaited(_takePhoto());
    } else if (kind.isFile) {
      unawaited(_chooseFile());
    }
  }

  void _changeKind() {
    setState(() {
      _kind = null;
      _file = null;
      _scannedPages.clear();
      _inputController.clear();
    });
  }

  /// Abre el selector del sistema.
  ///
  /// Cancelar no es un error y no muestra nada: es la respuesta más común de
  /// un selector de archivos, porque abrirlo por accidente pasa todo el
  /// tiempo. La falta de permiso sí se avisa, porque pide una acción distinta
  /// —ir a los ajustes del sistema— y sin el aviso el botón parecería roto.
  Future<void> _chooseFile() async {
    final l10n = AppLocalizations.of(context)!;

    try {
      final chosen = await ref.read(fileChooserProvider).pickOne();
      if (chosen == null || !mounted) return;

      setState(() => _file = chosen);
    } on FileAccessDeniedException {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.captureFileAccessDenied)));
    }
  }

  /// Abre la cámara del sistema y suma lo que salga a [_scannedPages]. El
  /// mismo criterio que [_chooseFile]: cancelar sin sacar ninguna foto no es
  /// un error y no muestra nada.
  ///
  /// Sirve igual para la primera foto que para "agregar otra página": las
  /// dos acciones son la misma, sacar una foto más y sumarla a la lista, así
  /// que no hace falta un método aparte para la segunda en adelante.
  Future<void> _takePhoto() async {
    final l10n = AppLocalizations.of(context)!;

    try {
      final photo = await ref.read(cameraChooserProvider).takePhoto();
      if (photo == null || !mounted) return;

      // Una foto ya llega en memoria: `readAll` no lee nada del disco.
      final page = await photo.readAll();
      if (!mounted) return;
      setState(() => _scannedPages.add(page));
    } on CameraAccessDeniedException {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.captureCameraAccessDenied)));
    }
  }

  void _removeScannedPage(int index) {
    setState(() => _scannedPages.removeAt(index));
  }

  /// Lo que se soltó sobre la pantalla, igual que si se hubiera elegido con
  /// el selector.
  ///
  /// Solo un archivo por vez: [CapturedFile] es singular en toda la app —el
  /// selector del sistema también rechaza una selección múltiple— y una
  /// carpeta no tiene bytes propios que leer. Ninguno de los dos casos es un
  /// error del usuario tan grave como para no explicarlo, así que se avisa
  /// en vez de quedarse callado o adivinar cuál de varios era el que
  /// importaba.
  Future<void> _onDropDone(DropDoneDetails details) async {
    final l10n = AppLocalizations.of(context)!;
    final dropped = details.files;

    if (dropped.length != 1 || dropped.single is DropItemDirectory) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.captureDropSingleFileOnly)));
      return;
    }

    final item = dropped.single;

    final file = await _capturedFileFrom(item);
    if (!mounted) return;

    setState(() {
      _file = file;
      _kind = _kindFor(file.format.sourceKind);
    });
  }

  /// El archivo que se manda a guardar: [_file] tal cual para cualquier paso
  /// que no sea la cámara, o lo que corresponda armar con [_scannedPages]
  /// para ese paso —una foto sola se guarda como imagen, dos o más se
  /// combinan en un solo documento PDF, con [DocumentScanAssembler]—.
  ///
  /// Combinar acá y no en cada foto —un PDF nuevo por cada página que se
  /// suma— evita rehacer ese trabajo una y otra vez mientras se sigue
  /// escaneando: recién hace falta el resultado final cuando se aprieta
  /// guardar.
  Future<CapturedFile?> _fileToSubmit() async {
    if (_kind != _CaptureKind.camera) return _file;
    if (_scannedPages.isEmpty) return null;

    final l10n = AppLocalizations.of(context)!;
    if (_scannedPages.length == 1) {
      return CapturedFile(
        name: '${l10n.capturePhotoFileName}.jpg',
        bytes: _scannedPages.single,
      );
    }

    final pdfBytes = await ref
        .read(documentScanAssemblerProvider)
        .assemble(_scannedPages);
    return CapturedFile(
      name: '${l10n.captureScanFileName}.pdf',
      bytes: pdfBytes,
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final file = await _fileToSubmit();
    if (!mounted) return;

    if (file == null && _inputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.captureEmptyError)));
      return;
    }

    // El aviso de duplicado (F7) solo aplica a texto: un archivo recién
    // tiene contenido con el que comparar después de procesarse, y para
    // ese caso avisa una sugerencia pendiente en cambio (D3). El texto en
    // cambio ya está completo acá, antes de guardar nada.
    final mergeWithItemId = file == null
        ? await checkForDuplicateBeforeSave(
            context: context,
            ref: ref,
            text: _inputController.text,
          )
        : null;
    if (!mounted) return;

    final notifier = ref.read(captureNotifierProvider.notifier);
    final item = file != null
        ? await notifier.captureFile(
            file: file,
            title: _titleController.text,
            note: _noteController.text,
            spaceId: _spaceId,
          )
        : await notifier.capture(
            rawInput: _inputController.text,
            title: _titleController.text,
            note: _noteController.text,
            spaceId: _spaceId,
          );

    if (!mounted || item == null) return;

    if (mergeWithItemId != null) {
      await ref.read(mergeDuplicateItemsUseCaseProvider)(
        keepItemId: mergeWithItemId,
        discardItemId: item.id,
      );
      if (!mounted) return;
    }

    // Al volver, el elemento ya está en la lista: la biblioteca escucha los
    // cambios de la base y se actualiza sola.
    //
    // No se cierra con un `pop` a secas porque no siempre hay algo que
    // cerrar. A esta pantalla se llega apilándola sobre la biblioteca, pero
    // en web también se puede llegar escribiendo la dirección: ahí la pila
    // está vacía y `pop` revienta con "There is nothing to pop" justo
    // después de haber guardado bien. En ese caso se va a la biblioteca, que
    // es adonde el usuario quería llegar de todos modos.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.library);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(captureNotifierProvider);

    ref.listen<CaptureState>(captureNotifierProvider, (previous, next) {
      if (next case CaptureFailed(:final failure)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(failure.localizedMessage(l10n))),
          );
      }
    });

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDraggingFile = true),
      onDragExited: (_) => setState(() => _isDraggingFile = false),
      onDragDone: _onDropDone,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.captureTitle)),
        body: SafeArea(
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              constraints: const BoxConstraints(maxWidth: 560),
              // El único indicio de que soltar acá hace algo: sin él, la
              // superficie que acepta un archivo arrastrado sería invisible
              // hasta que alguien lo probara por las dudas.
              decoration: BoxDecoration(
                border: _isDraggingFile
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : Border.all(color: Colors.transparent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _kind == null
                    ? _TypeSelector(
                        key: const ValueKey('selector'),
                        spaceId: _spaceId,
                        onSelected: _selectKind,
                      )
                    : _CaptureForm(
                        key: ValueKey(_kind),
                        kind: _kind!,
                        inputController: _inputController,
                        titleController: _titleController,
                        noteController: _noteController,
                        spaceId: _spaceId,
                        onSpaceChanged: (spaceId) =>
                            setState(() => _spaceId = spaceId),
                        file: _file,
                        scannedPages: _scannedPages,
                        detectedKind: _detectedKind,
                        isSaving: state is CaptureSaving,
                        onChangeKind: _changeKind,
                        onChooseFile: _kind!.isCamera
                            ? _takePhoto
                            : _chooseFile,
                        onRemoveFile: () => setState(() => _file = null),
                        onRemoveScanPage: _removeScannedPage,
                        onSubmit: _submit,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El primer paso: elegir de qué se trata lo que se va a guardar.
///
/// Una grilla de tarjetas y no un menú desplegable: son solo ocho opciones,
/// todas caben en pantalla a la vez, y tocar directamente la que corresponde
/// es un gesto más corto que abrir un selector para después elegir adentro.
class _TypeSelector extends ConsumerWidget {
  const _TypeSelector({
    required this.spaceId,
    required this.onSelected,
    super.key,
  });

  /// El tema con el que arranca una nota —ver `_CaptureScreenState._spaceId`—:
  /// la nota se escribe en su propio editor, que tiene su propio campo Tema.
  final String? spaceId;
  final ValueChanged<_CaptureKind> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasTemplates =
        (ref.watch(noteTemplatesProvider).valueOrNull ?? []).isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(24),
      shrinkWrap: true,
      children: [
        Text(l10n.captureTypePrompt, style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            for (final kind in _CaptureKind.values)
              if (!kind.isCamera || _cameraIsSupported)
                _TypeCard(
                  icon: kind.icon,
                  label: kind.label(l10n),
                  onTap: () => onSelected(kind),
                ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (context) => BlockEditorScreen(initialSpaceId: spaceId),
            ),
          ),
          icon: Icon(SourceKind.manualNote.icon),
          label: Text(l10n.captureTypeNote),
        ),
        // Solo si hay alguna: sin plantillas guardadas, este botón no
        // llevaría a ningún lado más que a lo mismo que el de arriba (F16).
        if (hasTemplates)
          TextButton.icon(
            onPressed: () async {
              final chosen = await showTemplatePickerSheet(context, ref);
              if (chosen == null || !context.mounted) return;
              final (template,) = chosen;
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => BlockEditorScreen(
                    template: template,
                    initialSpaceId: spaceId,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.bookmark_outline),
            label: Text(l10n.blocksChooseTemplate),
          ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El segundo paso: lo necesario para guardar justo el tipo elegido, y nada
/// más que eso.
class _CaptureForm extends StatelessWidget {
  const _CaptureForm({
    required this.kind,
    required this.inputController,
    required this.titleController,
    required this.noteController,
    required this.spaceId,
    required this.onSpaceChanged,
    required this.file,
    required this.scannedPages,
    required this.detectedKind,
    required this.isSaving,
    required this.onChangeKind,
    required this.onChooseFile,
    required this.onRemoveFile,
    required this.onRemoveScanPage,
    required this.onSubmit,
    super.key,
  });

  final _CaptureKind kind;
  final TextEditingController inputController;
  final TextEditingController titleController;
  final TextEditingController noteController;

  /// El tema elegido para lo que se va a guardar —ver
  /// `_CaptureScreenState._spaceId`—.
  final String? spaceId;
  final ValueChanged<String?> onSpaceChanged;
  final CapturedFile? file;

  /// Las fotos escaneadas hasta ahora — ver el comentario de
  /// `_CaptureScreenState._scannedPages`. Solo se mira cuando [kind] es
  /// [_CaptureKind.camera].
  final List<Uint8List> scannedPages;
  final SourceKind? detectedKind;
  final bool isSaving;
  final VoidCallback onChangeKind;
  final Future<void> Function() onChooseFile;
  final VoidCallback onRemoveFile;
  final ValueChanged<int> onRemoveScanPage;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      shrinkWrap: true,
      children: [
        Row(
          children: [
            Icon(kind.icon, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(kind.label(l10n), style: theme.textTheme.titleMedium),
            ),
            TextButton(
              onPressed: onChangeKind,
              child: Text(l10n.captureChangeType),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (kind.isLink) ...[
          TextField(
            controller: inputController,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.captureLinkLabel,
              hintText: _hintFor(kind, l10n),
              prefixIcon: const Icon(Icons.link),
            ),
          ),
          _DetectedKindPreview(
            detectedKind: detectedKind,
            theme: theme,
            l10n: l10n,
          ),
          // Solo "Video": un enlace de YouTube o TikTok es lo más común,
          // pero no siempre hay un enlace — a veces el video ya está en el
          // teléfono, grabado o descargado antes. Las dos formas conviven
          // en el mismo paso en vez de ser pasos separados: es la misma
          // idea ("un video"), solo cambia de dónde sale.
          if (kind == _CaptureKind.video) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    l10n.captureOrDivider,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            if (file == null)
              OutlinedButton.icon(
                onPressed: onChooseFile,
                icon: const Icon(Icons.video_file_outlined),
                label: Text(l10n.captureChooseVideoFileAction),
              )
            else
              _ChosenFileCard(file: file!, onRemove: onRemoveFile),
          ],
        ] else if (kind == _CaptureKind.pasteText) ...[
          TextField(
            controller: inputController,
            autofocus: true,
            minLines: 5,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: l10n.captureTypePasteTextHint,
            ),
          ),
          _DetectedKindPreview(
            detectedKind: detectedKind,
            theme: theme,
            l10n: l10n,
          ),
        ] else if (kind.isCamera) ...[
          if (scannedPages.isEmpty)
            OutlinedButton.icon(
              onPressed: onChooseFile,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l10n.captureTakePhotoAction),
            )
          else
            _ScanPagesReview(
              pages: scannedPages,
              onAddPage: onChooseFile,
              onRemovePage: onRemoveScanPage,
            ),
        ] else if (kind.isFile) ...[
          if (file == null)
            OutlinedButton.icon(
              onPressed: onChooseFile,
              icon: const Icon(Icons.attach_file),
              label: Text(l10n.captureChooseFileAction),
            )
          else
            _ChosenFileCard(file: file!, onRemove: onRemoveFile),
        ],
        const SizedBox(height: 16),
        CustomTextField(
          label: l10n.captureOptionalTitleLabel,
          controller: titleController,
          validator: (_) => null,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        // En todos los tipos por igual, entre el título y la nota: es otro
        // dato opcional sobre lo que se guarda, no parte de qué se guarda.
        SpaceField(spaceId: spaceId, onChanged: onSpaceChanged),
        const SizedBox(height: 16),
        CustomTextField(
          label: l10n.captureOptionalNoteLabel,
          controller: noteController,
          validator: (_) => null,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: l10n.captureAction,
          isLoading: isSaving,
          onPressed: onSubmit,
        ),
      ],
    );
  }

  String _hintFor(_CaptureKind kind, AppLocalizations l10n) => switch (kind) {
    _CaptureKind.video => l10n.captureTypeVideoHint,
    _CaptureKind.post => l10n.captureTypePostHint,
    _CaptureKind.webPage => l10n.captureTypeWebPageHint,
    _ => '',
  };
}

/// La tira de páginas ya escaneadas, con una miniatura por foto —cada una
/// se puede quitar— y una tarjeta al final para sacar una más.
///
/// Aparece igual con una sola página que con varias: no hay un paso
/// intermedio donde "todavía es solo una foto" se vea distinto de "ya es un
/// documento de varias" — esa decisión se toma sola, en silencio, recién al
/// guardar (ver `_CaptureScreenState._fileToSubmit`), así que la interfaz
/// no tiene por qué anticiparla.
class _ScanPagesReview extends StatelessWidget {
  const _ScanPagesReview({
    required this.pages,
    required this.onAddPage,
    required this.onRemovePage,
  });

  final List<Uint8List> pages;
  final Future<void> Function() onAddPage;
  final ValueChanged<int> onRemovePage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.captureScanPagesCount(pages.length),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < pages.length; i++) ...[
                _ScanPageThumbnail(
                  bytes: pages[i],
                  onRemove: () => onRemovePage(i),
                ),
                const SizedBox(width: 8),
              ],
              _AddScanPageTile(onTap: onAddPage),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.captureScanHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Una página ya escaneada, con su botón para quitarla encima.
class _ScanPageThumbnail extends StatelessWidget {
  const _ScanPageThumbnail({required this.bytes, required this.onRemove});

  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SizedBox(
      width: 72,
      height: 96,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              width: 72,
              height: 96,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: theme.colorScheme.surface.withValues(alpha: 0.9),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: l10n.captureScanRemovePage,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: onRemove,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La tarjeta al final de la tira, para sacar una página más.
class _AddScanPageTile extends StatelessWidget {
  const _AddScanPageTile({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SizedBox(
      width: 72,
      height: 96,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Tooltip(
            message: l10n.captureScanAddPage,
            child: Icon(
              Icons.add_a_photo_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// La línea "se va a guardar como X", común a los pasos que arrancan de
/// texto —enlace o texto suelto—: los dos alimentan al mismo detector, así
/// que los dos merecen la misma honestidad sobre qué va a pasar.
///
/// Alto reservado aunque no haya nada que decir, para que el formulario no
/// salte al empezar a escribir.
class _DetectedKindPreview extends StatelessWidget {
  const _DetectedKindPreview({
    required this.detectedKind,
    required this.theme,
    required this.l10n,
  });

  final SourceKind? detectedKind;
  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final detected = detectedKind;

    return SizedBox(
      height: 24,
      child: detected == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    detected.icon,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.captureWillSaveAs(detected.label(l10n)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Lo que se ve cuando ya hay un archivo elegido.
///
/// Muestra el nombre, de qué formato es y cuánto pesa. Lo del formato no es
/// decoración: es el aviso temprano de que un `.pages` o un `.zip` se va a
/// guardar pero no va a dar texto, y de que un `.docx` renombrado a `.txt`
/// igual se reconoció bien.
class _ChosenFileCard extends StatelessWidget {
  const _ChosenFileCard({required this.file, required this.onRemove});

  final CapturedFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final format = file.format;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(format.sourceKind.icon),
        title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          l10n.captureFileSize(
            formatFileSize(file.sizeInBytes, l10n.localeName),
            describeFormat(format),
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.captureFileRemove,
          onPressed: onRemove,
        ),
      ),
    );
  }
}

/// [item] sin leerlo entero (F21): su tamaño, sus primeros bytes para
/// reconocer qué es, y cómo leerlo por partes al guardarlo. Con la propia
/// API del archivo soltado y no con su ruta: en la web no hay una ruta de
/// verdad, solo el contenido.
Future<CapturedFile> _capturedFileFrom(DropItem item) async {
  final size = await item.length();

  // Desde el principio, y se corta apenas alcanza: `break` cancela la
  // lectura, así que de un video de varios GB se lee una parte, no el video.
  final builder = BytesBuilder(copy: false);
  await for (final chunk in item.openRead()) {
    builder.add(chunk);
    if (builder.length >= CapturedFile.headBytes) break;
  }
  final read = builder.takeBytes();
  final head = read.length > CapturedFile.headBytes
      ? Uint8List.sublistView(read, 0, CapturedFile.headBytes)
      : read;

  return CapturedFile.onDisk(
    name: item.name,
    sizeInBytes: size,
    head: head,
    openRead: item.openRead,
  );
}
