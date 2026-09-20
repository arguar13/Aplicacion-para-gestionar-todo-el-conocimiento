# Benchmark de la bóveda sintética

Esquema v20
Equipo: escritorio, Windows 11 (10.0.26200), Intel Core i5-10300H, modo profile (flutter drive -d windows)
Umbral: objetivo del encargo

```
búsqueda: palabra rara                         frío     57 ms   mediana     51 ms   objetivo 300 ms
búsqueda: palabra mediana                      frío     69 ms   mediana     90 ms   objetivo 300 ms
búsqueda: palabra en casi todo                 frío    155 ms   mediana     88 ms   objetivo 300 ms
búsqueda: dos palabras                         frío     34 ms   mediana     31 ms   objetivo 300 ms
búsqueda: prefijo                              frío     98 ms   mediana     83 ms   objetivo 300 ms
detalle: la fuente con más chunks              frío      4 ms   mediana      1 ms   objetivo 200 ms
detalle: una nota con enlaces                  frío     26 ms   mediana     22 ms   objetivo 200 ms
grafo local: panel, elemento típico            frío      3 ms   mediana      1 ms   objetivo 500 ms
grafo local: panel, el más conectado           frío     58 ms   mediana    156 ms   objetivo 500 ms
grafo local: pantalla, el más conectado        frío    340 ms   mediana    200 ms   objetivo 500 ms
línea de tiempo: leer los eventos              frío    101 ms   mediana    115 ms   objetivo 1000 ms
panel de salud: todos los indicadores          frío     66 ms   mediana     78 ms   objetivo 600 ms
vocabulario: estadísticas + candidatos         frío    132 ms   mediana    135 ms   objetivo 3000 ms
```
