import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/features/export/domain/entities/notebooklm_export_result.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_query_notifier.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_item_card.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La pantalla principal: todo lo guardado, con búsqueda y filtros.
///
/// Reemplaza al panel de demostración que había antes. Aquel traía una barra
/// de navegación con destinos "Perfil" y "Ajustes" que no llevaban a ninguna
/// parte; se quitó en vez de conservarla vacía, porque una navegación cuyos
/// botones no hacen nada enseña a desconfiar de los que sí funcionan. Vuelve
/// cuando haya secciones de verdad a las que ir.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  /// Vacío significa "no está en modo selección", no "seleccionó todo y
  /// después nada". Entrar al modo pasando por acá, y no por un booleano
  /// aparte, evita el estado imposible de "modo activo, pero no se sabe con
  /// qué arrancó".
  final Set<String> _selectedIds = {};
  var _selectionModeActive = false;

  @override
  void initState() {
    super.initState();

    // Retoma lo que quedó a medias en sesiones anteriores: alguien pudo
    // capturar cinco enlaces sin conexión y cerrar la app. Al volver, eso se
    // completa solo, sin que haya que acordarse de pedirlo.
    //
    // Diferido al post-frame por la regla de Riverpod de no tocar providers
    // mientras se construye el árbol de widgets.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(processingQueueProvider.notifier).enqueuePending());
    });
  }

  void _enterSelectionMode(String itemId) {
    setState(() {
      _selectionModeActive = true;
      _selectedIds.add(itemId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionModeActive = false;
      _selectedIds.clear();
    });
  }

  void _setSelected(String itemId, {required bool selected}) {
    setState(() {
      if (selected) {
        _selectedIds.add(itemId);
      } else {
        _selectedIds.remove(itemId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(libraryQueryNotifierProvider);
    final items = ref.watch(libraryItemsProvider(query));

    // La fila de etiquetas solo ocupa lugar cuando hay algo que mostrar en
    // ella: sin esto, una biblioteca sin una sola etiqueta puesta reservaría
    // el alto igual, dejando una franja vacía debajo de los filtros de tipo.
    final hasTags =
        (ref.watch(allTagsProvider).valueOrNull ?? const []).isNotEmpty;
    final loadedItems = items.valueOrNull ?? const <KnowledgeItem>[];

    return Scaffold(
      appBar: _selectionModeActive
          ? _SelectionAppBar(
              selectedCount: _selectedIds.length,
              onCancel: _exitSelectionMode,
              onExport: () => _exportSelection(context, loadedItems),
            )
          : AppBar(
              title: Text(l10n.libraryTitle),
              actions: [
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: l10n.librarySelectTooltip,
                  // Sin nada elegido todavía: entrar al modo alcanza, no
                  // hace falta que el primer toque también elija algo.
                  onPressed: () => setState(() => _selectionModeActive = true),
                ),
                const _LanguageToggleButton(),
                const _ThemeModeToggleButton(),
                IconButton(
                  icon: const Icon(Icons.mic_none_outlined),
                  tooltip: l10n.libraryTranscriptionModelTooltip,
                  onPressed: () => context.push(RoutePaths.transcriptionModel),
                ),
                IconButton(
                  icon: const Icon(Icons.backup_outlined),
                  tooltip: l10n.libraryVaultBackupTooltip,
                  onPressed: () => context.push(RoutePaths.vaultBackup),
                ),
                IconButton(
                  icon: const Icon(Icons.lock_outline),
                  tooltip: l10n.lockVaultTooltip,
                  // Ni navegación manual ni conocimiento del router: solo se
                  // le avisa al controlador de la bóveda, y el router
                  // reacciona.
                  onPressed: () =>
                      ref.read(vaultSessionControllerProvider.notifier).lock(),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(hasTags ? 216 : 168),
                child: const _SearchAndFilters(),
              ),
            ),
      floatingActionButton: _selectionModeActive
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(RoutePaths.capture),
              icon: const Icon(Icons.add),
              label: Text(l10n.captureAction),
            ),
      body: items.when(
        // Solo se ve en el primer instante: después, el stream re-emite sin
        // volver a pasar por "cargando", así que la lista no parpadea cada
        // vez que se guarda algo.
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _LibraryError(error: error),
        data: (list) => list.isEmpty
            ? _EmptyState(query: query)
            : _ItemList(
                items: list,
                selectionMode: _selectionModeActive,
                selectedIds: _selectedIds,
                onLongPressItem: _enterSelectionMode,
                onSelectedChanged: _setSelected,
              ),
      ),
    );
  }

  Future<void> _exportSelection(
    BuildContext context,
    List<KnowledgeItem> allItems,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = allItems
        .where((item) => _selectedIds.contains(item.id))
        .toList();

    final result = await ref.read(exportNotebookLmPackageUseCaseProvider)(
      selected,
    );
    if (!context.mounted) return;

    result.match(
      (failure) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(failure.localizedMessage(l10n))),
          );
      },
      (exportResult) {
        // Cancelar el selector de carpeta no es un error: se deja el modo
        // de selección tal como estaba, por si quiere intentarlo de nuevo.
        if (exportResult is! NotebookLmExportCompleted) return;

        setState(() {
          _selectionModeActive = false;
          _selectedIds.clear();
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                l10n.libraryExportPackageSaved(
                  exportResult.fileCount,
                  exportResult.directoryPath,
                ),
              ),
            ),
          );
      },
    );
  }
}

/// La barra superior mientras se seleccionan elementos: cuenta cuántos hay,
/// deja cancelar y ofrece la única acción que tiene sentido en este modo.
class _SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SelectionAppBar({
    required this.selectedCount,
    required this.onCancel,
    required this.onExport,
  });

  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback onExport;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l10n.libraryExitSelectionTooltip,
        onPressed: onCancel,
      ),
      title: Text(l10n.librarySelectedCount(selectedCount)),
      actions: [
        IconButton(
          icon: const Icon(Icons.upload_file_outlined),
          tooltip: l10n.libraryExportSelectedTooltip,
          // Deshabilitado en cero: pedirle al caso de uso una lista vacía
          // solo volvería con el mismo fallo de validación, sin que el
          // usuario haya podido hacer nada distinto para evitarlo.
          onPressed: selectedCount == 0 ? null : onExport,
        ),
      ],
    );
  }
}

class _SearchAndFilters extends ConsumerWidget {
  const _SearchAndFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(libraryQueryNotifierProvider);
    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <Tag>[];
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            onChanged: ref.read(libraryQueryNotifierProvider.notifier).search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.librarySearchHint,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            children: [
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(l10n.spacesNewAction),
                onPressed: () => _createSpace(context, ref),
              ),
              const SizedBox(width: 8),
              for (final space in spaces) ...[
                GestureDetector(
                  onLongPress: () => _manageSpace(context, ref, space),
                  child: FilterChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(space.name),
                    selected: query.spaceId == space.id,
                    onSelected: (_) => ref
                        .read(libraryQueryNotifierProvider.notifier)
                        .selectSpace(space.id),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final kind in SourceKind.values) ...[
                FilterChip(
                  avatar: Icon(kind.icon, size: 18),
                  label: Text(kind.label(l10n)),
                  selected: query.sourceKinds.contains(kind),
                  onSelected: (_) => ref
                      .read(libraryQueryNotifierProvider.notifier)
                      .toggleSourceKind(kind),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        // Sin nada en el vocabulario todavía, esta fila no tiene qué
        // mostrar: ocuparía espacio para decir "no hay etiquetas por las que
        // filtrar", que no es información que alguien necesite ver siempre.
        if (tags.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                for (final tag in tags) ...[
                  FilterChip(
                    avatar: const Icon(Icons.label_outline, size: 18),
                    label: Text(tag.name),
                    selected: query.tagIds.contains(tag.id),
                    onSelected: (_) => ref
                        .read(libraryQueryNotifierProvider.notifier)
                        .toggleTagId(tag.id),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _createSpace(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.spacesNewTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.spacesNameHint),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.spacesNewAction),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    final result = await ref.read(organizeRepositoryProvider).createSpace(name);
    if (!context.mounted) return;

    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      // El espacio recién creado queda elegido: quien lo crea casi siempre
      // lo hace para empezar a usarlo enseguida, no solo para que exista.
      (space) =>
          ref.read(libraryQueryNotifierProvider.notifier).selectSpace(space.id),
    );
  }

  Future<void> _manageSpace(
    BuildContext context,
    WidgetRef ref,
    Space space,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    final action = await showDialog<_SpaceAction>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(space.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_SpaceAction.rename),
            child: Text(l10n.spacesRenameAction),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_SpaceAction.delete),
            child: Text(l10n.spacesDeleteAction),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case _SpaceAction.rename:
        await _renameSpace(context, ref, space);
      case _SpaceAction.delete:
        await _deleteSpace(context, ref, space);
    }
  }

  Future<void> _renameSpace(
    BuildContext context,
    WidgetRef ref,
    Space space,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: space.name);

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.spacesRenameAction),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.spacesNameHint),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.detailSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    final result = await ref
        .read(organizeRepositoryProvider)
        .renameSpace(id: space.id, name: name);
    if (!context.mounted) return;

    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) {},
    );
  }

  Future<void> _deleteSpace(
    BuildContext context,
    WidgetRef ref,
    Space space,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.spacesDeleteConfirm(space.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.spacesDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Si era el espacio que se estaba mirando, hay que salir de esa vista:
    // de lo contrario la biblioteca quedaría filtrando por un espacio que
    // ya no existe, mostrando siempre una lista vacía sin decir por qué.
    final notifier = ref.read(libraryQueryNotifierProvider.notifier);
    if (ref.read(libraryQueryNotifierProvider).spaceId == space.id) {
      notifier.selectSpace(null);
    }

    await ref.read(organizeRepositoryProvider).deleteSpace(space.id);
  }
}

enum _SpaceAction { rename, delete }

class _ItemList extends StatelessWidget {
  const _ItemList({
    required this.items,
    required this.selectionMode,
    required this.selectedIds,
    required this.onLongPressItem,
    required this.onSelectedChanged,
  });

  final List<KnowledgeItem> items;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<String> onLongPressItem;
  final void Function(String itemId, {required bool selected})
  onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // Sitio para que el botón flotante no tape la última fila, y aire a
      // los costados: cada fila es su propia tarjeta, no un renglón que
      // ocupa el ancho completo hasta el borde de la pantalla.
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return LibraryItemCard(
          item: item,
          onTap: () => context.push('${RoutePaths.library}/${item.id}'),
          onLongPress: () => onLongPressItem(item.id),
          selectionMode: selectionMode,
          selected: selectedIds.contains(item.id),
          onSelectedChanged: (value) =>
              onSelectedChanged(item.id, selected: value),
        );
      },
    );
  }
}

/// Qué mostrar cuando no hay nada que mostrar.
///
/// Son tres situaciones distintas y confundirlas desorienta: una biblioteca
/// recién estrenada, una búsqueda sin coincidencias y unos filtros demasiado
/// estrechos. La última además ofrece la salida, porque el usuario puede no
/// darse cuenta de que dejó un filtro puesto.
class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.query});

  final LibraryQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final notifier = ref.read(libraryQueryNotifierProvider.notifier);

    final (icon, title, message, action) = switch (query) {
      _ when query.hasSearchText => (
        Icons.search_off,
        l10n.librarySearchEmpty(query.searchText!),
        null,
        null,
      ),
      _ when notifier.hasActiveFilters => (
        Icons.filter_alt_off_outlined,
        l10n.libraryFilterEmpty,
        null,
        (l10n.libraryClearFilters, notifier.clearFilters),
      ),
      _ => (
        Icons.inbox_outlined,
        l10n.emptyLibraryTitle,
        l10n.emptyLibraryMessage,
        null,
      ),
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 24),
              Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: action.$2,
                  child: Text(action.$1),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // El repositorio manda los fallos por el stream como `Failure`, así que
    // se traducen por tipo. Cualquier otra cosa cae en el mensaje genérico:
    // mostrar el texto crudo de una excepción no le dice nada a nadie.
    final message = error is Failure
        ? (error as Failure).localizedMessage(l10n)
        : l10n.globalErrorUnexpected;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Cicla sistema -> claro -> oscuro -> sistema. El ícono refleja el modo
/// actual; el cambio persiste solo (ver `ThemeModeNotifier`).
class _ThemeModeToggleButton extends ConsumerWidget {
  const _ThemeModeToggleButton();

  static const _cycle = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];

  IconData _iconFor(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto,
    ThemeMode.light => Icons.light_mode,
    ThemeMode.dark => Icons.dark_mode,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeNotifierProvider);

    return IconButton(
      icon: Icon(_iconFor(themeMode)),
      tooltip: AppLocalizations.of(context)!.themeModeTooltip,
      onPressed: () {
        final next = _cycle[(_cycle.indexOf(themeMode) + 1) % _cycle.length];
        ref.read(themeModeNotifierProvider.notifier).setThemeMode(next);
      },
    );
  }
}

/// Cicla sistema -> Español -> English -> sistema. Muestra el código del
/// idioma *efectivo* (resuelve "sistema" a es/en real), no un ícono ambiguo.
class _LanguageToggleButton extends ConsumerWidget {
  const _LanguageToggleButton();

  static const _cycle = <Locale?>[null, Locale('es'), Locale('en')];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(localeNotifierProvider);
    final effective = ref.watch(effectiveLocaleProvider);

    return IconButton(
      icon: Text(
        effective.languageCode.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      tooltip: AppLocalizations.of(context)!.languageTooltip,
      onPressed: () {
        final next = _cycle[(_cycle.indexOf(preference) + 1) % _cycle.length];
        ref.read(localeNotifierProvider.notifier).setLocale(next);
      },
    );
  }
}
