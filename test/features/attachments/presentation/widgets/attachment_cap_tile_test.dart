import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_cap.dart';
import 'package:sinapsis/features/attachments/presentation/widgets/attachment_cap_tile.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('muestra el tope y se cambia desde el diálogo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AttachmentCapTile()),
        ),
      ),
    );

    expect(find.textContaining('Hasta 500,0 MB por elemento'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-attachment-cap')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('attachment-cap-${200 * 1024 * 1024}')),
    );
    await tester.pumpAndSettle();

    expect(container.read(attachmentCapProvider), 200 * 1024 * 1024);
    expect(find.textContaining('Hasta 200,0 MB por elemento'), findsOneWidget);
    expect(prefs.getInt('attachments_max_bytes_per_item'), 200 * 1024 * 1024);
  });
}
