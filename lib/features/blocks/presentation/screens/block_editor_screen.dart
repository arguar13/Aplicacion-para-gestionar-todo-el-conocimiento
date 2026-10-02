import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_template.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/inline_link_parser.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/blocks/presentation/providers/note_template_providers.dart';
import 'package:sinapsis/features/duplicates/presentation/providers/duplicate_providers.dart';
import 'package:sinapsis/features/duplicates/presentation/widgets/duplicate_warning_dialog.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/links/presentation/providers/link_providers.dart';
import 'package:sinapsis/features/links/presentation/widgets/broken_link_offer.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_clearance.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/notes/presentation/providers/derived_note_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/pick_item_dialog.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Crea o edita una nota armada con bloques: encabezados, párrafos, listas,
/// casilleros y citas, cada uno editable, reordenable y con su tipo propio.
///
/// Con [existingItem] en `null`, guarda un elemento nuevo con el título y los
/// bloques como su única forma de contenido. Con uno puesto, reemplaza el
/// título y la rendition de bloques del elemento —el resto (etiquetas,
/// espacio, vínculos) queda tal cual, porque `save()` sincroniza renditions y
/// etiquetas por separado (ver `_syncRenditions` en
/// `LibraryRepositoryImpl`)—.
///
/// [template] precarga los bloques y, tras el primer guardado, las
/// propiedades (F16): solo tiene sentido para una nota nueva —una que ya
/// existe tiene sus propios bloques y sus propias propiedades, que una
/// plantilla no debe pisar—.
///
/// Lo escrito se puede escuchar con el lector flotante (F25), sin resaltado:
/// el texto está en campos que se editan.
class BlockEditorScreen extends ConsumerStatefulWidget {
  const BlockEditorScreen({this.existingItem, this.template, super.key});

  final KnowledgeItem? existingItem;
  final NoteTemplate? template;

  @override
  ConsumerState<BlockEditorScreen> createState() => _BlockEditorScreenState();
}

class _BlockEntry {
  _BlockEntry(ContentBlock block)
    : controller = TextEditingController(text: block.text),
      type = block,
      key = UniqueKey();

  /// El bloque, solo para saber de qué tipo es y —en el caso del
  /// casillero— si está marcado. El texto vive en [controller], no acá: si
  /// viviera en los dos habría que decidir cuál manda cada vez que se
  /// escribe una letra.
  ContentBlock type;
  final TextEditingController controller;
  final Key key;

  /// El bloque como se guarda: con el texto de ahora y la fecha en que nació,
  /// que no cambia por escribir en él ni por cambiarle el tipo.
  ContentBlock toBlock() => switch (type) {
    ParagraphBlock(:final addedAt) => ContentBlock.paragraph(
      text: controller.text,
      addedAt: addedAt,
    ),
    HeadingBlock(:final level, :final addedAt) => ContentBlock.heading(
      text: controller.text,
      level: level,
      addedAt: addedAt,
    ),
    BulletItemBlock(:final addedAt) => ContentBlock.bulletItem(
      text: controller.text,
      addedAt: addedAt,
    ),
    NumberedItemBlock(:final addedAt) => ContentBlock.numberedItem(
      text: controller.text,
      addedAt: addedAt,
    ),
    ChecklistItemBlock(:final checked, :final addedAt) =>
      ContentBlock.checklistItem(
        text: controller.text,
        checked: checked,
        addedAt: addedAt,
      ),
    QuoteBlock(:final addedAt) => ContentBlock.quote(
      text: controller.text,
      addedAt: addedAt,
    ),
  };

  void dispose() => controller.dispose();
}

class _BlockEditorScreenState extends ConsumerState<BlockEditorScreen> {
  /// Cuánto se espera sin que se escriba nada antes de revisar si los
  /// `[[ ]]` tienen destino: una consulta por cada letra sería trabajo tirado.
  static const _linkCheckDelay = Duration(milliseconds: 500);

  /// El reloj, tomado al abrir la pantalla: los bloques que nacen mientras se
  /// edita se sellan con la hora inyectada, no con `DateTime.now()`.
  late final Clock _now;

  late final _titleController = TextEditingController(
    text: widget.existingItem?.title ?? '',
  );
  late final List<_BlockEntry> _blocks = _initialBlocks();
  var _saving = false;

  Timer? _linkCheckTimer;

  /// Se sube con cada revisión: una respuesta que llega después de que se
  /// pidió otra más nueva no la pisa.
  var _linkCheckGeneration = 0;

  /// Los títulos que la última revisión consultó, para no repetirla si lo que
  /// se escribió no tocó ningún `[[ ]]`.
  Set<String> _checkedTitles = const {};

  /// Los enlaces del texto que no tienen ninguna nota con ese título.
  List<InlineLinkMention> _missingLinks = const [];

  /// Los que el usuario dijo "ahora no": no se vuelven a ofrecer mientras dure
  /// esta edición.
  final _dismissedLinks = <String>{};
  var _creatingLink = false;

  /// Qué es para el lector flotante (F25): la nota que se edita, o esta
  /// pantalla si la nota todavía no existe —otra nota nueva es otra cosa—.
  late final _readableId =
      'editor:${widget.existingItem?.id ?? identityHashCode(this)}';

  /// Las líneas de la nota tal como está escrita, para leerla en voz alta
  /// (F25); `null` si cambió y hay que volver a armarlas. Mientras se
  /// escribe se arman un rato después de la última letra, no con cada una.
  List<ReadableSegment>? _readable;
  Timer? _readableTimer;

  List<_BlockEntry> _initialBlocks() {
    final existing = widget.existingItem?.renditions
        .whereType<TextRendition>()
        .where((r) => r.kind == RenditionKind.blocks)
        .firstOrNull;

    // La plantilla solo se usa al crear: una nota que ya existe trae sus
    // propios bloques, y una plantilla no los pisa.
    final blocks = existing != null
        ? decodeContentBlocks(existing.content)
        : widget.template?.blocks ?? const <ContentBlock>[];

    return (blocks.isEmpty
          ? [_BlockEntry(_newBlock())]
          : blocks.map(_BlockEntry.new).toList())
      ..forEach(_track);
  }

  /// Un párrafo vacío que nace ahora: lleva la fecha de su nacimiento. Es lo
  /// que permite saber, mucho después, qué notas crecieron esta semana. Los
  /// bloques que ya estaban en la nota conservan la suya —o ninguna, si son de
  /// antes de que se guardara—: abrir una nota vieja no los hace nuevos.
  ContentBlock _newBlock() => ContentBlock.paragraph(text: '', addedAt: _now());

  @override
  void initState() {
    super.initState();
    _now = ref.read(clockProvider);
    // El título también cuenta: un `[[ ]]` igual al propio título de una nota
    // que aún no se guardó no es un enlace a algo que falta.
    _titleController
      ..addListener(_scheduleLinkCheck)
      ..addListener(_scheduleReadable);
  }

  @override
  void dispose() {
    _linkCheckTimer?.cancel();
    _readableTimer?.cancel();
    _titleController.dispose();
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  void _track(_BlockEntry entry) => entry.controller
    ..addListener(_scheduleLinkCheck)
    ..addListener(_scheduleReadable);

  void _addBlockAfter(int index) {
    final entry = _BlockEntry(_newBlock());
    _track(entry);
    setState(() {
      _blocks.insert(index + 1, entry);
      _readable = null;
    });
  }

  void _removeBlock(int index) {
    if (_blocks.length <= 1) return;
    setState(() {
      _blocks.removeAt(index).dispose();
      _readable = null;
    });
    _scheduleLinkCheck();
  }

  void _scheduleReadable() {
    _readableTimer?.cancel();
    _readableTimer = Timer(_linkCheckDelay, () {
      if (mounted) setState(() => _readable = null);
    });
  }

  /// Cada bloque, un texto aparte: sus posiciones son las de su campo.
  List<ReadableSegment> _readableSegments() => [
    for (final (index, entry) in _blocks.indexed)
      ...buildReadableSegments(
        entry.controller.text,
        sourceKey: '$_readableId:$index',
        markdown: true,
      ),
  ];

  void _scheduleLinkCheck() {
    _linkCheckTimer?.cancel();
    _linkCheckTimer = Timer(_linkCheckDelay, _checkLinks);
  }

  /// Los `[[ ]]` del texto de ahora, sin el que se llama como la propia nota.
  List<InlineLinkMention> _currentMentions() {
    final own = normalizeLinkTitle(_titleController.text);
    return [
      for (final mention in extractInlineLinksFromBlocks([
        for (final entry in _blocks) entry.toBlock(),
      ]))
        if (mention.normalizedTitle != own) mention,
    ];
  }

  /// Revisa cuáles de los enlaces escritos no tienen nota. Sin ningún `[[ ]]`
  /// en el texto no toca la base: es lo que pasa casi siempre.
  Future<void> _checkLinks({bool force = false}) async {
    final mentions = _currentMentions();
    final wanted = {for (final m in mentions) m.normalizedTitle};
    if (!force &&
        wanted.length == _checkedTitles.length &&
        _checkedTitles.containsAll(wanted)) {
      return;
    }
    _checkedTitles = wanted;
    final generation = ++_linkCheckGeneration;

    if (wanted.isEmpty) {
      if (_missingLinks.isNotEmpty && mounted) {
        setState(() => _missingLinks = const []);
      }
      return;
    }

    final result = await ref
        .read(linkRepositoryProvider)
        .findMissingTitles(wanted, excludingItemId: widget.existingItem?.id);
    if (!mounted || generation != _linkCheckGeneration) return;

    // Si la consulta falló el repositorio ya lo informó: el aviso es una
    // ayuda, no un paso del guardado, y sin respuesta simplemente no se ofrece.
    final missing = result.getRight().toNullable() ?? const <String>{};
    setState(() {
      _missingLinks = [
        for (final mention in mentions)
          if (missing.contains(mention.normalizedTitle)) mention,
      ];
    });
  }

  /// Crea la nota que falta sin salir del editor: guardarla resuelve el enlace
  /// —y, si esta nota ya estaba guardada con ese enlace roto, crea su
  /// relación al instante; si es nueva o el enlace es nuevo, la relación nace
  /// al guardar esta nota, que ya encuentra el destino—.
  Future<void> _createLinkedNote(
    InlineLinkMention mention,
    NoteKind kind,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _creatingLink = true);

    final result = await ref
        .read(linkRepositoryProvider)
        .createNoteForLink(title: mention.title, kind: kind);
    if (!mounted) return;
    setState(() => _creatingLink = false);

    final failure = result.getLeft().toNullable();
    if (failure != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
      return;
    }
    await _checkLinks(force: true);
  }

  void _changeType(int index, ContentBlock Function(String text) build) {
    setState(() {
      final entry = _blocks[index];
      // Cambiarle el tipo a un bloque no lo hace nuevo: conserva su fecha.
      entry.type = build(
        entry.controller.text,
      ).copyWith(addedAt: entry.type.addedAt);
    });
  }

  /// [newIndex] llega ya ajustado por la remoción del elemento en
  /// [oldIndex] —eso es lo que hace `onReorderItem` de más respecto del
  /// `onReorder` obsoleto—, así que acá alcanza con mover sin ningún
  /// cálculo adicional.
  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final entry = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, entry);
      _readable = null;
    });
  }

  /// Abre el buscador de la biblioteca y, con lo elegido, inserta
  /// `[[Título]]` en el bloque [blockIndex] —en la posición del cursor, o
  /// al final si el campo nunca tuvo foco—.
  ///
  /// Solo escribe el texto: el vínculo de verdad (`Relations`, el que
  /// alimenta el Grafo) se crea recién al guardar —ver `_save`—, porque acá
  /// una nota nueva todavía no tiene el `id` propio con el que vincularse a
  /// nada.
  Future<void> _insertLink(int blockIndex) async {
    final itemId = await showDialog<String>(
      context: context,
      builder: (context) =>
          PickItemDialog(excludeItemId: widget.existingItem?.id),
    );
    if (itemId == null || !mounted) return;

    // `findById`, no `libraryItemsProvider`: ese es un `StreamProvider`
    // pensado para que un widget lo mire con `ref.watch` desde su propio
    // `build`, no para leerlo una sola vez desde un método imperativo como
    // este — hacerlo así deja una suscripción activa que `autoDispose`
    // nunca llega a soltar, y la próxima operación contra la base que
    // dependa de esa misma conexión se queda esperando para siempre.
    final result = await ref.read(libraryRepositoryProvider).findById(itemId);
    final target = result.getRight().toNullable();
    if (target == null || !mounted) return;

    final controller = _blocks[blockIndex].controller;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final insertion = '[[${target.title}]]';

    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, insertion),
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final title = _titleController.text.trim();
    final blocks = _blocks.map((e) => e.toBlock()).toList();
    final hasContent = blocks.any((b) => b.text.trim().isNotEmpty);

    if (title.isEmpty && !hasContent) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.blocksEmptyError)));
      return;
    }

    // El aviso de duplicado (F7) solo tiene sentido para una nota nueva:
    // editar una ya existente no crea ningún elemento con el que fusionar
    // —esa comparación la hace la detección continua al guardar, no este
    // diálogo (D7)—.
    final mergeWithItemId = widget.existingItem == null
        ? await checkForDuplicateBeforeSave(
            context: context,
            ref: ref,
            text: blocks.map((b) => b.text).join('\n'),
          )
        : null;
    if (!mounted) return;

    setState(() => _saving = true);

    final ids = ref.read(idGeneratorProvider);
    final clock = ref.read(clockProvider);
    final now = clock();
    final existing = widget.existingItem;
    final itemId = existing?.id ?? ids.next();

    // Si ya había una rendition de bloques, se conserva su id: es la misma
    // forma de contenido, actualizada, no una nueva que reemplaza a la
    // vieja.
    final existingBlocksRendition = existing?.renditions
        .whereType<TextRendition>()
        .where((r) => r.kind == RenditionKind.blocks)
        .firstOrNull;
    final existingBlocksId = existingBlocksRendition?.id;
    final blocksContent = encodeContentBlocks(blocks);

    final blocksRendition = Rendition.text(
      id: existingBlocksId ?? ids.next(),
      itemId: itemId,
      kind: RenditionKind.blocks,
      content: blocksContent,
      isPrimary: true,
      createdAt: now,
    );

    final item = existing == null
        ? KnowledgeItem(
            id: itemId,
            title: title.isEmpty ? l10n.blocksUntitled : title,
            source: Source(
              id: ids.next(),
              kind: SourceKind.manualNote,
              capturedAt: now,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [blocksRendition],
          )
        : existing.copyWith(
            title: title.isEmpty ? l10n.blocksUntitled : title,
            updatedAt: now,
            renditions: [
              ...existing.renditions.where(
                (r) => r.renditionKind != RenditionKind.blocks,
              ),
              blocksRendition,
            ],
          );

    final result = await ref.read(libraryRepositoryProvider).save(item);
    if (!mounted) return;

    final failure = result.getLeft().toNullable();
    if (failure != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
      return;
    }

    // Editar el contenido de un derivado lo hace suyo (F16, D3): solo al
    // editar una nota que ya existía, y solo si el texto de verdad cambió
    // —abrir y guardar sin tocar nada no cuenta—. `markEdited` no hace nada
    // si la nota no es un derivado, así que no hace falta consultar eso acá.
    if (existing != null && existingBlocksRendition?.content != blocksContent) {
      await ref.read(derivedNoteRepositoryProvider).markEdited(itemId);
    }

    // Las propiedades de la plantilla (F16) recién ahora, con el elemento ya
    // creado: `assignProperty` las pone una por una, por el mismo camino que
    // escribirlas a mano —crea el valor si hace falta, y no falla si de
    // algún modo ya estaba puesta—. Solo al crear: una nota que ya existía
    // no llega con `template` puesto.
    if (existing == null && widget.template != null) {
      final organize = ref.read(organizeRepositoryProvider);
      for (final property in widget.template!.properties) {
        await organize.assignProperty(
          itemId: itemId,
          definitionId: property.definitionId,
          value: property.value,
        );
      }
    }

    // Los `[[Título]]` del texto guardado ya son vínculos de verdad: `save`
    // los registra y crea la relación de los que tienen destino, dentro de
    // la misma transacción que guarda la nota. Se lee el texto guardado, no
    // un registro aparte de "qué se insertó": si alguien borra el `[[ ]]`
    // antes de guardar, no queda un enlace fantasma.
    //
    // La fusión va después, con los vínculos ya creados: reasigna a
    // `mergeWithItemId` cualquiera que `itemId` haya quedado teniendo —
    // reasignarlos primero sería trabajo de más para el mismo resultado.
    if (mergeWithItemId != null) {
      await ref.read(mergeDuplicateItemsUseCaseProvider)(
        keepItemId: mergeWithItemId,
        discardItemId: itemId,
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);
    // `canPop`: esta pantalla siempre llega apilada sobre otra —la captura
    // o el detalle—, pero un `pop()` a secas sobre la única ruta de la
    // pila revienta el `Navigator` en vez de no hacer nada. Mismo cuidado
    // que `CaptureScreen._submit`.
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  /// Guarda los bloques y las propiedades de la nota como una plantilla
  /// nueva (F16): las propiedades son las que la nota YA tenía al abrir esta
  /// pantalla —el editor de bloques no las cambia—, no las de este borrador.
  Future<void> _saveAsTemplate() async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _askTemplateName(context, l10n);
    if (name == null || name.trim().isEmpty || !mounted) return;

    final blocks = _blocks.map((e) => e.toBlock()).toList();
    final properties = [
      for (final property in widget.existingItem!.properties)
        TemplateProperty(
          definitionId: property.definitionId,
          definitionName: property.definitionName,
          value: property.value,
        ),
    ];

    await ref
        .read(noteTemplateRepositoryProvider)
        .create(name: name.trim(), blocks: blocks, properties: properties);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.blocksTemplateSaved(name.trim()))),
      );
  }

  Future<String?> _askTemplateName(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.blocksTemplateNameDialogTitle),
        content: TextField(
          key: const Key('template-name-field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('template-confirm-save'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.libraryViewsSaveAction),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final offered = [
      for (final mention in _missingLinks)
        if (!_dismissedLinks.contains(mention.normalizedTitle)) mention,
    ];
    final title = _titleController.text.trim();
    final readable = ReadableDocument(
      id: _readableId,
      title: title.isEmpty ? l10n.blocksUntitled : title,
      segments: _readable ??= _readableSegments(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingItem == null
              ? l10n.blocksNewTitle
              : l10n.blocksEditTitle,
        ),
        actions: [
          if (widget.existingItem != null)
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined),
              tooltip: l10n.blocksSaveAsTemplate,
              onPressed: _saveAsTemplate,
            ),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: l10n.detailSave,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ReadableRegion(
        document: readable,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: _blocks.length + 1,
                      // Sacar el foco antes de que arranque el arrastre: un
                      // `TextField` con foco activo es un `Element` que depende
                      // de su `FocusScope` (un `InheritedWidget`).
                      // `ReorderableListView` desmonta y remonta ese `Element`
                      // en otra posición del árbol para animar el
                      // reordenamiento, y si todavía tiene ese vínculo activo,
                      // Flutter revienta con "'_dependents.isEmpty': is not
                      // true" al desmontarlo —un bug conocido de la propia
                      // librería cuando el ítem arrastrado tiene un campo de
                      // texto enfocado—. Sin foco, no hay dependencia que
                      // sobreviva al desmontaje.
                      onReorderStart: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      onReorderItem: (oldIndex, newIndex) {
                        // El título ocupa el índice 0 y no participa del
                        // reordenamiento: se lo trata aparte, restando uno a
                        // cada índice de bloque real. `onReorderItem` —a
                        // diferencia de `onReorder`, obsoleto— ya entrega
                        // `newIndex` ajustado por la remoción del elemento en
                        // `oldIndex`.
                        if (oldIndex == 0 || newIndex == 0) return;
                        _reorder(oldIndex - 1, newIndex - 1);
                      },
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            key: const ValueKey('title'),
                            padding: const EdgeInsets.only(bottom: 16),
                            child: TextField(
                              controller: _titleController,
                              style: Theme.of(context).textTheme.headlineSmall,
                              decoration: InputDecoration(
                                hintText: l10n.blocksTitleHint,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                              ),
                            ),
                          );
                        }

                        final blockIndex = index - 1;
                        final entry = _blocks[blockIndex];
                        return _BlockRow(
                          key: entry.key,
                          entry: entry,
                          canDelete: _blocks.length > 1,
                          onChangeType: (build) =>
                              _changeType(blockIndex, build),
                          onDelete: () => _removeBlock(blockIndex),
                          onAddAfter: () => _addBlockAfter(blockIndex),
                          onInsertLink: () => _insertLink(blockIndex),
                        );
                      },
                    ),
                  ),
                  // Abajo de todo, con sus botones: el lector flotante se
                  // para encima (F25).
                  if (offered.isNotEmpty)
                    ReadAloudClearance(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: BrokenLinkOffer(
                          key: const ValueKey('brokenLinkOffer'),
                          title: offered.first.title,
                          moreCount: offered.length - 1,
                          busy: _creatingLink,
                          onCreate: (kind) =>
                              _createLinkedNote(offered.first, kind),
                          onDismiss: () => setState(
                            () => _dismissedLinks.add(
                              offered.first.normalizedTitle,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Una fila de bloque: el ícono de su tipo (que también abre el selector de
/// tipo), el texto, y las acciones de agregar/borrar.
class _BlockRow extends StatelessWidget {
  const _BlockRow({
    required this.entry,
    required this.canDelete,
    required this.onChangeType,
    required this.onDelete,
    required this.onAddAfter,
    required this.onInsertLink,
    super.key,
  });

  final _BlockEntry entry;
  final bool canDelete;
  final void Function(ContentBlock Function(String text) build) onChangeType;
  final VoidCallback onDelete;
  final VoidCallback onAddAfter;
  final VoidCallback onInsertLink;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final type = entry.type;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (type is ChecklistItemBlock)
            Checkbox(
              value: type.checked,
              onChanged: (value) => onChangeType(
                (text) => ContentBlock.checklistItem(
                  text: text,
                  checked: value ?? false,
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(_iconFor(type), size: 20),
              tooltip: l10n.blocksChangeType,
              onPressed: () => _pickType(context),
            ),
          Expanded(
            child: TextField(
              controller: entry.controller,
              maxLines: null,
              style: _styleFor(theme, type),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: _hintFor(l10n, type),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.link, size: 20),
            tooltip: l10n.blocksInsertLink,
            onPressed: onInsertLink,
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: l10n.blocksAddBlock,
            onPressed: onAddAfter,
          ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: l10n.blocksDeleteBlock,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  IconData _iconFor(ContentBlock type) => switch (type) {
    ParagraphBlock() => Icons.notes,
    HeadingBlock() => Icons.title,
    BulletItemBlock() => Icons.format_list_bulleted,
    NumberedItemBlock() => Icons.format_list_numbered,
    ChecklistItemBlock() => Icons.check_box_outlined,
    QuoteBlock() => Icons.format_quote,
  };

  String _hintFor(AppLocalizations l10n, ContentBlock type) => switch (type) {
    HeadingBlock() => l10n.blocksHeadingHint,
    BulletItemBlock() || NumberedItemBlock() => l10n.blocksListItemHint,
    QuoteBlock() => l10n.blocksQuoteHint,
    ChecklistItemBlock() || ParagraphBlock() => l10n.blocksParagraphHint,
  };

  TextStyle? _styleFor(ThemeData theme, ContentBlock type) => switch (type) {
    HeadingBlock(:final level) =>
      level <= 1 ? theme.textTheme.headlineSmall : theme.textTheme.titleLarge,
    QuoteBlock() => theme.textTheme.bodyLarge?.copyWith(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.onSurfaceVariant,
    ),
    ParagraphBlock() ||
    BulletItemBlock() ||
    NumberedItemBlock() ||
    ChecklistItemBlock() => theme.textTheme.bodyLarge,
  };

  Future<void> _pickType(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    final choice = await showModalBottomSheet<ContentBlock Function(String)>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notes),
              title: Text(l10n.blocksTypeParagraph),
              onTap: () => Navigator.of(
                context,
              ).pop((String text) => ContentBlock.paragraph(text: text)),
            ),
            ListTile(
              leading: const Icon(Icons.title),
              title: Text(l10n.blocksTypeHeading),
              onTap: () => Navigator.of(
                context,
              ).pop((String text) => ContentBlock.heading(text: text)),
            ),
            ListTile(
              leading: const Icon(Icons.format_list_bulleted),
              title: Text(l10n.blocksTypeBulletItem),
              onTap: () => Navigator.of(
                context,
              ).pop((String text) => ContentBlock.bulletItem(text: text)),
            ),
            ListTile(
              leading: const Icon(Icons.format_list_numbered),
              title: Text(l10n.blocksTypeNumberedItem),
              onTap: () => Navigator.of(
                context,
              ).pop((String text) => ContentBlock.numberedItem(text: text)),
            ),
            ListTile(
              leading: const Icon(Icons.check_box_outlined),
              title: Text(l10n.blocksTypeChecklistItem),
              onTap: () => Navigator.of(
                context,
              ).pop((String text) => ContentBlock.checklistItem(text: text)),
            ),
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: Text(l10n.blocksTypeQuote),
              onTap: () => Navigator.of(
                context,
              ).pop((String text) => ContentBlock.quote(text: text)),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    onChangeType(choice);
  }
}
