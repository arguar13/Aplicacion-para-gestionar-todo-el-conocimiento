# Equipo

- Máquina: escritorio de quien construye la app (una notebook).
- Procesador: Intel Core i5-10300H.
- Sistema: Windows 11 (10.0.26200).
- Modo: profile, con `flutter drive -d windows --profile`. Es el código de la app
  de verdad, no el de `flutter test` (debug).
- PC ENCHUFADA.
- Fecha: 2026-09-21.

Es la referencia de escritorio de F14, medida como se mide un teléfono. No es un
teléfono. En esta máquina pintar es caro —la línea de tiempo con 157 rótulos
tardaba 35 ms por cuadro de raster—, así que sus cuadros son una cota pesimista
del dibujo: la referencia que cuenta para F14 es la del emulador
(`../../emulador-Google-sdk_gphone16k_x86_64-android17/2026-09-21-f14/`).

# El mapa en pantalla, antes y después de dos cambios

Las cifras de esta carpeta (`latest_map_screens_report.md` y los `.json`) son las
de DESPUÉS. Estas son las de ANTES, de la primera corrida completa del arnés con
10.000 elementos y 2.000 temas, cuando el nivel de temas dibujaba todas las
uniones —5.896 entre 300 temas— una por una. El resto de las vistas salió igual
en las dos corridas, dentro de lo que dos corridas iguales difieren.

| Nivel de temas, 300 nodos, arrastre sostenido | antes | después |
|---|---|---|
| uniones dibujadas | 5.896 | 1.196 |
| raster por cuadro (media) | 53,7 ms | 20,9 ms |
| raster por cuadro (p90) | 56,9 ms | 21,9 ms |
| cuadros fuera del presupuesto de raster | 236 de 236 | 547 de 547 |

Los cuadros fuera del presupuesto siguen siendo todos —cada uno tarda unos 21 ms,
por encima de los 16,6 del presupuesto—, pero ahora cada cuadro tarda 2,6 veces
menos, y en el mismo tiempo el gesto produce más del doble de cuadros (547 contra
236).

## De dónde salió ese cambio: un experimento, no una suposición

Antes de tocar el dibujo se midió qué costaba cada parte, apagándola. Mismo nivel
(300 nodos, 5.896 uniones), cuatro pasadas de arrastre de 1,5 s, raster por
cuadro:

| Qué se dibujaba | raster medio | p90 |
|---|---|---|
| todo | 47,4 ms | 50,8 ms |
| sin uniones | 15,7 ms | 24,8 ms |
| sin etiquetas | 40,3 ms | 43,3 ms |
| sin círculos | 40,6 ms | 43,8 ms |
| sin uniones ni etiquetas | 7,7 ms | 15,9 ms |
| sin nada | 3,2 ms | 5,5 ms |

Las uniones eran unos 32 de los 47 ms; las etiquetas y los círculos, unos 7 cada
uno. Agruparlas por color y grosor para dibujarlas con unas pocas llamadas ayudó
poco (de 53,7 a 48,1 ms): lo que costaba era dibujar miles, no llamar miles de
veces. Lo que las bajó fue dibujar menos: cada tema conserva las cuatro más
fuertes de las suyas (`strongestEdges`), que además es lo único que se puede
leer.

El experimento se hizo con un interruptor temporal que ya no está en el código;
este archivo es lo único que queda de él.

# Lo que el arnés encontró de paso

En el nivel de temas, arrastrar el mapa lo sacaba del nivel: al soltar un gesto
se comparaba el zoom con el umbral de alejamiento (0,42), y con 300 temas el
encuadre queda por debajo —arrastrar, que no toca el zoom, subía de nivel—. La
medición lo mostró como «0 temas a la vista» después de un arrastre. Ahora un
gesto solo cambia de nivel si cambió el zoom.
