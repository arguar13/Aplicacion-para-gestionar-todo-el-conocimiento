import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/data/services/fragment_locator_resolver.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/citation_source_of.dart';
import 'package:sinapsis/features/citations/presentation/providers/citation_preferences.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/reference/presentation/providers/reference_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Donde de una fuente está un pasaje, para citarlo.
final fragmentLocatorResolverProvider = Provider<FragmentLocatorResolver>(
  (ref) => FragmentLocatorResolver(ref.watch(appDatabaseProvider)),
);

/// La cita de un pasaje de la fuente [sourceId] (F15), en el estilo y el idioma
/// por defecto: la que apunta a un lugar del texto y no a la obra entera.
///
/// Es la nota al pie en un estilo de notas —Chicago— y la cita en el texto en
/// los demás. Con [locator] lleva la página o el minuto; sin él, cita la obra.
/// Devuelve `null` si no hay tal fuente: no existe, o es una nota.
Future<Citation?> citeFragment(
  WidgetRef ref, {
  required String sourceId,
  CitationLocator? locator,
}) async {
  final found = await ref.read(libraryRepositoryProvider).findById(sourceId);
  final item = found.toNullable();
  // Una nota no se cita: lo que se cita es lo que salió de una fuente.
  if (item == null || item.source.kind == SourceKind.manualNote) return null;
  final reference = await ref.read(referenceRepositoryProvider).read(sourceId);

  final style = ref.read(defaultCitationStyleProvider);
  final form = style.forms.contains(CitationForm.note)
      ? CitationForm.note
      : CitationForm.inText;
  return style.format(
    form,
    citationSourceOf(item, reference),
    CitationContext(
      language: ref.read(defaultCitationLanguageProvider),
      locator: locator,
    ),
  );
}

/// Copia la cita de un pasaje de [sourceId] al portapapeles, como texto plano,
/// y lo avisa. Lo que falta de la fuente sale marcado en la cita, no callado.
Future<void> copyFragmentCitation(
  BuildContext context,
  WidgetRef ref, {
  required String sourceId,
  CitationLocator? locator,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final citation = await citeFragment(
    ref,
    sourceId: sourceId,
    locator: locator,
  );
  if (citation == null) return;
  await Clipboard.setData(ClipboardData(text: citation.toPlainText()));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.citationCopied)));
}
