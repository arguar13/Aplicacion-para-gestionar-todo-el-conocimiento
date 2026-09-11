import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_query_notifier.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_item_card.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(libraryQueryNotifierProvider);
    final items = ref.watch(libraryItemsProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        actions: [
          const _LanguageToggleButton(),
          const _ThemeModeToggleButton(),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: l10n.lockVaultTooltip,
            // Ni navegación manual ni conocimiento del router: solo se le
            // avisa al controlador de la bóveda, y el router reacciona.
            onPressed: () =>
                ref.read(vaultSessionControllerProvider.notifier).lock(),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(112),
          child: _SearchAndFilters(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
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
        data: (list) =>
            list.isEmpty ? _EmptyState(query: query) : _ItemList(items: list),
      ),
    );
  }
}

class _SearchAndFilters extends ConsumerWidget {
  const _SearchAndFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(libraryQueryNotifierProvider);

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
      ],
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({required this.items});

  final List<KnowledgeItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // Sitio para que el botón flotante no tape la última fila.
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return LibraryItemCard(
          item: item,
          onTap: () => context.push('${RoutePaths.library}/${item.id}'),
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
