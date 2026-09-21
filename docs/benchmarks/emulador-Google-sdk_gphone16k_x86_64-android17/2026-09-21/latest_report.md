# Benchmark de la bóveda sintética

Esquema v20
Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM
Umbral: objetivo del encargo

```
búsqueda: palabra rara                         frío    173 ms   mediana     13 ms   objetivo 300 ms
búsqueda: palabra mediana                      frío    143 ms   mediana     26 ms   objetivo 300 ms
búsqueda: palabra en casi todo                 frío     84 ms   mediana     44 ms   objetivo 300 ms
búsqueda: dos palabras                         frío     84 ms   mediana     14 ms   objetivo 300 ms
búsqueda: prefijo                              frío     57 ms   mediana     41 ms   objetivo 300 ms
detalle: la fuente con más chunks              frío     12 ms   mediana      0 ms   objetivo 200 ms
detalle: una nota con enlaces                  frío    112 ms   mediana      5 ms   objetivo 200 ms
grafo local: panel, elemento típico            frío      9 ms   mediana      0 ms   objetivo 500 ms
grafo local: panel, el más conectado           frío    322 ms   mediana     29 ms   objetivo 500 ms
grafo local: pantalla, el más conectado        frío    211 ms   mediana     80 ms   objetivo 500 ms
línea de tiempo: leer los eventos              frío     57 ms   mediana     58 ms   objetivo 1000 ms
panel de salud: todos los indicadores          frío     36 ms   mediana     24 ms   objetivo 600 ms
vocabulario: estadísticas + candidatos         frío     56 ms   mediana     57 ms   objetivo 3000 ms
```
