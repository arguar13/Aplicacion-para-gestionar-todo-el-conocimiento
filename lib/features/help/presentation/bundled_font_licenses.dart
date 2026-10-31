import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Las licencias de las letras que la app lleva adentro (ver `fonts:` en
/// `pubspec.yaml` y `tool/fetch_creation_fonts.sh`), por el nombre de su
/// familia. Son todas la SIL Open Font License, que pide acompañar la letra
/// con su licencia: Flutter junta solas las de los paquetes, pero no sabe de
/// estas, que no vienen de ningún paquete.
const kBundledFontLicenses = <String, String>{
  'Inter': 'assets/fonts/LICENSE.txt',
  'Caveat': 'assets/fonts/Caveat-OFL.txt',
  'JetBrains Mono': 'assets/fonts/JetBrainsMono-OFL.txt',
  'Lora': 'assets/fonts/Lora-OFL.txt',
  'Nunito': 'assets/fonts/Nunito-OFL.txt',
  'Playfair Display': 'assets/fonts/PlayfairDisplay-OFL.txt',
  'Source Sans 3': 'assets/fonts/SourceSans3-OFL.txt',
  'Space Grotesk': 'assets/fonts/SpaceGrotesk-OFL.txt',
};

var _registered = false;

/// Suma [kBundledFontLicenses] a las licencias que muestra
/// `showLicensePage` (F47, paso 7). Una vez por arranque: el registro las
/// acumula, y dos veces las mostraría repetidas. Los textos se leen recién
/// cuando la página de licencias los pide.
void registerBundledFontLicenses({AssetBundle? bundle}) {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final assets = bundle ?? rootBundle;
    for (final MapEntry(key: family, value: path)
        in kBundledFontLicenses.entries) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await assets.loadString(path, cache: false));
    }
  });
}

/// Deja volver a registrarlas, para las pruebas que vacían el registro
/// (`LicenseRegistry.reset`).
@visibleForTesting
void debugResetBundledFontLicenses() => _registered = false;
