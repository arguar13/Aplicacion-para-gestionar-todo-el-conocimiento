# Benchmark de la bóveda sintética

Esquema v20
Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM
Umbral: objetivo del encargo

```
búsqueda: palabra rara                         frío    139 ms   mediana     78 ms   objetivo 300 ms
búsqueda: palabra mediana                      frío    264 ms   mediana     46 ms   objetivo 300 ms
búsqueda: palabra en casi todo                 frío     73 ms   mediana     53 ms   objetivo 300 ms
búsqueda: dos palabras                         frío     18 ms   mediana     22 ms   objetivo 300 ms
búsqueda: prefijo                              frío     91 ms   mediana     60 ms   objetivo 300 ms
detalle: la fuente con más chunks              frío      3 ms   mediana      0 ms   objetivo 200 ms
detalle: una nota con enlaces                  frío      8 ms   mediana      6 ms   objetivo 200 ms
grafo local: panel, elemento típico            frío     11 ms   mediana      1 ms   objetivo 500 ms
grafo local: panel, el más conectado           frío     31 ms   mediana     34 ms   objetivo 500 ms
grafo local: pantalla, el más conectado        frío    120 ms   mediana    109 ms   objetivo 500 ms
línea de tiempo: leer los eventos              frío     83 ms   mediana     83 ms   objetivo 1000 ms
panel de salud: todos los indicadores          frío     36 ms   mediana     35 ms   objetivo 600 ms
vocabulario: estadísticas + candidatos         frío    104 ms   mediana     81 ms   objetivo 3000 ms
```
