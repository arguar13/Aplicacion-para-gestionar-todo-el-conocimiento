import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/links/domain/entities/broken_link.dart';
import 'package:sinapsis/features/links/presentation/providers/link_providers.dart';
import 'package:sinapsis/features/links/presentation/widgets/note_kind_chips.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los `[[enlaces]]` sin nota de toda la bóveda, con la creación en lote.
///
/// Cada fila es un título, no una nota: crear la nota que falta completa el
/// enlace en todas las notas que lo escriben a la vez. Cada fila se despliega
/// para ver —y abrir— esas notas, porque un enlace roto no siempre es una nota
/// que falta: a veces es un error de tipeo, y ahí lo que hay que hacer es
/// corregir el texto, no crear una nota con el nombre equivocado.
class BrokenLinksScreen extends ConsumerStatefulWidget {
  const BrokenLinksScreen({super.key});

  @override
  ConsumerState<BrokenLinksScreen> createState() => _BrokenLinksScreenState();
}

class _BrokenLinksScreenState extends ConsumerState<BrokenLinksScreen> {
  /// Los títulos marcados, normalizados.
  final _selected = <String>{};
  var _kind = NoteKind.living;
  var _creating = false;

  Future<void> _createSelected(List<BrokenLink> links) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final titles = [
      for (final link in links)
        if (_selected.contains(link.normalizedTitle)) link.title,
    ];
    setState(() => _creating = true);

    final result = await ref
        .read(linkRepositoryProvider)
        .createNotesForLinks(titles, kind: _kind);
    if (!mounted) return;
    setState(() => _creating = false);

    final failure = result.getLeft().toNullable();
    messenger.hideCurrentSnackBar();
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(failure.localizedMessage(l10n))),
      );
      return;
    }

    setState(_selected.clear);
    final created = result.getRight().toNullable() ?? 0;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.brokenLinksCreated(created))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final links = ref.watch(brokenLinksProvider);
    final items = links.valueOrNull ?? const <BrokenLink>[];
    // Un título que se acaba de crear desaparece de la lista: no puede quedar
    // marcado.
    final selected = _selected.intersection({
      for (final link in items) link.normalizedTitle,
    });
    final allSelected = items.isNotEmpty && selected.length == items.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.brokenLinksTitle),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: _creating
                  ? null
                  : () => setState(() {
                      _selected.clear();
                      if (!allSelected) {
                        _selected.addAll(items.map((l) => l.normalizedTitle));
                      }
                    }),
              child: Text(
                allSelected
                    ? l10n.brokenLinksClearSelection
                    : l10n.brokenLinksSelectAll,
              ),
            ),
        ],
      ),
      body: links.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _CenteredMessage(l10n.brokenLinksLoadError),
        data: (items) => items.isEmpty
            ? _CenteredMessage(l10n.brokenLinksEmpty)
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: items.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) return _Hint(l10n.brokenLinksHint);
                        final link = items[index - 1];
                        return _BrokenLinkTile(
                          link: link,
                          selected: selected.contains(link.normalizedTitle),
                          enabled: !_creating,
                          onSelected: (value) => setState(() {
                            if (value) {
                              _selected.add(link.normalizedTitle);
                            } else {
                              _selected.remove(link.normalizedTitle);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  if (selected.isNotEmpty)
                    _CreateBar(
                      count: selected.length,
                      kind: _kind,
                      busy: _creating,
                      onKindChanged: (kind) => setState(() => _kind = kind),
                      onCreate: () => _createSelected(items),
                    ),
                ],
              ),
      ),
    );
  }
}

class _BrokenLinkTile extends StatelessWidget {
  const _BrokenLinkTile({
    required this.link,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final BrokenLink link;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ExpansionTile(
      key: PageStorageKey(link.normalizedTitle),
      leading: Checkbox(
        value: selected,
        onChanged: enabled ? (value) => onSelected(value ?? false) : null,
      ),
      title: Text('[[${link.title}]]'),
      subtitle: Text(l10n.brokenLinksWrittenIn(link.sources.length)),
      children: [
        for (final source in link.sources)
          ListTile(
            dense: true,
            leading: const Icon(Icons.description_outlined),
            title: Text(source.title),
            onTap: () => context.push(RoutePaths.itemDetail(source.itemId)),
          ),
      ],
    );
  }
}

class _CreateBar extends StatelessWidget {
  const _CreateBar({
    required this.count,
    required this.kind,
    required this.busy,
    required this.onKindChanged,
    required this.onCreate,
  });

  final int count;
  final NoteKind kind;
  final bool busy;
  final ValueChanged<NoteKind> onKindChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NoteKindChips(
                selected: kind,
                onChanged: busy ? null : onKindChanged,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : onCreate,
                  child: Text(l10n.brokenLinksCreateSelected(count)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
