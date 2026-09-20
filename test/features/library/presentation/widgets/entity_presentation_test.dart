import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Cómo se muestra cada tipo de vínculo: que ninguno quede sin ícono, color,
/// nombre ni frase, en los dos idiomas.
///
/// El `switch` de cada extensión es exhaustivo, así que el compilador avisa si
/// un tipo nuevo se olvida; esto es lo que dice que lo que se agregó se lee
/// bien —y, en los tipos con sentido, que la frase cambia con la dirección—.
void main() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  final locales = <String, AppLocalizations>{
    'es': AppLocalizationsEs(),
    'en': AppLocalizationsEn(),
  };

  /// Los que se leen distinto según desde qué lado se mire.
  const directional = {
    RelationKind.continues,
    RelationKind.cites,
    RelationKind.summarizes,
    RelationKind.extractedFrom,
    RelationKind.indexes,
  };

  for (final MapEntry(key: locale, value: l10n) in locales.entries) {
    group('los tipos de vínculo en $locale', () {
      test('cada uno tiene ícono, color y un nombre corto', () {
        for (final kind in RelationKind.values) {
          expect(kind.icon, isA<IconData>(), reason: kind.name);
          expect(kind.color(scheme), isA<Color>(), reason: kind.name);
          expect(kind.shortLabel(l10n).trim(), isNotEmpty, reason: kind.name);
        }
      });

      test('los nombres cortos no se repiten: si no, el selector no los '
          'distingue', () {
        final labels = [
          for (final kind in RelationKind.values) kind.shortLabel(l10n),
        ];

        expect(labels.toSet(), hasLength(labels.length));
      });

      test('la frase nombra al otro elemento, y cambia con la dirección solo '
          'en los que la tienen', () {
        for (final kind in RelationKind.values) {
          final out = kind.describe(
            l10n,
            direction: RelationDirection.outgoing,
            otherItemTitle: 'Roma',
          );
          final incoming = kind.describe(
            l10n,
            direction: RelationDirection.incoming,
            otherItemTitle: 'Roma',
          );

          expect(out, contains('Roma'), reason: kind.name);
          expect(incoming, contains('Roma'), reason: kind.name);
          expect(
            out == incoming,
            !directional.contains(kind),
            reason: kind.name,
          );
        }
      });
    });
  }

  test('indexa se lee como un índice: «Indexa a» desde la nota de mapa y '
      '«Indexado en» desde lo indexado', () {
    final es = AppLocalizationsEs();

    expect(
      RelationKind.indexes.describe(
        es,
        direction: RelationDirection.outgoing,
        otherItemTitle: 'Roma',
      ),
      'Indexa a Roma',
    );
    expect(
      RelationKind.indexes.describe(
        es,
        direction: RelationDirection.incoming,
        otherItemTitle: 'Mapa de Roma',
      ),
      'Indexado en Mapa de Roma',
    );
  });
}
