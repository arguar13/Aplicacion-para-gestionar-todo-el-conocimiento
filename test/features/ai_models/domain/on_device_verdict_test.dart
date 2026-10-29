import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/device_profile.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/entities/on_device_image_model.dart';
import 'package:sinapsis/features/ai_models/domain/services/on_device_verdict.dart';

import '../../../support/on_device_harness.dart';

const _sdxs = OnDeviceImageModel.sdxs;
const _turbo = OnDeviceImageModel.sdTurbo;

OnDeviceVerdict _verdict(
  OnDeviceImageModel model,
  DeviceProfile device, {
  bool downloaded = false,
  bool closed = false,
}) => onDeviceVerdict(
  model,
  device,
  downloaded: downloaded,
  closedLastTime: closed,
);

void main() {
  group('la memoria como la dice la ficha del teléfono', () {
    test(
      'lo que ve el sistema se lleva a la medida comercial que lo cubre',
      () {
        int? gb(double gib) => DeviceProfile(
          android: true,
          arm64: true,
          totalRamBytes: (gib * kGiB).round(),
        ).ramGb;

        // Un Redmi Note 13 Pro+ de 12 GB ve unos 11,2.
        expect(gb(11.2), 12);
        expect(gb(7.4), 8);
        expect(gb(5.6), 6);
        expect(gb(8), 8);
        expect(gb(8.01), 10);
        expect(gb(40), 40);
      },
    );

    test('sin dato, no se sabe (nunca cero)', () {
      expect(const DeviceProfile(android: true, arm64: true).ramGb, isNull);
      expect(
        const DeviceProfile(android: true, arm64: true, totalRamBytes: 0).ramGb,
        isNull,
      );
    });
  });

  group('«Tu teléfono: puede / justo / no alcanza»', () {
    test('con 12 GB, los dos pueden', () {
      final phone = phoneWith();
      expect(_verdict(_sdxs, phone).level, OnDeviceVerdictLevel.can);
      final turbo = _verdict(_turbo, phone);
      expect(turbo.level, OnDeviceVerdictLevel.can);
      expect(turbo.failure, isNull);
      expect(
        turbo.reasons.single,
        isA<RamFacts>()
            .having((r) => r.ramGb, 'ram', 12)
            .having((r) => r.minGb, 'min', 8)
            .having((r) => r.recommendedGb, 'recomendada', 12),
      );
    });

    test('con 8 GB, SDXS puede y SD-Turbo justo', () {
      final phone = phoneWith(ramGb: 8);
      expect(_verdict(_sdxs, phone).level, OnDeviceVerdictLevel.can);
      expect(_verdict(_turbo, phone).level, OnDeviceVerdictLevel.tight);
    });

    test('con 6 GB, SDXS justo y SD-Turbo no alcanza, por la memoria', () {
      final phone = phoneWith(ramGb: 6);
      expect(_verdict(_sdxs, phone).level, OnDeviceVerdictLevel.tight);
      final turbo = _verdict(_turbo, phone);
      expect(turbo.level, OnDeviceVerdictLevel.cannot);
      expect(turbo.failure, ImageFailure.deviceTooSmall);
    });

    test('con 4 GB, ninguno', () {
      final phone = phoneWith(ramGb: 4);
      expect(_verdict(_sdxs, phone).cannot, isTrue);
      expect(_verdict(_turbo, phone).cannot, isTrue);
    });

    test('sin saber la memoria, justo: no se promete nada', () {
      final verdict = _verdict(_sdxs, phoneWith(ramGb: null));
      expect(verdict.level, OnDeviceVerdictLevel.tight);
      expect(
        verdict.reasons.single,
        isA<RamFacts>().having((r) => r.ramGb, 'ram', isNull),
      );
    });

    test(
      'fuera de Android, de 32 bits o sin ARMv8.2: el teléfono no puede',
      () {
        for (final phone in [
          phoneWith(android: false),
          phoneWith(arm64: false),
          phoneWith(cpu: false),
        ]) {
          final verdict = _verdict(_sdxs, phone);
          expect(verdict.level, OnDeviceVerdictLevel.cannot, reason: '$phone');
          expect(verdict.failure, ImageFailure.unsupportedDevice);
          expect(verdict.reasons, hasLength(1));
        }
        expect(
          _verdict(_sdxs, phoneWith(android: false)).reasons.single,
          isA<NotAndroid>(),
        );
        expect(
          _verdict(_sdxs, phoneWith(arm64: false)).reasons.single,
          isA<Not64BitArm>(),
        );
        expect(
          _verdict(_sdxs, phoneWith(cpu: false)).reasons.single,
          isA<CpuTooOld>(),
        );
        // Sin poder leer el procesador no se descarta.
        expect(_verdict(_sdxs, phoneWith(cpu: null)).cannot, isFalse);
      },
    );

    test(
      'sin lugar para bajarlo no alcanza; ya bajado, el lugar no importa',
      () {
        // SD-Turbo pesa 2 GB: con 1 GB libre no entra.
        final phone = phoneWith(freeGb: 1);
        final verdict = _verdict(_turbo, phone);
        expect(verdict.cannot, isTrue);
        expect(verdict.failure, ImageFailure.deviceTooSmall);
        final short = verdict.reasons.whereType<StorageShort>().single;
        expect(short.freeBytes, kGiB);
        expect(short.neededBytes, _turbo.spec.bytes + kOnDeviceStorageMargin);
        // Lo que impide va primero.
        expect(verdict.reasons.first, isA<StorageShort>());

        expect(
          _verdict(_turbo, phone, downloaded: true).level,
          OnDeviceVerdictLevel.can,
        );
        // SDXS (883 MB + el margen) sí entra en 2 GB.
        expect(_verdict(_sdxs, phoneWith(freeGb: 2)).cannot, isFalse);
      },
    );

    test('justo al margen: lo que pesa más el margen alcanza', () {
      final needed = _sdxs.spec.bytes + kOnDeviceStorageMargin;
      DeviceProfile withFree(int free) => DeviceProfile(
        android: true,
        arm64: true,
        cpuSupported: true,
        totalRamBytes: 12 * kGiB,
        freeStorageBytes: free,
      );
      expect(_verdict(_sdxs, withFree(needed)).cannot, isFalse);
      expect(_verdict(_sdxs, withFree(needed - 1)).cannot, isTrue);
    });

    test('si la app se cerró dibujando, se apaga solo y lo dice primero', () {
      final verdict = _verdict(
        _sdxs,
        phoneWith(),
        downloaded: true,
        closed: true,
      );
      expect(verdict.level, OnDeviceVerdictLevel.cannot);
      expect(verdict.failure, ImageFailure.notEnoughMemory);
      expect(verdict.reasons.first, isA<ClosedLastTime>());
      expect(verdict.reasons.whereType<RamFacts>(), hasLength(1));
    });
  });

  test('los modelos, como se verificaron en sus fichas el 2026-10-28', () {
    expect(
      _sdxs.spec.downloadUrl,
      'https://huggingface.co/akleine/sdxs-512/resolve/'
      '17ef024d73ebee1db9b0643f9c90454dae6c5772/sdxs.safetensors',
    );
    expect(_sdxs.spec.bytes, 882587118);
    expect(
      _sdxs.spec.officialUrl,
      'https://huggingface.co/IDKiro/sdxs-512-dreamshaper',
    );
    expect(
      _turbo.spec.downloadUrl,
      'https://huggingface.co/Green-Sky/SD-Turbo-GGUF/resolve/'
      '19a31586d02d64a73b4419bc193b3ecfaf38e1f0/sd_turbo-f16-q8_0.gguf',
    );
    expect(_turbo.spec.bytes, 2023745376);
    expect(
      _turbo.spec.officialUrl,
      'https://huggingface.co/stabilityai/sd-turbo',
    );
    // Un paso y sin guía, como pide stable-diffusion.cpp para los dos.
    for (final model in OnDeviceImageModel.values) {
      expect(model.spec.steps, 1);
      expect(model.spec.cfg, 1);
      expect(model.spec.sha256, hasLength(64));
      expect(OnDeviceImageModel.byId(model.spec.id), model);
    }
    expect(OnDeviceImageModel.byId('otro'), isNull);
  });
}
