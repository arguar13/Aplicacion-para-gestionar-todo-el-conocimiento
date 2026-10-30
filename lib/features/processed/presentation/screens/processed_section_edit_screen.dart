import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_panel.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_presentation.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_text_pages.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// **Editar** el texto, el resumen o la síntesis de un documento procesado
/// (F41), desde ⋮ de su lector (F47, paso 1): la edición de siempre, de a una
/// página —con su paso de páginas, «Editar» y «Quitar» en cada una— o de a
/// una oración. Lo que se cambia se ve en el lector al volver, y en «Lo
/// creado»: es una vista viva.
class ProcessedSectionEditScreen extends ConsumerWidget {
  const ProcessedSectionEditScreen({
    required this.documentId,
    required this.section,
    super.key,
  });

  final String documentId;
  final ProcessedSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final document = ref.watch(processedDocumentProvider(documentId));
    final value = document.valueOrNull;
    final count = value?.summary.partCounts[section] ?? 0;
    final source = value?.source;
    final sourceItemId = source == null || source.inTrash
        ? null
        : source.itemId;

    return Scaffold(
      key: Key('processed-edit-${section.name}'),
      appBar: AppBar(
        title: Text(
          l10n.f47P1EditTitle(section.label(l10n)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: value == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (section == ProcessedSection.text)
                  ProcessedTextPages(
                    documentId: documentId,
                    pageCount: count,
                    sourceItemId: sourceItemId,
                  )
                else
                  ProcessedPartsList(
                    documentId: documentId,
                    section: section,
                    count: count,
                    sourceItemId: sourceItemId,
                  ),
              ],
            ),
    );
  }
}
