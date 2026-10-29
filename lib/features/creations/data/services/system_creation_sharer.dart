import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';

/// Si la hoja de compartir del sistema acepta archivos acá: `share_plus` los
/// pasa en Android, iOS, la web, macOS y Windows; en Linux no tiene cómo
/// (tira `UnimplementedError`), y ahí «Compartir» no se ofrece —«Descargar»
/// sí—.
bool systemShareSupportsFiles({bool isWeb = kIsWeb, TargetPlatform? platform}) {
  if (isWeb) return true;
  return (platform ?? defaultTargetPlatform) != TargetPlatform.linux;
}

/// Lo que abre la hoja de compartir del sistema con lo que se le pasa.
typedef SystemShare = Future<ShareResult> Function(ShareParams params);

/// Pasa el archivo de una creación a otra app con la hoja de compartir del
/// sistema (F43, M9): el PDF de la presentación, el PNG de la infografía, el
/// Markdown del informe… El archivo viaja armado en memoria
/// (`XFile.fromData`) y con su nombre de verdad (`fileNameOverrides`: sin
/// eso, `cross_file` le inventa uno en todas partes menos en la web).
///
/// `origin` es de dónde sale la hoja en un iPad o una Mac —la fila o el
/// botón que se tocó—; en el resto se ignora.
///
/// Cerrar la hoja sin elegir no es un error. Lo que falla de verdad sube, y
/// quien lo llama lo dice en una línea, igual que al descargar.
class SystemCreationSharer {
  /// [share] es la hoja: la de `SharePlus.instance`, o una de mentira en las
  /// pruebas (el paquete no exporta su interfaz de plataforma).
  SystemCreationSharer({SystemShare? share})
    : _share = share ?? SharePlus.instance.share;

  final SystemShare _share;

  Future<void> call(
    CreationExportFile file, {
    required String title,
    Rect? origin,
  }) async {
    await _share(
      ShareParams(
        files: [
          XFile.fromData(
            file.bytes,
            mimeType: file.mimeType,
            name: file.fileName,
          ),
        ],
        fileNameOverrides: [file.fileName],
        title: title,
        subject: title,
        sharePositionOrigin: origin,
        // En la web, si el navegador no comparte archivos, la descarga de
        // siempre —«Descargar» ya está al lado— y nunca un correo con el
        // archivo afuera.
        mailToFallbackEnabled: false,
      ),
    );
  }
}
