# Benchmark de la bóveda sintética

> Reconstruido del registro de la corrida (`flutter drive` imprime cada informe). Es la PRIMERA medición en el emulador, hecha con el commit `a94e88d`, antes de `d15f2bf`: es la que mostró que «palabra en casi todo» tardaba 640 ms contra un objetivo de 300. El equipo se describía como «dispositivo sin describir» porque el guion todavía no pasaba la descripción al APK; era el mismo emulador, con la PC enchufada.


Esquema v20
Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM
Umbral: objetivo del encargo

```
búsqueda: palabra rara                         frío     19 ms   mediana     12 ms   objetivo 300 ms
búsqueda: palabra mediana                      frío     28 ms   mediana     25 ms   objetivo 300 ms
búsqueda: palabra en casi todo                 frío    638 ms   mediana    640 ms   objetivo 300 ms
búsqueda: dos palabras                         frío     15 ms   mediana     14 ms   objetivo 300 ms
búsqueda: prefijo                              frío    184 ms   mediana    183 ms   objetivo 300 ms
detalle: la fuente con más chunks              frío      1 ms   mediana      0 ms   objetivo 200 ms
detalle: una nota con enlaces                  frío      5 ms   mediana      4 ms   objetivo 200 ms
grafo local: panel, elemento típico            frío      1 ms   mediana      0 ms   objetivo 500 ms
grafo local: panel, el más conectado           frío     21 ms   mediana     23 ms   objetivo 500 ms
grafo local: pantalla, el más conectado        frío     82 ms   mediana     80 ms   objetivo 500 ms
línea de tiempo: leer los eventos              frío     58 ms   mediana     59 ms   objetivo 1000 ms
panel de salud: todos los indicadores          frío     25 ms   mediana     25 ms   objetivo 600 ms
vocabulario: estadísticas + candidatos         frío     54 ms   mediana     55 ms   objetivo 3000 ms
```
