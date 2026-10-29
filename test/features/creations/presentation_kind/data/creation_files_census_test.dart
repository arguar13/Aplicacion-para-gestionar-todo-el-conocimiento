import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/creations/data/repositories/study_creation_repository_impl.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/test_vault.dart';
import '../support/presentation_fakes.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Las ilustraciones de una presentación (F43, paso 11) siguen a la
/// presentación por lo común de «Lo creado» (paso 12): la unión de bóvedas
/// las encuentra por el `illustration_ref` de cada diapositiva y copia las
/// que faltan, y borrarla para siempre se lleva su carpeta.
void main() {
  late TestVault tel;
  late TestVault pc;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
  });
  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  StudyCreationRepositoryImpl repositoryOf(
    TestVault vault, {
    InMemoryFileStore? files,
  }) => StudyCreationRepositoryImpl(
    database: vault.db,
    telemetry: _SilentTelemetry(),
    ids: FakeIdGenerator(prefix: 'c-${vault.deviceId}'),
    clock: () => vault.now,
    files: files,
  );

  /// Una presentación lista con una ilustración en la portada, en [path].
  Future<StudyCreation> ready(
    StudyCreationRepositoryImpl repository,
    String Function(String id) path,
  ) async {
    final created = (await repository.create(
      const CreationRequest(
        kind: StudyCreationKind.presentation,
        scope: CreationScope.allProcessed(),
        sourceIds: ['d'],
      ),
    )).getRight().toNullable()!;
    final content = PresentationContent(
      deck: SlideDeck(
        title: 'Éxodo',
        slides: [
          Slide.cover(title: 'Éxodo', illustrationRef: path(created.id)),
          const Slide.bullets(title: 'Ideas', bullets: ['Una']),
        ],
      ),
    );
    await repository.complete(
      created.id,
      title: 'Éxodo',
      content: content.encode(),
    );
    return (await repository.find(created.id)).getRight().toNullable()!;
  }

  test('la unión de bóvedas copia las ilustraciones de una presentación que '
      'llega', () async {
    pc.at(3);
    final c = await ready(
      repositoryOf(pc),
      (id) => 'originales/$id/ilustraciones/diapositiva-1.png',
    );
    final path = 'originales/${c.id}/ilustraciones/diapositiva-1.png';
    await pc.writeOriginal(path, 'imagen');

    final result = await tel.mergeFrom(pc);

    expect(result.filesCopied, 1);
    expect(tel.readOriginal(path), 'imagen');
    // Y la creación llegó con la diapositiva apuntando a su archivo.
    final arrived = PresentationContent.decode(
      (await tel.db.select(tel.db.studyCreations).getSingle()).contentJson,
    );
    expect(arrived.files, {path});
  });

  test('borrarla para siempre se lleva las ilustraciones que guardó', () async {
    final store = InMemoryFileStore();
    final files = CreationIllustrationStore(store);
    final repository = repositoryOf(tel, files: store);
    final paths = <String>[];
    final c = await ready(repository, (id) => 'originales/$id/ilustraciones/x');
    for (var slide = 0; slide < 2; slide++) {
      paths.add(
        await files.save(
          creationId: c.id,
          slotId: 'diapositiva-${slide + 1}',
          bytes: tinyPng(slide),
          mimeType: 'image/png',
        ),
      );
    }
    expect(store.paths.toSet(), paths.toSet());

    await repository.trash(c.id);
    // En la papelera se puede restaurar: los archivos siguen.
    expect(store.paths, hasLength(2));
    await repository.emptyTrash();
    expect(store.paths, isEmpty);
    expect(store.deletedFolders, [c.id]);
  });
}
