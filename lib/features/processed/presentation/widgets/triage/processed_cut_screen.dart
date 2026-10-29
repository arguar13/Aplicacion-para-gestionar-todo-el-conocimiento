import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_triage.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_triage_providers.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_toggles.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/presentation/providers/viewer_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre «Cortar del original» de [sourceItemId] encima de la hoja «¿Qué va a
/// Procesado?» (F41).
Future<void> openProcessedCutScreen(
  BuildContext context,
  String sourceItemId,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => ProcessedCutScreen(sourceItemId: sourceItemId),
  ),
);

/// «Cortar del original» (F41): el texto de una fuente en **modo cortar**,
/// para elegir a mano qué pasajes van a su documento procesado.
///
/// - **Se ve en su visor de siempre** —el PDF real, la página web guardada, el
///   lector de Word, EPUB y texto—, o en su texto extraído, el de un audio,
///   un video o una foto, con el mismo lector, por páginas si es un libro.
///   Arriba, «Ver el texto extraído» pasa del PDF o la página a su texto (una
///   página escaneada no tiene letras donde seleccionar), y vuelve.
/// - **Se corta con la barrita de resaltar de siempre** (F38): mientras esta
///   pantalla está abierta suma «A Procesado», que manda lo seleccionado a
///   los fragmentos, y su «Extraer como nota» lo suma a las notas del
///   documento procesado en vez de crear una nota suelta en la Biblioteca
///   (decisión C). Todo lo demás —resaltar, escuchar, la tarjeta— sigue
///   igual.
/// - **Cada corte se ve marcado en el texto**, encima de todo, y en una
///   **lista viva abajo**, donde se puede quitar.
/// - Arriba van los botones de estudiar de la fuente, los de siempre: prender
///   y apagar lo estudiado mientras se corta. El resumen, la síntesis y las
///   palabras clave ya no se eligen al triar (F43, decisión J).
///
/// Cómo lo saben los visores sin saber de Procesado: la pantalla declara de
/// qué fuente se corta ([processedCutSourceProvider], solo para lo que tiene
/// adentro) y cada uno pregunta eso al armar su barrita y al pintar. Lo
/// cortado vive en la hoja ([processedTriageProvider]): cerrar esta pantalla
/// no pierde nada, y la hoja lo muestra al volver.
class ProcessedCutScreen extends ConsumerStatefulWidget {
  const ProcessedCutScreen({required this.sourceItemId, super.key});

  final String sourceItemId;

  @override
  ConsumerState<ProcessedCutScreen> createState() => _ProcessedCutScreenState();
}

class _ProcessedCutScreenState extends ConsumerState<ProcessedCutScreen> {
  /// Qué visor le toca al original, resuelto una sola vez.
  Future<ResolvedViewer>? _resolved;

  /// Si se ve el texto extraído en vez del PDF o la página.
  var _asText = false;

  Future<ResolvedViewer> _resolve(KnowledgeItem item) =>
      _resolved ??= ref.read(fileViewerResolverProvider).resolve(item);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final id = widget.sourceItemId;
    // Lo cortado vive en la hoja: mirarla la mantiene viva aunque la hoja
    // se cierre mientras tanto.
    ref.watch(processedTriageProvider(id));
    final item = ref.watch(libraryItemProvider(id)).valueOrNull;
    final text = item == null ? null : studyTextOf(item);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.processedCutTitle),
            actions: [
              if (item != null && text != null)
                FutureBuilder<ResolvedViewer>(
                  future: _resolve(item),
                  builder: (context, snapshot) {
                    if (_originalOf(snapshot.data, text) == null) {
                      return const SizedBox.shrink();
                    }
                    return TextButton.icon(
                      key: const Key('processed-cut-switch-view'),
                      onPressed: () => setState(() => _asText = !_asText),
                      icon: Icon(
                        _asText ? Icons.description_outlined : Icons.notes,
                      ),
                      label: Text(
                        _asText
                            ? l10n.processedCutShowOriginal
                            : l10n.processedCutShowText,
                      ),
                    );
                  },
                ),
            ],
          ),
          body: SafeArea(
            child: ProviderScope(
              overrides: [processedCutSourceProvider.overrideWithValue(id)],
              child: Column(
                children: [
                  Expanded(child: _body(l10n, item, text)),
                  _CutTray(sourceItemId: id),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n, KnowledgeItem? item, StudyText? text) {
    if (item == null) return const Center(child: CircularProgressIndicator());
    if (text == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.processedCutNoText, textAlign: TextAlign.center),
        ),
      );
    }
    return FutureBuilder<ResolvedViewer>(
      future: _resolve(item),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final original = _asText ? null : _originalOf(snapshot.data, text);
        return original ?? _TextView(title: item.title, text: text);
      },
    );
  }

  /// El original en su visor —el PDF, la página guardada—, si tiene uno y
  /// su texto es el mismo del que se corta; si no, `null`, y se corta del
  /// texto extraído.
  Widget? _originalOf(ResolvedViewer? resolved, StudyText text) {
    final title = ref.read(libraryItemProvider(text.itemId)).valueOrNull?.title;
    return switch (resolved) {
      PdfResolvedViewer(:final path, text: final study?)
          when study.renditionId == text.renditionId =>
        Column(
          children: [
            StudyBar(text: study),
            Expanded(
              child: PdfViewerView(path: path, text: study, title: title ?? ''),
            ),
          ],
        ),
      WebPageResolvedViewer(:final path, :final url, text: final study?)
          when study.renditionId == text.renditionId =>
        Column(
          children: [
            StudyBar(text: study),
            Expanded(
              child: WebPageViewerView(
                path: path,
                url: url,
                text: study,
                title: title ?? '',
                readAloud: true,
              ),
            ),
          ],
        ),
      _ => null,
    };
  }
}

/// El texto extraído en el lector de siempre —por páginas, si es largo—, con
/// los botones de estudiar.
class _TextView extends StatelessWidget {
  const _TextView({required this.title, required this.text});

  final String title;
  final StudyText text;

  @override
  Widget build(BuildContext context) => DocumentReaderView(
    key: const Key('processed-cut-text'),
    title: title,
    content: text.content,
    markdown: text.markdown,
    study: text,
    showFontControls: true,
  );
}

/// Lo cortado hasta ahora, abajo y siempre a la vista: los fragmentos y las
/// notas extraídas, cada uno con «Quitar», y «Listo» para volver a la hoja.
///
/// Sin nada todavía, cómo se corta. Mide a lo sumo un tercio de la pantalla,
/// y se desliza si hay más.
class _CutTray extends ConsumerWidget {
  const _CutTray({required this.sourceItemId});

  final String sourceItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final triage = ref.watch(processedTriageProvider(sourceItemId));
    final controller = ref.read(processedTriageProvider(sourceItemId).notifier);
    final fragments = triage.clipsOf(ProcessedSection.fragments);
    final notes = triage.clipsOf(ProcessedSection.notes);
    final clips = [
      for (final clip in fragments) (clip, ProcessedSection.fragments),
      for (final clip in notes) (clip, ProcessedSection.notes),
    ];

    return Material(
      key: const Key('processed-cut-tray'),
      color: scheme.surfaceContainerHigh,
      elevation: 2,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height / 3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.content_cut, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    // Se anuncia sola cuando cambia: cortar con un lector de
                    // pantalla dice cuánto lleva.
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        clips.isEmpty
                            ? l10n.processedCutHint
                            : [
                                l10n.processedTriageFragmentCount(
                                  fragments.length,
                                ),
                                l10n.processedTriageNoteCount(notes.length),
                              ].join(' · '),
                        style: clips.isEmpty
                            ? theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              )
                            : theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('processed-cut-done'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(l10n.processedCutDone),
                  ),
                ],
              ),
            ),
            if (clips.isNotEmpty)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: clips.length,
                  itemBuilder: (context, index) {
                    final (clip, section) = clips[index];
                    return TriageClipTile(
                      clip: clip,
                      section: section,
                      onRemove: () => controller.remove(clip.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Un pasaje de una lista —un fragmento cortado o una nota—: su texto, a lo
/// sumo en tres renglones, y «Quitar». El mismo en la hoja y en la pantalla
/// de cortar.
class TriageClipTile extends StatelessWidget {
  const TriageClipTile({
    required this.clip,
    required this.section,
    required this.onRemove,
    super.key,
  });

  final TriageClip clip;
  final ProcessedSection section;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final fragment = section == ProcessedSection.fragments;
    return ListTile(
      key: ValueKey('triage-clip-${clip.id}'),
      dense: true,
      leading: Icon(
        fragment ? Icons.format_quote_outlined : Icons.sticky_note_2_outlined,
        color: fragment ? scheme.primary : scheme.tertiary,
      ),
      title: Text(
        clip.excerpt.trim().isEmpty ? '…' : clip.excerpt.trim(),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        key: ValueKey('triage-clip-remove-${clip.id}'),
        tooltip: l10n.processedCutRemove,
        icon: const Icon(Icons.close),
        onPressed: onRemove,
      ),
    );
  }
}
