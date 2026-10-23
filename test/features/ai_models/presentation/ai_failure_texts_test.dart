import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Lo que se le dice a la persona de cada clase de falla de la IA en la
/// nube (F39): qué pasó de verdad y qué hacer, sin confundir la falta de
/// internet con una espera vencida, una cuota o un servicio caído.
void main() {
  final locales = <String, AppLocalizations>{
    'es': AppLocalizationsEs(),
    'en': AppLocalizationsEn(),
  };

  for (final MapEntry(key: name, value: l10n) in locales.entries) {
    group('en $name', () {
      test('cada clase de falla tiene su motivo y su explicación', () {
        for (final failure in CloudModelFailure.values) {
          expect(
            aiFailureReason(l10n, failure),
            isNotEmpty,
            reason: '$failure',
          );
          expect(aiFailureHelp(l10n, failure), isNotEmpty, reason: '$failure');
        }
      });

      test('ninguna explicación repite a otra', () {
        final helps = [
          for (final failure in CloudModelFailure.values)
            aiFailureHelp(l10n, failure),
        ];
        expect(helps.toSet(), hasLength(helps.length));
        final reasons = [
          for (final failure in CloudModelFailure.values)
            aiFailureReason(l10n, failure),
        ];
        expect(reasons.toSet(), hasLength(reasons.length));
      });
    });
  }

  final es = AppLocalizationsEs();

  test(
    'la falta de internet, la espera vencida y el corte se dicen distinto',
    () {
      expect(es.lmHelpNetwork, contains('No hay conexión'));
      expect(es.lmHelpTimeout, contains('la conexión anda'));
      expect(es.lmHelpTimeout, isNot(contains('No hay conexión')));
      expect(es.lmHelpCutOff, contains('se cortó'));
      expect(es.lmHelpCutOff, isNot(contains('No hay conexión')));
    },
  );

  test('cada explicación dice qué hacer', () {
    // Una instrucción: probá, revisá, cargá, elegí, volvé…
    final acts = RegExp(
      'Prob[aá]|Revis[aá]|Carg[aá]|Eleg[ií]|Volv[eé]|Sigue',
      caseSensitive: false,
    );
    for (final failure in CloudModelFailure.values) {
      expect(
        acts.hasMatch(aiFailureHelp(es, failure)),
        isTrue,
        reason: '$failure: ${aiFailureHelp(es, failure)}',
      );
    }
  });

  test('«Reintentando (2 de 4)» lleva el intento y el motivo', () {
    final text = aiRetryingText(
      es,
      attempt: 2,
      maxAttempts: 4,
      failure: CloudModelFailure.network,
    );
    expect(text, startsWith('Reintentando (2 de 4)'));
    expect(text, contains(es.lmFailureNetwork));
  });
}
