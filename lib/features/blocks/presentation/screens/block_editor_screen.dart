import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
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
class BlockEditorScreen extends ConsumerStatefulWidget {
  const BlockEditorScreen({this.existingItem, super.key});

  final KnowledgeItem? existingItem;

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

  ContentBlock toBlock() => switch (type) {
    ParagraphBlock() => ContentBlock.paragraph(text: controller.text),
    HeadingBlock(:final level) => ContentBlock.heading(
      text: controller.text,
      level: level,
    ),
    BulletItemBlock() => ContentBlock.bulletItem(text: controller.text),
    NumberedItemBlock() => ContentBlock.numberedItem(text: controller.text),
    ChecklistItemBlock(:final checked) => ContentBlock.checklistItem(
      text: controller.text,
      checked: checked,
    ),
    QuoteBlock() => ContentBlock.quote(text: controller.text),
  };

  void dispose() => controller.dispose();
}

class _BlockEditorScreenState extends ConsumerState<BlockEditorScreen> {
  late final _titleController = TextEditingController(
    text: widget.existingItem?.title ?? '',
  );
  late final List<_BlockEntry> _blocks = _initialBlocks();
  var _saving = false;

  List<_BlockEntry> _initialBlocks() {
    final existing = widget.existingItem?.renditions
        .whereType<TextRendition>()
        .where((r) => r.kind == RenditionKind.blocks)
        .firstOrNull;

    final blocks = existing == null
        ? const <ContentBlock>[]
        : decodeContentBlocks(existing.content);

    if (blocks.isEmpty) {
      return [_BlockEntry(const ContentBlock.paragraph(text: ''))];
    }
    return blocks.map(_BlockEntry.new).toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  void _addBlockAfter(int index) {
    setState(() {
      _blocks.insert(
        index + 1,
        _BlockEntry(const ContentBlock.paragraph(text: '')),
      );
    });
  }

  void _removeBlock(int index) {
    if (_blocks.length <= 1) return;
    setState(() {
      _blocks.removeAt(index).dispose();
    });
  }

  void _changeType(int index, ContentBlock Function(String text) build) {
    setState(() {
      _blocks[index].type = build(_blocks[index].controller.text);
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

    setState(() => _saving = true);

    final ids = ref.read(idGeneratorProvider);
    final clock = ref.read(clockProvider);
    final now = clock();
    final existing = widget.existingItem;
    final itemId = existing?.id ?? ids.next();

    // Si ya había una rendition de bloques, se conserva su id: es la misma
    // forma de contenido, actualizada, no una nueva que reemplaza a la
    // vieja.
    final existingBlocksId = existing?.renditions
        .whereType<TextRendition>()
        .where((r) => r.kind == RenditionKind.blocks)
        .firstOrNull
        ?.id;

    final blocksRendition = Rendition.text(
      id: existingBlocksId ?? ids.next(),
      itemId: itemId,
      kind: RenditionKind.blocks,
      content: encodeContentBlocks(blocks),
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

    // Cada `[[Título]]` que sigue apareciendo en el texto final —lo haya
    // escrito `_insertLink` o a mano— se convierte en un vínculo de
    // verdad. Se escanea el texto guardado, no un registro aparte de "qué
    // se insertó": si alguien borra el `[[ ]]` antes de guardar, no debe
    // quedar un vínculo fantasma sin ningún enlace visible que lo explique.
    //
    // `list()`, no `libraryItemsProvider`: ver el comentario de
    // `_insertLink` sobre por qué un `StreamProvider` no es para leerse una
    // sola vez desde un método imperativo.
    final linkedTitles = extractLinkedTitles(blocks);
    if (linkedTitles.isNotEmpty) {
      final allItems =
          (await ref.read(libraryRepositoryProvider).list(const LibraryQuery()))
              .getRight()
              .toNullable() ??
          const <KnowledgeItem>[];
      final organize = ref.read(organizeRepositoryProvider);
      for (final other in allItems) {
        if (other.id == itemId) continue;
        if (!linkedTitles.contains(other.title.trim().toLowerCase())) continue;
        await organize.createRelation(
          fromItemId: itemId,
          toItemId: other.id,
          kind: RelationKind.relatedTo,
        );
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    // `canPop`: esta pantalla siempre llega apilada sobre otra —la captura
    // o el detalle—, pero un `pop()` a secas sobre la única ruta de la
    // pila revienta el `Navigator` en vez de no hacer nada. Mismo cuidado
    // que `CaptureScreen._submit`.
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingItem == null
              ? l10n.blocksNewTitle
              : l10n.blocksEditTitle,
        ),
        actions: [
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _blocks.length + 1,
              // Sacar el foco antes de que arranque el arrastre: un
              // `TextField` con foco activo es un `Element` que depende de
              // su `FocusScope` (un `InheritedWidget`). `ReorderableListView`
              // desmonta y remonta ese `Element` en otra posición del árbol
              // para animar el reordenamiento, y si todavía tiene ese
              // vínculo activo, Flutter revienta con
              // "'_dependents.isEmpty': is not true" al desmontarlo —un bug
              // conocido de la propia librería cuando el ítem arrastrado
              // tiene un campo de texto enfocado—. Sin foco, no hay
              // dependencia que sobreviva al desmontaje.
              onReorderStart: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              onReorderItem: (oldIndex, newIndex) {
                // El título ocupa el índice 0 y no participa del
                // reordenamiento: se lo trata aparte, restando uno a cada
                // índice de bloque real. `onReorderItem` —a diferencia de
                // `onReorder`, obsoleto— ya entrega `newIndex` ajustado por
                // la remoción del elemento en `oldIndex`.
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
                  onChangeType: (build) => _changeType(blockIndex, build),
                  onDelete: () => _removeBlock(blockIndex),
                  onAddAfter: () => _addBlockAfter(blockIndex),
                  onInsertLink: () => _insertLink(blockIndex),
                );
              },
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

final _linkPattern = RegExp(r'\[\[(.+?)\]\]');

/// Los títulos —sin distinguir mayúsculas, recortados— que aparecen entre
/// `[[ ]]` en cualquier bloque.
///
/// Función aparte de `_save`, y no un método privado del `State`, para que
/// se pueda probar sola con datos concretos, sin montar el editor entero:
/// es la única parte de la extracción de enlaces con lógica real, el resto
/// es E/S contra la base.
Set<String> extractLinkedTitles(List<ContentBlock> blocks) {
  final titles = <String>{};
  for (final block in blocks) {
    for (final match in _linkPattern.allMatches(block.text)) {
      final title = match.group(1)!.trim().toLowerCase();
      if (title.isNotEmpty) titles.add(title);
    }
  }
  return titles;
}
