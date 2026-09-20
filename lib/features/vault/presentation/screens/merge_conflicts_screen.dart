import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/vault/domain/entities/merge_conflict.dart';
import 'package:sinapsis/features/vault/presentation/providers/merge_conflict_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los cambios que una fusión no pudo decidir sola (F11): el mismo dato,
/// modificado en las dos bóvedas a la vez.
///
/// Nada se pisó en silencio: la versión más reciente quedó en uso y la otra se
/// guardó. Acá se elige cuál queda; elegir la que ya está en uso solo da el
/// cambio por revisado. Lo que se elige se guarda como una edición tuya, así
/// que una fusión posterior no lo vuelve a marcar.
class MergeConflictsScreen extends ConsumerWidget {
  const MergeConflictsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final conflicts = ref.watch(pendingMergeConflictsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.conflictsTitle)),
      body: conflicts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (items) => items.isEmpty
            ? _Empty(l10n: l10n)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    l10n.conflictsIntro,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final conflict in items) _ConflictCard(conflict),
                ],
              ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.conflictsEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.conflictsEmptyBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictCard extends ConsumerWidget {
  const _ConflictCard(this.conflict);

  final MergeConflict conflict;

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    MergeConflictChoice choice,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(mergeConflictRepositoryProvider)
        .resolve(conflict.id, choice);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.match(
              (failure) => failure.localizedMessage(l10n),
              (_) => l10n.conflictsResolved,
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => context.push(RoutePaths.itemDetail(conflict.itemId)),
              child: Text(
                conflict.itemTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              conflictFieldLabel(l10n, conflict),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            if (conflict.itemInTrash)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.conflictsItemInTrash,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _VersionBox(
              side: l10n.conflictsSideLocal,
              conflict: conflict,
              version: conflict.local,
              onChoose: () =>
                  _resolve(context, ref, MergeConflictChoice.keepLocal),
            ),
            const SizedBox(height: 8),
            _VersionBox(
              side: l10n.conflictsSideIncoming,
              conflict: conflict,
              version: conflict.incoming,
              onChoose: () =>
                  _resolve(context, ref, MergeConflictChoice.useIncoming),
              // Sin la otra versión no hay a qué pasar.
              enabled:
                  !(conflict.kind == MergeConflictKind.text &&
                      conflict.incoming.text == null),
            ),
            if (conflict.canKeepBoth) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      _resolve(context, ref, MergeConflictChoice.keepBoth),
                  child: Text(l10n.conflictsKeepBoth),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Una de las dos versiones, con lo que se puede hacer con ella.
class _VersionBox extends StatelessWidget {
  const _VersionBox({
    required this.side,
    required this.conflict,
    required this.version,
    required this.onChoose,
    this.enabled = true,
  });

  final String side;
  final MergeConflict conflict;
  final MergeConflictVersion version;
  final VoidCallback onChoose;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final at = version.at;
    final device = version.deviceId;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: version.inUse
            ? scheme.primaryContainer.withValues(alpha: 0.4)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: version.inUse ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(side, style: theme.textTheme.titleSmall)),
              if (version.inUse)
                Chip(
                  label: Text(l10n.conflictsInUse),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (at != null || device != null)
            Text(
              l10n.conflictsVersionMeta(
                device == null ? '' : _shortDevice(device),
                at == null
                    ? ''
                    : MaterialLocalizations.of(context).formatMediumDate(at),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          Text(conflictVersionText(l10n, conflict, version)),
          if (conflict.kind == MergeConflictKind.text && version.length != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.conflictsTextLength(version.length!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: enabled ? onChoose : null,
              child: Text(
                version.inUse ? l10n.conflictsKeepThis : l10n.conflictsUseThis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Un identificador de dispositivo es un UUID: se muestran los primeros
  /// caracteres, que alcanzan para distinguir dos.
  static String _shortDevice(String id) =>
      id.length <= 8 ? id : id.substring(0, 8);
}

/// El nombre del campo del conflicto, para el usuario.
String conflictFieldLabel(AppLocalizations l10n, MergeConflict conflict) {
  if (conflict.kind == MergeConflictKind.text) return l10n.conflictsFieldText;
  return switch (conflict.fieldName) {
    EntryField.title => l10n.conflictsFieldTitle,
    EntryField.subtitle => l10n.conflictsFieldSubtitle,
    EntryField.notes => l10n.conflictsFieldNotes,
    EntryField.spaceId => l10n.conflictsFieldSpace,
    EntryField.state => l10n.conflictsFieldState,
    EntryField.deletedAt => l10n.conflictsFieldDeleted,
    EntryField.noteKind => l10n.conflictsFieldNoteKind,
    EntryField.maturity => l10n.conflictsFieldMaturity,
    EntryField.originUrl => l10n.conflictsFieldOriginUrl,
    EntryField.authorName => l10n.conflictsFieldAuthor,
    EntryField.authorUrl => l10n.conflictsFieldAuthorUrl,
    EntryField.publishedAt => l10n.conflictsFieldPublishedAt,
    EntryField.originalBlobPath => l10n.conflictsFieldOriginalFile,
    _ => conflict.fieldName,
  };
}

/// El valor de una versión, para leerlo: el nombre de un espacio en lugar de su
/// identificador, una fecha en lugar de segundos, «En la papelera» en lugar de
/// un instante.
String conflictVersionText(
  AppLocalizations l10n,
  MergeConflict conflict,
  MergeConflictVersion version,
) {
  if (conflict.kind == MergeConflictKind.text) {
    final text = version.text;
    if (text == null) return l10n.conflictsGone;
    final length = version.length ?? text.length;
    return length > text.length ? '$text…' : text;
  }

  final raw = version.text;
  switch (conflict.fieldName) {
    case EntryField.deletedAt:
      final date = version.date;
      return date == null
          ? l10n.conflictsInLibrary
          : l10n.conflictsInTrash(_date(date));
    case EntryField.publishedAt:
      final date = version.date;
      return date == null ? l10n.conflictsEmptyValue : _date(date);
    case EntryField.spaceId:
      return version.spaceName ?? raw ?? l10n.conflictsEmptyValue;
    case EntryField.state:
      return switch (ItemState.values.asNameMap()[raw]) {
        ItemState.captured => l10n.conflictsStateCaptured,
        ItemState.processed => l10n.conflictsStateProcessed,
        ItemState.triaged => l10n.conflictsStateTriaged,
        ItemState.distilled => l10n.conflictsStateDistilled,
        ItemState.discarded => l10n.conflictsStateDiscarded,
        null => raw ?? l10n.conflictsEmptyValue,
      };
    case EntryField.noteKind:
      return NoteKind.values.asNameMap()[raw]?.label(l10n) ??
          raw ??
          l10n.conflictsEmptyValue;
    case EntryField.maturity:
      return NoteMaturity.values.asNameMap()[raw]?.label(l10n) ??
          raw ??
          l10n.conflictsEmptyValue;
  }
  return raw == null || raw.isEmpty ? l10n.conflictsEmptyValue : raw;
}

String _date(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
