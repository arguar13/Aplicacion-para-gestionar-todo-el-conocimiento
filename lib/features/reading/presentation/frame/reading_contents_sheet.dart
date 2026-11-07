import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/app_bottom_sheet.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una sección de «Contenido» que pone quien arma el marco: las fuentes de lo
/// creado, las partes de un documento procesado. Con [entries] —renglones que
/// llevan a un lugar— o con [child], lo que haga falta mostrar —las fichas de
/// cada fuente—.
@immutable
class ReadingContentsSection {
  const ReadingContentsSection({
    required this.title,
    this.entries = const [],
    this.child,
    this.key,
  });

  final String title;
  final List<ReadingOutlineEntry> entries;

  /// Lo que va debajo de los renglones. Se arma con el contexto de la hoja:
  /// lo que abre algo encima la cierra antes (ver [closeReadingSheet]).
  final WidgetBuilder? child;

  final Key? key;
}

/// Abre «Contenido» del marco de lectura (F47, paso 1): el índice que arma
/// el cuerpo —los documentos de una extracción, los capítulos de un libro—,
/// las secciones de quien arma el marco —las fuentes, las partes de un
/// documento procesado— y **«Leer: Todo · Resumen · Síntesis · Palabras
/// clave»**, que empieza a leer esa parte en voz alta.
Future<void> showReadingContents(
  BuildContext context, {
  required ReadingFrameController controller,
  required List<ReadingContentsSection> sections,
}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (_) =>
        ReadingContentsSheet(controller: controller, sections: sections),
  );
}

/// Cierra la hoja de [context] y, ya cerrada, hace [then]: lo que se abre
/// encima —otra pantalla, otra hoja— no queda debajo de ella.
void closeReadingSheet(BuildContext context, VoidCallback then) {
  Navigator.of(context).pop();
  then();
}

/// Lo de adentro de «Contenido».
class ReadingContentsSheet extends StatelessWidget {
  const ReadingContentsSheet({
    required this.controller,
    required this.sections,
    super.key,
  });

  final ReadingFrameController controller;
  final List<ReadingContentsSection> sections;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final outline = controller.outline;
        return ListView(
          key: const Key('reading-contents-sheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Text(
                l10n.f47P1ContentsTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (outline.isNotEmpty)
              _Section(title: l10n.f47P1ContentsInDocument, entries: outline),
            const _ReadAloudScopes(),
            for (final section in sections)
              _Section(
                key: section.key,
                title: section.title,
                entries: section.entries,
                child: section.child,
              ),
            if (outline.isEmpty && sections.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  l10n.f47P1ContentsEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.entries,
    this.child,
    super.key,
  });

  final String title;
  final List<ReadingOutlineEntry> entries;
  final WidgetBuilder? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        for (final entry in entries)
          ListTile(
            key: entry.key,
            contentPadding: EdgeInsets.only(
              left: 8 + 20.0 * entry.depth,
              right: 8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(entry.label),
            subtitle: entry.detail == null ? null : Text(entry.detail!),
            onTap: () => closeReadingSheet(context, entry.onSelected),
          ),
        if (child case final child?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: child(context),
          ),
      ],
    );
  }
}

/// «Leer: Todo · Resumen · Síntesis · Palabras clave» (F39), ahora en
/// «Contenido»: lee esa parte de lo que se ve, desde su comienzo —o desde lo
/// que se mira, en un libro o un PDF—. La parte que todavía no tiene nada se
/// ve apagada. Un documento que no se estudia —un adjunto— solo ofrece
/// «Todo».
class _ReadAloudScopes extends ConsumerWidget {
  const _ReadAloudScopes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final document = ref.watch(
      readableRegistryProvider.select(currentReadableOf),
    );
    if (document == null) return const SizedBox.shrink();
    final current = ref.watch(
      readAloudControllerProvider.select(
        (s) => s.document?.id == document.id && s.panel != ReadAloudPanel.hidden
            ? s.scope
            : null,
      ),
    );
    final scopes = document.hasScopes ? ReadScope.values : [ReadScope.all];

    String label(ReadScope scope) => switch (scope) {
      ReadScope.all => l10n.readAloudScopeAll,
      ReadScope.summary => l10n.readAloudScopeSummary,
      ReadScope.synthesis => l10n.readAloudScopeSynthesis,
      ReadScope.keywords => l10n.readAloudScopeKeywords,
    };

    return Column(
      key: const Key('reading-contents-read-aloud'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
          child: Semantics(
            header: true,
            child: Text(
              l10n.f47P1ContentsReadAloud,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scope in scopes)
                ChoiceChip(
                  key: Key('reading-read-${scope.name}'),
                  avatar: const Icon(Icons.headphones_outlined, size: 18),
                  label: Text(label(scope)),
                  selected: scope == current,
                  // Sin onSelected, la ficha queda apagada: esa parte no
                  // tiene nada todavía.
                  onSelected: !document.offers(scope)
                      ? null
                      : (_) => closeReadingSheet(
                          context,
                          () => unawaited(
                            ref
                                .read(readAloudControllerProvider.notifier)
                                .open(document, scope: scope),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
