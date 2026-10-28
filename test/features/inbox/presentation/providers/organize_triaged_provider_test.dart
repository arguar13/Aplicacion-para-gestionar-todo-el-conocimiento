import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';

import '../../../../support/fake_ai_organize_queue.dart';

/// Lo triado va a la IA (F41, paso 6): el gancho de `TriageIntoProcessed` en
/// la app es la cola, leída recién al triar.
void main() {
  test('le pasa el documento a la cola, y armarlo no la arranca', () {
    final queue = FakeAiOrganizeQueue();
    var built = 0;
    final container = ProviderContainer(
      overrides: [
        aiOrganizeQueueProvider.overrideWith((ref) {
          built++;
          return queue;
        }),
      ],
    );
    addTearDown(container.dispose);

    final organize = container.read(organizeTriagedProvider);
    expect(built, 0);

    organize('documento');

    expect(queue.processedForOrganizing, ['documento']);
    expect(queue.organizeNowCalls, isEmpty);
  });
}
