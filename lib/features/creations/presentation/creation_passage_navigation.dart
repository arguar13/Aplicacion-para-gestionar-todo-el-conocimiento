/// «Ver en el documento» de lo que una creación cita de sus fuentes: una idea
/// del mapa mental (F43, paso 9) o una cita del guion de un podcast (F47, paso
/// 6). Un solo camino para las dos, así el salto al pasaje es el mismo en
/// todas.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/services/creation_passage.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_source_chips.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre la lectura de [documentId] —una fuente de [creation]— parada en el
/// pasaje de [quote], con el tramo marcado: el mismo salto de las citas del
/// chat y de «Abrir en el original».
///
/// - Si el pasaje no aparece en el texto, o no hay [quote], abre el documento
///   procesado, y si había pasaje avisa que no se encontró.
/// - Si no se sabe de qué documento sale ([documentId] `null`), muestra las
///   fuentes de la creación.
/// - Si el documento ya no está, lo dice: «Fuente borrada».
Future<void> openCreationPassage(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation, {
  required String? documentId,
  required String? quote,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  if (documentId == null) {
    await showCreationSources(context, creation);
    return;
  }
  final sources = (await ref.read(creationScopeResolverProvider).sourcesOf([
    documentId,
  ])).getOrElse((_) => const []);
  final source = sources.isEmpty ? null : sources.first;
  if (source == null || !source.isLive) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.f43StudioSourceDeleted)));
    return;
  }
  final itemId = source.sourceItemId;
  if (quote != null && quote.trim().isNotEmpty && itemId != null) {
    final range = await _locate(ref, itemId, quote);
    if (range != null) {
      unawaited(
        router.push(
          RoutePaths.reading(itemId, start: range.start, end: range.end),
        ),
      );
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.f43MindPassageMissing)));
  }
  unawaited(router.push(RoutePaths.processedDocument(documentId)));
}

/// Dónde está [quote] en el texto que abre la lectura de [itemId]
/// (`extractableRendition`: sus posiciones son las de ella). Un texto largo
/// —un libro— se recorre en otro hilo.
Future<PassageRange?> _locate(
  WidgetRef ref,
  String itemId,
  String quote,
) async {
  final item = (await ref.read(libraryRepositoryProvider).findById(itemId))
      .getOrElse((_) => null);
  final text = item == null ? null : extractableRendition(item)?.content;
  if (text == null || text.isEmpty) return null;
  if (text.length < _kInlineSearchChars) return findPassage(text, quote);
  return Isolate.run(() => findPassage(text, quote));
}

/// Hasta cuánto texto se busca el pasaje sin salir del hilo de la pantalla:
/// unas cuarenta páginas se recorren en milisegundos.
const _kInlineSearchChars = 100000;
