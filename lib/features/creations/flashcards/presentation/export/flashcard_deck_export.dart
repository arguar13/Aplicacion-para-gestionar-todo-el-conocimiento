import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/export/study_pdf.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/widgets/study_viewer_parts.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_text_export.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En qué se descarga un mazo.
enum DeckExportFormat { anki, markdown, pdf }

/// «Descargar» de «Tarjetas didácticas» (F43, paso 8): pregunta el formato
/// —para Anki, Markdown o PDF— y arma el archivo. `null` si se cerró la hoja.
Future<CreationExportFile?> exportFlashcardDeck(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final format = await showStudyExportChoices<DeckExportFormat>(
    context,
    title: l10n.f43CardsExportTitle,
    choices: [
      StudyExportChoice(
        value: DeckExportFormat.anki,
        icon: Icons.style_outlined,
        title: l10n.f43CardsExportAnki,
        subtitle: l10n.f43CardsExportAnkiHint,
      ),
      StudyExportChoice(
        value: DeckExportFormat.markdown,
        icon: Icons.notes,
        title: l10n.f43CardsExportMarkdown,
        subtitle: l10n.f43CardsExportMarkdownHint,
      ),
      StudyExportChoice(
        value: DeckExportFormat.pdf,
        icon: Icons.picture_as_pdf_outlined,
        title: l10n.f43CardsExportPdf,
        subtitle: l10n.f43CardsExportPdfHint,
      ),
    ],
  );
  if (format == null) return null;
  final deck = FlashcardDeckJson.decode(creation.decodedContent);
  final title = studyCreationTitle(l10n, creation);
  return flashcardDeckFile(
    deck,
    format: format,
    title: title,
    labels: DeckExportLabels.of(l10n),
    createdAt: creation.createdAt,
  );
}

/// Los textos de los archivos del mazo, en el idioma de la app.
@immutable
class DeckExportLabels {
  const DeckExportLabels({
    required this.question,
    required this.answer,
    required this.hint,
    required this.subtitle,
    required this.page,
  });

  factory DeckExportLabels.of(AppLocalizations l10n) => DeckExportLabels(
    question: l10n.f43CardsQuestion,
    answer: l10n.f43CardsAnswer,
    hint: l10n.f43CardsHint,
    subtitle: (count) => l10n.f43CardsCount(count),
    page: l10n.f43CardsPdfPage,
  );

  final String question;
  final String answer;
  final String Function(String hint) hint;
  final String Function(int count) subtitle;
  final String Function(int page, int pages) page;
}

/// El archivo de [deck] en [format], con [title] de nombre.
Future<CreationExportFile> flashcardDeckFile(
  FlashcardDeck deck, {
  required DeckExportFormat format,
  required String title,
  required DeckExportLabels labels,
  required DateTime createdAt,
  AssetBundle? bundle,
}) async {
  final name = sanitizeFileName(title.isEmpty ? 'Mazo' : title);
  return switch (format) {
    DeckExportFormat.anki => CreationExportFile(
      fileName: '$name.tsv',
      bytes: flashcardDeckAnkiText(deck, title: title, createdAt: createdAt),
      mimeType: 'text/tab-separated-values',
    ),
    DeckExportFormat.markdown => CreationExportFile(
      fileName: '$name.md',
      bytes: Uint8List.fromList(
        utf8.encode(flashcardDeckMarkdown(deck, title: title, labels: labels)),
      ),
      mimeType: 'text/markdown',
    ),
    DeckExportFormat.pdf => CreationExportFile(
      fileName: '$name.pdf',
      bytes: await flashcardDeckPdf(
        deck,
        title: title,
        labels: labels,
        bundle: bundle,
      ),
      mimeType: 'application/pdf',
    ),
  };
}

/// El mazo para Anki, con el mismo archivo de texto que exporta Repasar (F17):
/// sus encabezados, el HTML de los campos y el mazo `Sinapsis::Estudiar::…`.
Uint8List flashcardDeckAnkiText(
  FlashcardDeck deck, {
  required String title,
  required DateTime createdAt,
}) {
  final deckPath = [
    'Sinapsis',
    'Estudiar',
    title.replaceAll('::', ':').trim(),
  ].where((part) => part.isNotEmpty).join('::');
  return buildAnkiTextExport([
    for (final card in deck.cards)
      AnkiCardExport(
        card: Flashcard(
          id: card.flashcardId ?? card.id,
          itemId: card.documentId ?? '',
          front: card.front,
          back: card.back,
          dueAt: createdAt,
          createdAt: createdAt,
        ),
        deckPath: deckPath,
        answer: card.hint.isEmpty ? card.back : '${card.back}\n\n${card.hint}',
      ),
  ], AnkiTextFormat.tsv);
}

/// El mazo en Markdown: cada tarjeta con su pregunta de título y su
/// respuesta debajo.
String flashcardDeckMarkdown(
  FlashcardDeck deck, {
  required String title,
  required DeckExportLabels labels,
}) {
  final buffer = StringBuffer('# $title\n\n')
    ..writeln(labels.subtitle(deck.cards.length))
    ..writeln();
  for (final (i, card) in deck.cards.indexed) {
    buffer
      ..writeln('## ${i + 1}. ${card.front}')
      ..writeln()
      ..writeln(card.back);
    if (card.hint.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('> ${labels.hint(card.hint)}');
    }
    buffer.writeln();
  }
  return buffer.toString();
}

/// El mazo en PDF: una tabla de pregunta y respuesta, para imprimir y
/// recortar o tapar una columna.
Future<Uint8List> flashcardDeckPdf(
  FlashcardDeck deck, {
  required String title,
  required DeckExportLabels labels,
  AssetBundle? bundle,
}) => buildStudyPdf(
  title: title,
  subtitle: labels.subtitle(deck.cards.length),
  pageLabel: labels.page,
  bundle: bundle,
  build: () => [
    pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: kStudyPdfLine, width: 0.6),
        top: pw.BorderSide(color: kStudyPdfLine, width: 0.6),
        bottom: pw.BorderSide(color: kStudyPdfLine, width: 0.6),
      ),
      columnWidths: const {
        0: pw.FixedColumnWidth(24),
        1: pw.FlexColumnWidth(),
        2: pw.FlexColumnWidth(1.3),
      },
      children: [
        pw.TableRow(
          children: [
            pw.SizedBox(),
            _cell(labels.question, header: true),
            _cell(labels.answer, header: true),
          ],
        ),
        for (final (i, card) in deck.cards.indexed)
          pw.TableRow(
            children: [
              _cell('${i + 1}', muted: true),
              _cell(card.front),
              _cell(
                card.hint.isEmpty
                    ? card.back
                    : '${card.back}\n${labels.hint(card.hint)}',
              ),
            ],
          ),
      ],
    ),
  ],
);

pw.Widget _cell(String text, {bool header = false, bool muted = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: header ? 9 : 10.5,
          color: header || muted ? kStudyPdfMuted : null,
          letterSpacing: header ? 0.8 : null,
          lineSpacing: 2,
        ),
      ),
    );
