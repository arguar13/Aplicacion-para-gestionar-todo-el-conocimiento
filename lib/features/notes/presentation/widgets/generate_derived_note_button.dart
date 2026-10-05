import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_model_option_notifier.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/usecases/generate_derived_note_usecase.dart';
import 'package:sinapsis/features/notes/presentation/providers/derived_note_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El botón "Generar derivado" (F16, D5), en el detalle de un cuaderno o de
/// un elemento: exactamente uno de [notebookId]/[itemId] debe venir puesto.
///
/// Mismo criterio que `SummarizeButton` para el modelo: sin él descargado
/// no hay nada que generar, así que se avisa y se ofrece ir a descargarlo
/// ANTES de mostrar el menú de tipos —no tiene sentido elegir un tipo para
/// algo que no va a poder correr—.
class GenerateDerivedNoteButton extends ConsumerStatefulWidget {
  const GenerateDerivedNoteButton({
    required this.sourceTitle,
    this.notebookId,
    this.itemId,
    super.key,
  }) : assert(
         (notebookId == null) != (itemId == null),
         'un derivado sale de un cuaderno o de un elemento, nunca los dos ni '
         'ninguno',
       );

  /// El nombre del cuaderno o el título del elemento, para el título por
  /// defecto de la nota nueva.
  final String sourceTitle;
  final String? notebookId;
  final String? itemId;

  @override
  ConsumerState<GenerateDerivedNoteButton> createState() =>
      _GenerateDerivedNoteButtonState();
}

class _GenerateDerivedNoteButtonState
    extends ConsumerState<GenerateDerivedNoteButton> {
  var _loading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return IconButton(
      icon: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome_outlined),
      tooltip: l10n.derivedNoteGenerateTooltip,
      onPressed: _loading ? null : _start,
    );
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context)!;
    final ready = await ref.read(chatModelManagerProvider).isReady();
    if (!mounted) return;

    if (!ready) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.derivedNoteModelRequired),
            action: SnackBarAction(
              label: l10n.derivedNoteDownloadAction,
              onPressed: () => context.push(RoutePaths.chatModel),
            ),
          ),
        );
      return;
    }

    final type = await _pickType(l10n);
    if (type == null || !mounted) return;

    await _generate(type);
  }

  Future<DerivedNoteType?> _pickType(AppLocalizations l10n) {
    return showModalBottomSheet<DerivedNoteType>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in DerivedNoteType.values)
              ListTile(
                key: Key('derived-note-type-${type.name}'),
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(_labelOf(type, l10n)),
                onTap: () => Navigator.of(sheetContext).pop(type),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate(DerivedNoteType type) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _loading = true);

    final model = ref.read(chatModelOptionNotifierProvider).name;
    final result = await ref.read(generateDerivedNoteUseCaseProvider)(
      GenerateDerivedNoteParams(
        type: type,
        title: _titleOf(type, l10n),
        model: model,
        notebookId: widget.notebookId,
        itemId: widget.itemId,
      ),
    );
    if (!mounted) return;
    setState(() => _loading = false);

    result.match(
      (failure) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(failure.localizedMessage(l10n))),
          );
      },
      (result) {
        final saved = result.note;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(l10n.derivedNoteCreated(saved.title)),
              action: SnackBarAction(
                label: l10n.derivedNoteViewAction,
                onPressed: () {
                  if (context.mounted) {
                    context.push(RoutePaths.itemDetail(saved.id));
                  }
                },
              ),
            ),
          );
      },
    );
  }

  String _labelOf(DerivedNoteType type, AppLocalizations l10n) =>
      switch (type) {
        DerivedNoteType.studyGuide => l10n.derivedNoteTypeStudyGuide,
        DerivedNoteType.openQuestions => l10n.derivedNoteTypeOpenQuestions,
        DerivedNoteType.outline => l10n.derivedNoteTypeOutline,
        DerivedNoteType.timeline => l10n.derivedNoteTypeTimeline,
      };

  String _titleOf(DerivedNoteType type, AppLocalizations l10n) =>
      switch (type) {
        DerivedNoteType.studyGuide => l10n.derivedNoteTitleStudyGuide(
          widget.sourceTitle,
        ),
        DerivedNoteType.openQuestions => l10n.derivedNoteTitleOpenQuestions(
          widget.sourceTitle,
        ),
        DerivedNoteType.outline => l10n.derivedNoteTitleOutline(
          widget.sourceTitle,
        ),
        DerivedNoteType.timeline => l10n.derivedNoteTitleTimeline(
          widget.sourceTitle,
        ),
      };
}
