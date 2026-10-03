import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/ai_certainty.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_space_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/space_chooser.dart';

import '../../../../support/ai_organize_harness.dart';

void main() {
  late AiOrganizeHarness vault;
  late AutoSpaceStep step;
  SpaceChoice? answer;
  late List<List<String>> asked;
  late String historia;

  setUp(() async {
    vault = AiOrganizeHarness();
    answer = null;
    asked = [];
    step = AutoSpaceStep(
      chooser: ({required itemTitle, required excerpt, required spaces}) async {
        asked.add(spaces);
        return answer;
      },
      organize: vault.organize,
      library: vault.library,
    );
    await vault.organize.createSpace('Cocina');
    historia = (await vault.organize.createSpace(
      'Historia',
    )).getOrElse((f) => fail('$f')).id;
  });

  tearDown(() => vault.close());

  test('con certeza alta, lo pone en el tema que eligió', () async {
    final item = await vault.source('a', title: 'Roma', content: 'Roma.');
    answer = const SpaceChoice(index: 1, certainty: AiCertainty.high);

    final report = await step.organize(item, runId: 'run');

    expect(report.applied, 1);
    // Los temas que existen, en orden alfabético: nunca uno nuevo.
    expect(asked.single, ['Cocina', 'Historia']);
    expect((await vault.reload('a')).spaceId, historia);
  });

  test('con certeza media, o sin tema, no lo mueve', () async {
    final item = await vault.source('a', title: 'Roma', content: 'Roma.');
    for (final doubtful in [
      const SpaceChoice(index: 1, certainty: AiCertainty.medium),
      const SpaceChoice(index: 1),
      null,
    ]) {
      answer = doubtful;
      expect(await step.organize(item, runId: 'run'), AiStepReport.nothing);
    }
    expect((await vault.reload('a')).spaceId, isNull);
  });

  test(
    'lo que ya tiene tema, o una biblioteca sin temas, ni se pregunta',
    () async {
      await vault.source('a', title: 'Roma', content: 'Roma.');
      await vault.library.assignSpace(itemId: 'a', spaceId: historia);
      answer = const SpaceChoice(index: 0, certainty: AiCertainty.high);

      await step.organize(await vault.reload('a'), runId: 'run');

      expect(asked, isEmpty);
      expect((await vault.reload('a')).spaceId, historia);
    },
  );

  test(
    'si la persona le puso tema mientras el modelo pensaba, gana ella',
    () async {
      final item = await vault.source('a', title: 'Roma', content: 'Roma.');
      final cocina = (await vault.organize.watchAllSpaces().first).first.id;
      step = AutoSpaceStep(
        chooser:
            ({required itemTitle, required excerpt, required spaces}) async {
              await vault.library.assignSpace(itemId: 'a', spaceId: cocina);
              return const SpaceChoice(index: 1, certainty: AiCertainty.high);
            },
        organize: vault.organize,
        library: vault.library,
      );

      expect(await step.organize(item, runId: 'run'), AiStepReport.nothing);
      expect((await vault.reload('a')).spaceId, cocina);
    },
  );

  group('parseSpaceChoice', () {
    test('lee el número y la certeza', () {
      expect(
        parseSpaceChoice('TEMA: 2 | alta', spaceCount: 3),
        const SpaceChoice(index: 1, certainty: AiCertainty.high),
      );
      expect(
        parseSpaceChoice('Pienso que...\ntema: 1|Media', spaceCount: 3),
        const SpaceChoice(index: 0, certainty: AiCertainty.medium),
      );
      expect(
        parseSpaceChoice('TEMA: 3', spaceCount: 3),
        const SpaceChoice(index: 2),
      );
    });

    test(
      '«ninguno», un número fuera de la lista o nada legible es ninguno',
      () {
        expect(parseSpaceChoice('TEMA: ninguno', spaceCount: 3), isNull);
        expect(parseSpaceChoice('TEMA: 4 | alta', spaceCount: 3), isNull);
        expect(parseSpaceChoice('TEMA: 0 | alta', spaceCount: 3), isNull);
        expect(parseSpaceChoice('Historia', spaceCount: 3), isNull);
      },
    );
  });
}
