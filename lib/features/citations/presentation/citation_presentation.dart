import 'package:flutter/material.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/reference_style.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se nombran, para quien los mira, los estilos de cita, sus formas y sus
/// idiomas (F15). Vive en un solo lugar: la sección de cita, Ajustes y la
/// bibliografía los nombran igual.
extension ReferenceStylePresentation on ReferenceStyle {
  /// «APA 7», «MLA 9», «IEEE»; los dos sistemas de Chicago llevan además su
  /// explicación en el idioma de la app, porque su nombre corto —«NB» y «AD»—
  /// no dice nada a quien no lo conoce.
  String label(AppLocalizations l10n) => switch (id) {
    'chicago17nb' => l10n.citationStyleChicagoNotes,
    'chicago17ad' => l10n.citationStyleChicagoAuthorDate,
    _ => name,
  };
}

extension CitationFormPresentation on CitationForm {
  String label(AppLocalizations l10n) => switch (this) {
    CitationForm.reference => l10n.citationFormReference,
    CitationForm.inText => l10n.citationFormInText,
    CitationForm.note => l10n.citationFormNote,
    CitationForm.shortNote => l10n.citationFormShortNote,
  };

  /// Si la forma cita un pasaje —una página, un minuto—: la entrada de la
  /// lista cita la obra entera.
  bool get takesLocator => this != CitationForm.reference;
}

extension CitationLanguagePresentation on CitationLanguage {
  String label(AppLocalizations l10n) => switch (this) {
    CitationLanguage.es => l10n.citationLanguageEs,
    CitationLanguage.en => l10n.citationLanguageEn,
  };
}

extension CitationGapPresentation on CitationGap {
  /// Qué falta, en el idioma de la app: para la línea de «Faltan datos».
  String label(AppLocalizations l10n) => switch (this) {
    CitationGap.author => l10n.contributorRoleAuthor,
    CitationGap.title => l10n.citationGapTitle,
    CitationGap.year => l10n.referenceYear,
    CitationGap.publisher => l10n.referenceFieldPublisher,
    CitationGap.container => l10n.referenceFieldContainer,
    CitationGap.volume => l10n.referenceFieldVolume,
    CitationGap.link => l10n.citationGapLink,
    CitationGap.type => l10n.referenceFieldType,
    CitationGap.accessed => l10n.referenceFieldAccessed,
  };
}

/// La página o el minuto que alguien escribió: «12», «12-14» o «0:14:35». Un
/// texto con dos puntos es un instante de un audio o un video; vacío, `null`.
CitationLocator? parseLocator(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.contains(':')
      ? CitationLocator.time(trimmed)
      : CitationLocator.page(trimmed);
}

/// La cita como se muestra en pantalla: las cursivas del estilo en cursiva y lo
/// que falta resaltado, para que se vea qué completar.
TextSpan citationTextSpan(Citation citation, ThemeData theme) => TextSpan(
  style: theme.textTheme.bodyMedium,
  children: [
    for (final run in citation.runs)
      switch (run) {
        PlainRun() => TextSpan(text: run.text),
        ItalicRun() => TextSpan(
          text: run.text,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
        GapRun() => TextSpan(
          text: run.text,
          style: TextStyle(
            backgroundColor: theme.colorScheme.errorContainer,
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      },
  ],
);
