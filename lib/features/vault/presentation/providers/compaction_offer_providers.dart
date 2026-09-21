import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_compaction_providers.dart';

/// Si la oferta de compactar ya se contestó —abriendo la pantalla o
/// descartándola—, entre reinicios: la oferta es UNA, no un recordatorio.
class CompactionOfferNotifier extends StateNotifier<bool> {
  CompactionOfferNotifier({required SharedPreferences prefs})
    : _prefs = prefs,
      super(prefs.getBool(_prefsKey) ?? false);

  static const _prefsKey = 'compaction_offer_answered';

  final SharedPreferences _prefs;

  Future<void> markAnswered() async {
    state = true;
    await _prefs.setBool(_prefsKey, true);
  }
}

final compactionOfferAnsweredProvider =
    StateNotifierProvider<CompactionOfferNotifier, bool>((ref) {
      return CompactionOfferNotifier(
        prefs: ref.watch(sharedPreferencesProvider),
      );
    });

/// La medición a ofrecer, o `null` si no hay oferta: ya se contestó, o no hay
/// tanto para devolver como para molestar (ver
/// [CompactionAssessment.worthOffering]).
final compactionOfferProvider =
    FutureProvider.autoDispose<CompactionAssessment?>((ref) async {
      if (ref.watch(compactionOfferAnsweredProvider)) return null;
      final assessment = await ref.watch(compactionAssessmentProvider.future);
      return assessment.worthOffering ? assessment : null;
    });
