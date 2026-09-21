# Dispositivo

- Tipo: EMULADOR (los tiempos son de la máquina anfitriona; las cifras de memoria sí valen)
- Modelo: Google sdk_gphone16k_x86_64
- Android: 17 (API 37)
- SoC: ranchu
- RAM: 3.8 GB
- Libre en /data al empezar: 13.5 GB
- PC anfitriona: enchufada
- Temperatura de la batería al empezar: 25 °C (cargando: False)
- Flavor: staging (app.sinapsis.staging), modo profile
- Fecha: 2026-09-21 14:52

# Cómo leer estas cifras

Las mide `integration_test/map_benchmark_test.dart` (ver `../../README.md`, «El
mapa de conocimiento»). Los temas de la pantalla son los estructurados —con los
de la base, asignados al azar, el mapa entero es una sola comunidad—; lo demás sale
de la base sintética de 10.000 elementos y 2.000 temas, generada en el propio
emulador. Un emulador usa la CPU y la GPU de la PC: sus TIEMPOS son optimistas y no
valen como los de un teléfono de gama media.

## El criterio de cierre de F14 contra estas cifras

Interacción fluida con 2.000 temas: percentil 90 de armado y de raster por debajo
de 16,6 ms, y menos del 5 % de cuadros fuera del presupuesto.

| Vista y gesto (cuadros) | armado p90 | raster p90 | fuera de raster | ¿cumple? |
|---|---|---|---|---|
| esquema, arrastre (438) | 1,3 ms | 18,0 ms | 13,0 % | armado sí; raster no |
| panorama, arrastre (683) | 1,9 ms | 19,5 ms | 16,7 % | armado sí; raster no |
| panorama, dos dedos (494) | 0,9 ms | 24,1 ms | 42,9 % | armado sí; raster no |
| temas, 300 nodos, arrastre (297) | 3,5 ms | 38,9 ms | 61,3 % | armado sí; raster no |
| elementos, arrastre (468) | 1,9 ms | 9,0 ms | 4,7 % | sí |
| panorama + recálculo de fondo (662) | 2,1 ms | 18,5 ms | 15,4 % | armado sí (0,6 % fuera); raster no |

**El armado nunca es el problema** —el percentil 90 no pasa de 3,5 ms en ninguna
vista— y **el criterio de raster se cumple solo en el nivel de elementos**. Las
otras vistas quedan entre 1,1 y 2,3 veces por encima del presupuesto. Para
ubicarse: la línea de tiempo con 10.000 hechos, en este mismo emulador, dio un p90
de raster de 23,1 ms y 23 % de cuadros fuera (`../2026-09-21/`); el panorama y el
esquema del mapa están al nivel de ella o algo mejor, y el zoom con dos dedos y el
nivel de temas están peor.

Lo que sí se cumple, medido: que recalcular el mapa de fondo no detiene la
interfaz. Con el mapa recalculándose diez veces en 18 s mientras se arrastra, el
raster del panorama no empeora (p90 de 18,5 ms contra 19,5 sin recalcular) y el
armado pierde el 0,6 % de los cuadros.

Memoria: 191 MB residentes al empezar, 418 MB como máximo.
