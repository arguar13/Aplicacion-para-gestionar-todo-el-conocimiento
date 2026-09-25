import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/imported_reference.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_fuzzy_index.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_identity_index.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_import_report.dart';
import 'package:sinapsis/features/reference/domain/repositories/reference_fuzzy_match_repository.dart';
import 'package:sinapsis/features/reference/domain/repositories/reference_identity_repository.dart';
import 'package:sinapsis/features/reference/domain/services/attachment_file_name.dart';
import 'package:sinapsis/features/reference/domain/services/bibtex/bibtex_parser.dart';
import 'package:sinapsis/features/reference/domain/services/ris/ris_parser.dart';
import 'package:sinapsis/features/reference/domain/usecases/attach_reference_file_usecase.dart';
import 'package:sinapsis/features/reference/domain/usecases/import_reference_entry_usecase.dart';

/// Importa un `.bib` o un `.ris` entero (F15, D9/D14/D15.3): entre los
/// archivos que se eligieron juntos, el primero con esa extensión es la
/// bibliografía; el resto son candidatos a adjuntarse por su nombre.
///
/// Arma los índices de identidad y de coincidencia difusa UNA sola vez
/// —nunca una consulta por entrada, D9— y llama a
/// [ImportReferenceEntryUseCase] y a [AttachReferenceFileUseCase] por cada
/// una, sumando el informe. Una entrada que falla al guardarse —no al
/// entenderse, eso ya lo filtró el analizador— se cuenta como saltada y NO
/// aborta el resto: miles de referencias no pueden depender de que la
/// primera mala tire abajo todo el archivo.
///
/// El archivo entero entra en UN solo lote (`LibraryRepository.runBulk`,
/// F15, comando 16; F19, 19.4): guardar cada entrada por separado —cada
/// una con su propio `save`, su propia confirmación, su propio índice de
/// texto reconstruido fila por fila— es lo que hacía que importar 5.000
/// entradas tardara más de 20 s incluso en escritorio. Un fallo de verdad
/// inesperado —no una entrada saltada, que ya se maneja arriba y nunca
/// llega a lanzar— deshace el archivo entero: mejor eso que una importación
/// a medias sin que nadie lo haya pedido.
class ImportReferencesFileUseCase {
  ImportReferencesFileUseCase({
    required LibraryRepository library,
    required ReferenceIdentityRepository identity,
    required ReferenceFuzzyMatchRepository fuzzyMatch,
    required ImportReferenceEntryUseCase importEntry,
    required AttachReferenceFileUseCase attachFile,
  }) : _library = library,
       _identity = identity,
       _fuzzyMatch = fuzzyMatch,
       _importEntry = importEntry,
       _attachFile = attachFile;

  final LibraryRepository _library;
  final ReferenceIdentityRepository _identity;
  final ReferenceFuzzyMatchRepository _fuzzyMatch;
  final ImportReferenceEntryUseCase _importEntry;
  final AttachReferenceFileUseCase _attachFile;

  /// Un `.bib`/`.ris` más grande que esto no se analiza (F15, criterio de
  /// cierre): el analizador arma un árbol de entradas en memoria varias veces
  /// más grande que el texto, y un archivo de cientos de MB —el tope general
  /// de `CapturedFile.maxBytes`— se llevaría la app por delante antes de
  /// terminar de leerlo entero.
  static const maxBytes = 30 * 1024 * 1024;

  Future<Either<Failure, ReferenceImportReport>> call(
    List<CapturedFile> files, {
    bool prioritizeIncoming = false,
  }) async {
    final bibliographyFile = _findBibliographyFile(files);
    if (bibliographyFile == null) {
      return left(
        const Failure.validation(
          message: 'Ninguno de los archivos elegidos es un .bib o un .ris.',
        ),
      );
    }
    if (bibliographyFile.bytes.length > maxBytes) {
      return left(
        const Failure.validation(
          message:
              'El archivo pesa más de $maxBytes bytes: es demasiado '
              'grande para analizarlo entero.',
        ),
      );
    }
    final attachments = [
      for (final file in files)
        if (file != bibliographyFile) file,
    ];

    final (entries, skipped) = _parse(bibliographyFile);

    final report = await _library.runBulk(() async {
      final index = await _identity.buildIndex();
      final fuzzyIndex = await _fuzzyMatch.buildIndex();

      var report = ReferenceImportReport(skipped: skipped);
      for (final entry in entries) {
        report =
            report +
            await _importOne(
              entry,
              index,
              fuzzyIndex,
              attachments,
              prioritizeIncoming: prioritizeIncoming,
            );
      }
      return report;
    });
    return right(report);
  }

  Future<ReferenceImportReport> _importOne(
    ImportedReference entry,
    ReferenceIdentityIndex index,
    ReferenceFuzzyIndex fuzzyIndex,
    List<CapturedFile> attachments, {
    required bool prioritizeIncoming,
  }) async {
    final imported = await _importEntry(
      entry,
      index,
      fuzzyIndex,
      prioritizeIncoming: prioritizeIncoming,
    );
    final failure = imported.getLeft().toNullable();
    if (failure != null) {
      return ReferenceImportReport(
        skipped: [
          ReferenceImportSkip(
            key: entry.reference.citationKey ?? entry.title ?? '(sin clave)',
            reason: failure.message,
          ),
        ],
      );
    }
    final result = imported.getRight().toNullable()!;

    final attachedItemIds = <String>[];
    final match = matchAttachmentFile(entry.attachmentFileName, attachments);
    if (match != null) {
      final linked = await _attachFile(result.itemId, match);
      if (linked.isRight()) attachedItemIds.add(result.itemId);
    }

    return ReferenceImportReport(
      created: result.outcome == ImportedReferenceOutcome.created ? 1 : 0,
      updated: result.outcome == ImportedReferenceOutcome.updated ? 1 : 0,
      unchanged: result.outcome == ImportedReferenceOutcome.unchanged ? 1 : 0,
      attachedItemIds: attachedItemIds,
      possibleDuplicates: result.possibleDuplicates,
    );
  }

  CapturedFile? _findBibliographyFile(List<CapturedFile> files) {
    for (final file in files) {
      final extension = p.extension(file.name).toLowerCase();
      if (extension == '.bib' || extension == '.ris') return file;
    }
    return null;
  }

  (List<ImportedReference>, List<ReferenceImportSkip>) _parse(
    CapturedFile file,
  ) {
    final text = utf8.decode(file.bytes, allowMalformed: true);
    if (p.extension(file.name).toLowerCase() == '.ris') {
      final result = parseRis(text);
      return (
        result.entries,
        [
          for (final skip in result.skipped)
            ReferenceImportSkip(
              key: skip.id ?? '(sin ID)',
              reason: 'tipo no reconocido: ${skip.type}',
            ),
        ],
      );
    }
    final result = parseBibtex(text);
    return (
      result.entries,
      [
        for (final skip in result.skipped)
          ReferenceImportSkip(key: skip.key, reason: skip.reason),
      ],
    );
  }
}
