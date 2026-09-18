import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El texto completo de [item], para seleccionar un fragmento y
/// "Extraer como nota" desde ahí —el mismo menú de selección que ya
/// existe en el detalle de cualquier elemento (`HighlightableText`), sin
/// ninguna lógica de extracción nueva—.
class ExtractNoteScreen extends StatelessWidget {
  const ExtractNoteScreen({
    required this.item,
    required this.rendition,
    super.key,
  });

  final KnowledgeItem item;
  final TextRendition rendition;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.inboxExtractTitle(item.title))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: HighlightableText(
              itemId: item.id,
              renditionId: rendition.id,
              content: rendition.content,
            ),
          ),
        ),
      ),
    );
  }
}
