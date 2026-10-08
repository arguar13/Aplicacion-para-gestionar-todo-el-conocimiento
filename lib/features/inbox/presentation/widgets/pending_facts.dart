import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/features/inbox/domain/entities/source_extent.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un dato de lo que espera en la Bandeja: su ícono, cómo se lee y cómo lo
/// anuncia un lector de pantalla.
typedef PendingFact = ({IconData icon, String text, String semantics});

/// Los datos de [source] para la tarjeta de la Bandeja (F30, decisión 68):
/// autor, fecha de publicación, sitio, extensión —páginas o duración— e
/// idioma, en ese orden. Solo los que se saben: no se rellena lo que falta.
///
/// Es una función y no un widget para poder probarla sin dibujar nada. Nunca
/// hay un reproductor: la Bandeja trabaja con el texto y sus datos.
List<PendingFact> pendingFactsOf(
  Source source,
  SourceExtent extent,
  AppLocalizations l10n,
  String locale,
) {
  final facts = <PendingFact>[];

  final author = source.authorName?.trim();
  if (author != null && author.isNotEmpty) {
    facts.add((
      icon: Icons.person_outline,
      text: author,
      semantics: '${l10n.inboxFactAuthor}: $author',
    ));
  }

  final published = source.publishedAt;
  if (published != null) {
    final text = DateFormat.yMMMd(locale).format(published.toLocal());
    facts.add((
      icon: Icons.event_outlined,
      text: text,
      semantics: '${l10n.inboxFactPublished}: $text',
    ));
  }

  final site = siteOf(source.url);
  if (site != null) {
    facts.add((
      icon: Icons.public,
      text: site,
      semantics: '${l10n.inboxFactSite}: $site',
    ));
  }

  final length = extentText(extent, l10n);
  if (length != null) {
    facts.add((
      icon: extent.pages != null
          ? Icons.menu_book_outlined
          : Icons.schedule_outlined,
      text: length,
      semantics: '${l10n.inboxFactLength}: $length',
    ));
  }

  final language = source.language;
  if (language != null && language.isNotEmpty) {
    final text = accentDisplayName(language);
    facts.add((
      icon: Icons.translate,
      text: text,
      semantics: '${l10n.inboxFactLanguage}: $text',
    ));
  }
  return facts;
}

/// El sitio de una dirección —«es.wikipedia.org», sin el «www.»—, o `null` si
/// no es una dirección con sitio (un archivo local, una nota).
String? siteOf(String? url) {
  if (url == null) return null;
  final host = Uri.tryParse(url.trim())?.host;
  if (host == null || host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// «248 páginas», «1 h 12 min» o «7 min»; `null` si no se sabe ninguna de las
/// dos. Las páginas mandan: un PDF no tiene duración.
String? extentText(SourceExtent extent, AppLocalizations l10n) {
  final pages = extent.pages;
  if (pages != null) return l10n.inboxFactPages(pages);
  final duration = extent.duration;
  if (duration == null) return null;
  final minutes = duration.inMinutes;
  return minutes >= 60
      ? l10n.inboxFactHoursMinutes(minutes ~/ 60, minutes % 60)
      : l10n.inboxFactMinutes(minutes < 1 ? 1 : minutes);
}

/// La línea de datos de la tarjeta de la Bandeja: autor, fecha, sitio,
/// páginas o duración e idioma, como rótulos chicos. No dibuja nada si no se
/// sabe ninguno.
class PendingFactsLine extends ConsumerWidget {
  const PendingFactsLine({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final extent =
        ref.watch(inboxExtentProvider(item.id)).valueOrNull ??
        SourceExtent.none;
    final facts = pendingFactsOf(
      item.source,
      extent,
      l10n,
      Localizations.localeOf(context).toString(),
    );
    if (facts.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        key: const Key('pending-facts'),
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final fact in facts)
            Semantics(
              label: fact.semantics,
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(fact.icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      fact.text,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
