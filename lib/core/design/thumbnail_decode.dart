import 'package:flutter/widgets.dart';

/// El ancho en píxeles al que conviene decodificar una imagen que se muestra
/// en [logicalWidth] puntos: el doble de lo que ocupa en pantalla.
///
/// Sin esto, una miniatura de 40×40 decodifica la foto entera —una de 12
/// megapíxeles son unos 48 MB de memoria— para mostrar unos pocos miles de
/// píxeles. El doble, y no lo justo, porque la miniatura se recorta para
/// cubrir su recuadro (`BoxFit.cover`): con solo el ancho fijado, una foto
/// apaisada de hasta 2:1 sigue cubriendo el alto sin verse borrosa.
int thumbnailDecodeWidth(BuildContext context, double logicalWidth) =>
    (logicalWidth * MediaQuery.devicePixelRatioOf(context) * 2).round();
