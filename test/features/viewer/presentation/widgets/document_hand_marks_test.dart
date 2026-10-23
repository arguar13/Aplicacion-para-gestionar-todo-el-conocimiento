import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_hand_marks.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_selection.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  Highlight hl(String id, int minute) => Highlight(
    id: id,
    renditionId: 'r',
    startOffset: 0,
    endOffset: 1,
    excerpt: 'x',
    createdAt: DateTime(2026, 10, 22, 10, minute),
  );

  group('en qué orden se pintan sobre el documento real', () {
    test('de abajo hacia arriba: por fecha y, a igual fecha, por id', () {
      final stacked = stackedHighlights([hl('b', 5), hl('z', 1), hl('a', 5)]);

      expect(stacked.map((h) => h.id), ['z', 'a', 'b']);
    });
  });

  group('lo que se le dice a la persona', () {
    final l10n = AppLocalizationsEs();

    test('cada problema tiene su aviso, y salir bien o no haber nada '
        'seleccionado no dice nada', () {
      expect(
        highlightIssueMessage(l10n, const HighlightOutcome.created([])),
        isNull,
      );
      expect(
        highlightIssueMessage(
          l10n,
          const HighlightOutcome.issue(HighlightIssue.nothingSelected),
        ),
        isNull,
      );
      expect(
        highlightIssueMessage(
          l10n,
          const HighlightOutcome.issue(HighlightIssue.scanned),
        ),
        l10n.documentHighlightScanned,
      );
      expect(
        highlightIssueMessage(
          l10n,
          const HighlightOutcome.issue(HighlightIssue.notLocated),
        ),
        l10n.documentHighlightNotLocated,
      );
    });

    test('no guardado: el motivo de la falla, o un aviso general', () {
      expect(
        highlightIssueMessage(
          l10n,
          const HighlightOutcome.issue(HighlightIssue.notSaved),
        ),
        l10n.documentHighlightNotSaved,
      );
      expect(
        highlightIssueMessage(
          l10n,
          const HighlightOutcome.issue(
            HighlightIssue.notSaved,
            failure: Failure.cache(message: 'x'),
          ),
        ),
        isNot(l10n.documentHighlightNotSaved),
      );
    });
  });
}
