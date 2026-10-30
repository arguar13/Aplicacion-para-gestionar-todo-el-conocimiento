import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/domain/services/video_text_notices.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/features/transform/presentation/widgets/video_text_notice_listener.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// El aviso de la red de seguridad del idioma (F45, paso 4): esté en la
/// pantalla que esté, dice que los subtítulos no estaban en el idioma que se
/// habla y que el texto sale del audio; con su ✕.
void main() {
  final es = AppLocalizationsEs();
  const title = 'Las reliquias de San Francisco';

  Future<VideoTextNoticeBus> pump(WidgetTester tester) async {
    final bus = VideoTextNoticeBus();
    addTearDown(bus.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoTextNoticeBusProvider.overrideWithValue(bus)],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => VideoTextNoticeListener(child: child!),
          home: const Scaffold(body: Text('Biblioteca')),
        ),
      ),
    );
    return bus;
  }

  testWidgets('dice en qué estaban, qué se habla y que se transcribe el '
      'audio; se cierra con su ✕', (tester) async {
    final bus = await pump(tester);

    bus.notify(
      const ForeignCaptionsNotice(
        itemId: 'v',
        title: title,
        foundLanguage: 'ar',
        audioLanguage: 'es',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(es.f45S4ForeignCaptionsAudio(title, 'árabe', 'español')),
      findsOneWidget,
    );
    // El aviso común (`AppSnackBar`): con la ✕, porque dura más que uno
    // corto.
    final snack = tester.widget<SnackBar>(
      find.byKey(const Key('foreign-captions-notice')),
    );
    expect(snack.showCloseIcon, isTrue);
    expect(snack.duration, kForeignCaptionsNoticeDuration);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('foreign-captions-notice')), findsNothing);
  });

  testWidgets('donde no se puede transcribir, dice que queda la descripción; '
      'un idioma que no se reconoce es «otro idioma»', (tester) async {
    final bus = await pump(tester);

    bus.notify(
      const ForeignCaptionsNotice(
        itemId: 'v',
        title: title,
        audioLanguage: 'es',
        transcribing: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        es.f45S4ForeignCaptionsNoAudio(title, 'otro idioma', 'español'),
      ),
      findsOneWidget,
    );
  });
}
