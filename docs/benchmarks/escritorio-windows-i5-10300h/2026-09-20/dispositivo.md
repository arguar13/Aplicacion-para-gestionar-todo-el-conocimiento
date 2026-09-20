# Equipo

- Máquina: escritorio de quien construye la app.
- Procesador: Intel Core i5-10300H.
- Sistema: Windows 11 (10.0.26200).
- Modo: profile, con `flutter drive -d windows`. Es el código de la app de
  verdad, no el de `flutter test` (debug).
- Fecha: 2026-09-20.

Es la referencia de escritorio de F12, medida como se medirá un teléfono, para
poder comparar las dos columnas. No es un teléfono: no dice nada de un Android
de gama media.

# La línea de tiempo con 10.000 hechos

157 eventos en pantalla, doce pasadas de arrastre de 1,5 s. Antes es un widget
por evento; después, un solo lienzo (commit «los eventos de la línea de tiempo
se dibujan en un solo lienzo»).

| | antes (dos corridas) | después |
|---|---|---|
| armar un cuadro (media) | 22 a 28 ms | 4,1 ms |
| armar un cuadro (p99) | 71 a 85 ms | 12,9 ms |
| cuadros que pasan el presupuesto de armado | 233 de 299 y 281 de 361 | 3 de 527 |
| pintar un cuadro (media) | 49 a 62 ms | 35 ms |
| pintar un cuadro (p99) | 135 ms | 84 ms |
| recolecciones de basura, generación nueva / vieja | 388 a 428 / 210 a 232 | 136 / 18 |
| memoria residente máxima | 485 MB | 461 MB |
| abrir la pantalla con 10.000 hechos | 428 ms | 254 ms |

Lo que queda: pintar sigue tardando más de 16 ms por cuadro en esta máquina. Casi
todo son los 157 rótulos (sin ellos, pintar baja a 14 ms). Cómo le va en un
teléfono lo dirán sus cifras; si hace falta, el siguiente paso es dibujar la
capa de eventos una vez y desplazarla mientras se arrastra.

# La apertura de la app con 10.000 elementos

330 ms desde que se monta la app hasta la primera lista, sin el PIN y sin
contar el arranque del motor.
