import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que dice la confirmación antes de cargar la biblioteca de ejemplo, en
/// oraciones: qué se guarda, cuánto se baja y cómo se carga.
///
/// Describe lo que falta de verdad, no la biblioteca entera: si quedan dos
/// recursos —un PDF y una nota— nombra esos dos, y no habla de bajar nada
/// cuando no queda nada por bajar («unos 0 B» no le dice nada a nadie).
List<String> sampleLibraryConfirmSentences(
  AppLocalizations l10n,
  List<SampleResource> pending,
) {
  final locale = l10n.localeName;
  final files = pending.whereType<SampleFile>();
  final links = pending.whereType<SampleLink>();
  final now = sampleLibraryBytes(files);
  final later = sampleLibraryBytes(links);

  final pages = links.where((link) => link.kind == SampleLinkKind.webArticle);
  final videos = links.where(
    (link) => link.kind == SampleLinkKind.youtubeVideo,
  );
  final laterWhat = _enumerate(l10n, [
    if (pages.isNotEmpty) l10n.sampleLibraryLaterPages(pages.length),
    if (videos.isNotEmpty) l10n.sampleLibraryLaterVideoAudio(videos.length),
  ]);

  return [
    l10n.sampleLibraryConfirmSaves(pending.length, _kinds(l10n, pending)),
    if (now > 0 && later > 0)
      l10n.sampleLibraryConfirmDownloadNowAndLater(
        formatFileSize(now, locale),
        formatFileSize(later, locale),
        laterWhat,
      )
    else if (now > 0)
      l10n.sampleLibraryConfirmDownloadNow(formatFileSize(now, locale))
    else if (later > 0)
      l10n.sampleLibraryConfirmDownloadLater(
        formatFileSize(later, locale),
        laterWhat,
      ),
    l10n.sampleLibraryConfirmBackground(pending.length),
  ];
}

/// Cuánto se baja de internet por estos recursos, aproximado.
int sampleLibraryBytes(Iterable<SampleResource> resources) =>
    resources.fold(0, (sum, resource) => sum + resource.approxBytes);

/// Los tipos que se van a cargar, cada uno con cuántos: «3 artículos, 1 PDF
/// y 2 notas». Siempre en el mismo orden, el de la lista de ejemplo, y sin
/// los tipos de los que no queda ninguno.
String _kinds(AppLocalizations l10n, List<SampleResource> pending) {
  final counts = <_Kind, int>{};
  for (final resource in pending) {
    final kind = _kindOf(resource);
    counts[kind] = (counts[kind] ?? 0) + 1;
  }

  return _enumerate(l10n, [
    for (final kind in _Kind.values)
      if (counts[kind] case final count?) _describe(l10n, kind, count),
  ]);
}

/// Los tipos que nombra la confirmación. No son los de los recursos tal
/// cual: un PDF y un EPUB son los dos archivos, pero para quien lee son un
/// PDF y un libro.
enum _Kind { articles, videos, pdfs, books, texts, audios, images, notes }

_Kind _kindOf(SampleResource resource) => switch (resource) {
  SampleLink(kind: SampleLinkKind.webArticle) => _Kind.articles,
  SampleLink(kind: SampleLinkKind.youtubeVideo) => _Kind.videos,
  SampleFile(kind: SampleFileKind.pdf) => _Kind.pdfs,
  SampleFile(kind: SampleFileKind.epub) => _Kind.books,
  SampleFile(kind: SampleFileKind.text) => _Kind.texts,
  SampleFile(kind: SampleFileKind.audio) => _Kind.audios,
  SampleFile(kind: SampleFileKind.image) => _Kind.images,
  SampleNote() => _Kind.notes,
};

String _describe(AppLocalizations l10n, _Kind kind, int count) =>
    switch (kind) {
      _Kind.articles => l10n.sampleLibraryKindArticles(count),
      _Kind.videos => l10n.sampleLibraryKindVideos(count),
      _Kind.pdfs => l10n.sampleLibraryKindPdfs(count),
      _Kind.books => l10n.sampleLibraryKindBooks(count),
      _Kind.texts => l10n.sampleLibraryKindTexts(count),
      _Kind.audios => l10n.sampleLibraryKindAudios(count),
      _Kind.images => l10n.sampleLibraryKindImages(count),
      _Kind.notes => l10n.sampleLibraryKindNotes(count),
    };

/// «a», «a y b», «a, b y c»: las comas entre los primeros y la conjunción
/// del idioma antes del último.
String _enumerate(AppLocalizations l10n, List<String> items) {
  if (items.length < 2) return items.join();
  return l10n.sampleLibraryListJoin(
    items.take(items.length - 1).join(', '),
    items.last,
  );
}
