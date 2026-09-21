# Benchmark de la bóveda sintética

Esquema v21
Equipo: escritorio, Windows 11 (10.0.26200), Intel Core i5-10300H, modo profile (flutter drive -d windows), PC a BATERÍA (los tiempos salen de 2 a 5 veces peores)
Umbral: objetivo del encargo

```
búsqueda: palabra rara                         frío     44 ms   mediana     89 ms   objetivo 300 ms
búsqueda: palabra mediana                      frío    144 ms   mediana    127 ms   objetivo 300 ms
búsqueda: palabra en casi todo                 frío     84 ms   mediana    133 ms   objetivo 300 ms
búsqueda: dos palabras                         frío     60 ms   mediana     59 ms   objetivo 300 ms
búsqueda: prefijo                              frío    178 ms   mediana    172 ms   objetivo 300 ms
detalle: la fuente con más chunks              frío      5 ms   mediana      3 ms   objetivo 200 ms
detalle: una nota con enlaces                  frío      3 ms   mediana      2 ms   objetivo 200 ms
detalle: el elemento más conectado             frío    590 ms   mediana    556 ms
grafo local: panel, elemento típico            frío      8 ms   mediana      5 ms   objetivo 500 ms
grafo local: panel, el más conectado           frío    134 ms   mediana    114 ms   objetivo 500 ms
grafo local: pantalla, el más conectado        frío    329 ms   mediana    264 ms   objetivo 500 ms
línea de tiempo: leer los eventos              frío     97 ms   mediana    121 ms   objetivo 1000 ms
panel de salud: todos los indicadores          frío    110 ms   mediana    108 ms   objetivo 600 ms
filtro: tema raíz grande (con subtemas)        frío     38 ms   mediana     39 ms   objetivo 300 ms
filtro: una hoja (sin subtemas)                frío      9 ms   mediana      7 ms   objetivo 300 ms
filtro: los ids de todo el tema raíz grande    frío     32 ms   mediana     32 ms
D3: CTE recursiva, elementos del tema raíz grande frío     21 ms   mediana     21 ms
D3: cierre materializado, lo mismo             frío     20 ms   mediana     22 ms
Atlas: abrir (agregados + armado del árbol)    frío    251 ms   mediana    266 ms   objetivo 500 ms
Atlas: reabrir con la caché                    frío    253 ms   mediana      0 ms
Atlas: leer los elementos y las notas mapa (SQL) frío    131 ms   mediana    131 ms
Atlas: buscar un tema (letras sueltas)         frío      9 ms   mediana      6 ms
Atlas: exportar a Markdown                     frío     40 ms   mediana     40 ms
vocabulario: estadísticas + candidatos         frío    142 ms   mediana    159 ms   objetivo 3000 ms
```
