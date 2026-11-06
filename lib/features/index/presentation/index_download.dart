/// «Descargar el índice» (F46, paso 4): lo que se está mirando —por tema o
/// por documento, su orden, los niveles, lo abierto o cerrado a mano, la
/// numeración, o lo que se busca—, en PDF listo para imprimir o en Markdown,
/// guardado donde la persona elija con el selector de siempre
/// (`fileSaverProvider`), como lo creado y la bibliografía.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/repositories/index_repository.dart';
import 'package:sinapsis/features/index/domain/services/index_match.dart';
import 'package:sinapsis/features/index/domain/services/index_outline.dart';
import 'package:sinapsis/features/index/domain/services/index_print.dart';
import 'package:sinapsis/features/index/presentation/export/index_pdf_exporter.dart';
import 'package:sinapsis/features/index/presentation/providers/index_providers.dart';
import 'package:sinapsis/features/index/presentation/providers/index_view.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_rows.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_more_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En qué se descarga el índice.
enum IndexDownloadFormat {
  /// Con los puntos y las páginas, listo para imprimir.
  pdf('pdf'),

  /// Texto con títulos y listas, para editarlo o pegarlo.
  markdown('md');

  const IndexDownloadFormat(this.extension);

  final String extension;
}

/// Quien arma el PDF del índice. Las pruebas de la pantalla lo cambian por
/// uno que lo arma en el mismo hilo y con las letras del disco.
final indexPdfExporterProvider = Provider<IndexPdfExporter>(
  (ref) => const IndexPdfExporter(),
);

/// Abre «Descargar el índice»: la hoja común con lo que se va a descargar
/// arriba y los dos formatos.
Future<void> showIndexDownload(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final view = ref.read(indexViewProvider);
  return showReadingMore(
    context,
    info: ReadingDocumentInfo(
      title: l10n.f46P4Download,
      kindLabel: indexDownloadScope(l10n, view),
      kindIcon: Icons.download_outlined,
    ),
    groups: [
      ReadingMenuGroup([
        for (final (format, icon, label, detail) in [
          (
            IndexDownloadFormat.pdf,
            Icons.picture_as_pdf_outlined,
            l10n.f46P4DownloadPdf,
            l10n.f46P4DownloadPdfHint,
          ),
          (
            IndexDownloadFormat.markdown,
            Icons.notes_outlined,
            l10n.f46P4DownloadMarkdown,
            l10n.f46P4DownloadMarkdownHint,
          ),
        ])
          ReadingMenuEntry(
            key: Key('index-download-${format.name}'),
            icon: icon,
            label: label,
            detail: detail,
            onSelected: () =>
                unawaited(downloadIndex(context, ref, view, format)),
          ),
      ]),
    ],
  );
}

/// Lo que se descarga, en palabras: «Por tema · hasta el nivel 3 ·
/// numerado», o lo que se busca.
String indexDownloadScope(AppLocalizations l10n, IndexView view) {
  if (view.searching) return l10n.f46P4ScopeSearch(view.query);
  return [
    switch (view.arrangement) {
      IndexArrangement.byTopic => l10n.f46P3ByTopic,
      IndexArrangement.byDocument => switch (view.order) {
        IndexDocumentOrder.title => l10n.f46P4ScopeByTitle,
        IndexDocumentOrder.recent => l10n.f46P4ScopeByRecent,
      },
    },
    switch (view.depth.levels) {
      final levels? => l10n.f46P4ScopeLevels(levels),
      null => l10n.f46P4ScopeAllLevels,
    },
    if (view.numbered) l10n.f46P4ScopeNumbered,
  ].join(' · ');
}

/// Arma el índice de [view] en [format] y lo guarda donde la persona elija.
/// Avisa mientras lo arma, y después si se guardó o falló; cancelar el
/// selector no dice nada.
Future<void> downloadIndex(
  BuildContext context,
  WidgetRef ref,
  IndexView view,
  IndexDownloadFormat format,
) async {
  final l10n = AppLocalizations.of(context)!;
  final locale = Localizations.localeOf(context).toLanguageTag();
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(indexRepositoryProvider);
  final saver = ref.read(fileSaverProvider);
  final exporter = ref.read(indexPdfExporterProvider);
  final now = ref.read(clockProvider)();
  _say(messenger, l10n.f46P4Working);
  try {
    final print = await readIndexPrint(
      repository,
      view,
      l10n,
      subtitle:
          '${indexDownloadScope(l10n, view)} · '
          '${DateFormat.yMMMMd(locale).format(now)}',
    );
    if (print.isEmpty) {
      _say(messenger, l10n.f46P4DownloadEmpty);
      return;
    }
    final bytes = switch (format) {
      IndexDownloadFormat.pdf => await exporter.export(
        print,
        page: l10n.f46P4PrintPage,
      ),
      IndexDownloadFormat.markdown => Uint8List.fromList(
        utf8.encode(indexMarkdown(print)),
      ),
    };
    final fileName =
        '${l10n.f46P4FileName(DateFormat('yyyy-MM-dd').format(now))}'
        '.${format.extension}';
    final path = await saver.saveFile(fileName: fileName, bytes: bytes);
    // Cancelar el selector no es un error: no se dice nada más.
    if (path != null || kIsWeb) {
      _say(messenger, l10n.f46P4Saved(fileName));
    } else {
      messenger.hideCurrentSnackBar();
    }
    // Como el resto de las descargas: lo que falla al leer, armar o guardar
    // se dice en una línea, nunca se cae.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    _say(messenger, l10n.f46P4DownloadFailed);
  }
}

/// Lee lo que [view] muestra, entero —todos los documentos, cada uno con sus
/// entradas hasta sus niveles—, y lo arma en renglones (`index_print`).
///
/// - **Por tema**: cada tema con sus documentos; uno con varios temas, bajo
///   cada uno (decisión D).
/// - **Por documento**: todos, en el orden elegido.
/// - **Buscando**: los documentos cuyo título coincide y lo encontrado con los
///   capítulos que lo contienen, como se ve.
///
/// Plegar un tema o un documento es para recorrer el Índice en la pantalla:
/// lo que dice cuánto se descarga son los niveles, como en Word.
Future<IndexPrint> readIndexPrint(
  IndexRepository repository,
  IndexView view,
  AppLocalizations l10n, {
  required String subtitle,
}) async {
  final topics = await repository.watchTopics().first;
  final names = {
    for (final topic in topics)
      if (topic.spaceId case final id?) id: topic.name,
  };
  final labels = IndexPrintLabels(
    topicName: (topic) => indexTopicName(l10n, topic),
    entryTitle: (entry) => indexEntryTitle(l10n, entry),
    entryPage: (entry) => indexEntryPage(l10n, entry),
    topicsNote: (spaceIds, {required listed}) {
      final named = [
        for (final id in spaceIds)
          if (names[id] case final name?) name,
      ];
      if (named.isEmpty) return null;
      return listed
          ? l10n.f46P3InTopics(named.join(', '))
          : l10n.f46P3AlsoIn(named.join(', '));
    },
  );

  final List<IndexPrintLine> lines;
  if (view.searching) {
    // Como mucho las mismas que muestra la pantalla (`kIndexSearchLimit`).
    final hits = await repository.watchSearch(view.query).first;
    final documents = await repository
        .watchDocuments(IndexDocumentOrder.title)
        .first;
    lines = indexPrintSearch(
      documents: [
        for (final document in documents)
          if (indexTitleMatches(document.title, view.query)) document,
      ],
      groups: groupIndexSearch(hits),
      labels: labels,
    );
  } else {
    final groups = <IndexPrintGroup>[
      if (view.arrangement == IndexArrangement.byTopic)
        for (final topic in topics)
          (
            topic: topic,
            documents: await repository.watchDocumentsOf(topic.spaceId).first,
          )
      else
        (
          topic: null,
          documents: await repository.watchDocuments(view.order).first,
        ),
    ];
    final ids = {
      for (final group in groups)
        for (final document in group.documents) document.id,
    }.toList();
    final entries = (await repository.readEntries(
      ids,
    )).getOrElse((failure) => throw StateError('$failure'));
    lines = indexPrintTree(
      groups: groups,
      entries: entries,
      depth: view.depth.levels,
      folds: view.chapterFolds,
      numbered: view.numbered,
      labels: labels,
    );
  }
  return IndexPrint(
    title: l10n.f46P4PrintTitle,
    subtitle: subtitle,
    lines: lines,
  );
}

void _say(ScaffoldMessengerState messenger, String text) => messenger
  ..hideCurrentSnackBar()
  ..showAppSnackBar(AppSnackBar(content: Text(text)));
