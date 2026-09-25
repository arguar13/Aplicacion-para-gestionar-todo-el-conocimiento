# Benchmark de la bóveda sintética

Esquema v26
Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM
Umbral: objetivo del encargo

```
búsqueda: palabra rara                         frío     44 ms   mediana     45 ms   objetivo 300 ms
búsqueda: palabra mediana                      frío    112 ms   mediana    102 ms   objetivo 300 ms
búsqueda: palabra en casi todo                 frío    147 ms   mediana    103 ms   objetivo 300 ms
búsqueda: dos palabras                         frío     35 ms   mediana     34 ms   objetivo 300 ms
búsqueda: prefijo                              frío    118 ms   mediana    236 ms   objetivo 300 ms
cuaderno de 500: palabra rara                  frío     34 ms   mediana     23 ms   objetivo 300 ms
cuaderno de 500: palabra mediana               frío    317 ms   mediana     54 ms   objetivo 300 ms
cuaderno de 500: dos palabras                  frío    173 ms   mediana    101 ms   objetivo 300 ms
detalle: la fuente con más chunks              frío     22 ms   mediana      0 ms   objetivo 200 ms
detalle: una nota con enlaces                  frío      1 ms   mediana      0 ms   objetivo 200 ms
detalle: el elemento más conectado             frío    150 ms   mediana    174 ms
grafo local: panel, elemento típico            frío      2 ms   mediana      0 ms   objetivo 500 ms
grafo local: panel, el más conectado           frío     38 ms   mediana     28 ms   objetivo 500 ms
grafo local: pantalla, el más conectado        frío    166 ms   mediana    232 ms   objetivo 500 ms
línea de tiempo: leer los eventos              frío    112 ms   mediana    108 ms   objetivo 1000 ms
panel de salud: todos los indicadores          frío     50 ms   mediana     36 ms   objetivo 600 ms
filtro: tema raíz grande (con subtemas)        frío     54 ms   mediana     37 ms   objetivo 300 ms
filtro: una hoja (sin subtemas)                frío     19 ms   mediana      5 ms   objetivo 300 ms
filtro: los ids de todo el tema raíz grande    frío     22 ms   mediana     28 ms
D3: CTE recursiva, elementos del tema raíz grande frío     19 ms   mediana     30 ms
D3: cierre materializado, lo mismo             frío     33 ms   mediana     17 ms
Atlas: abrir (agregados + armado del árbol)    frío    359 ms   mediana    250 ms   objetivo 500 ms
Atlas: reabrir con la caché                    frío    246 ms   mediana      0 ms
Atlas: leer los elementos y las notas mapa (SQL) frío    182 ms   mediana    185 ms
Atlas: buscar un tema (letras sueltas)         frío      6 ms   mediana      6 ms
Atlas: exportar a Markdown                     frío     42 ms   mediana     49 ms
vocabulario: estadísticas + candidatos         frío    148 ms   mediana    161 ms   objetivo 3000 ms
```
