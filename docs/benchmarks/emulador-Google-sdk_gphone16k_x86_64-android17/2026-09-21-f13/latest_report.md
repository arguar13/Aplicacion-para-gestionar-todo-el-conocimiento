# Benchmark de la bóveda sintética

Esquema v21
Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM
Umbral: objetivo del encargo

```
búsqueda: palabra rara                         frío     21 ms   mediana     14 ms   objetivo 300 ms
búsqueda: palabra mediana                      frío     32 ms   mediana     27 ms   objetivo 300 ms
búsqueda: palabra en casi todo                 frío     64 ms   mediana     36 ms   objetivo 300 ms
búsqueda: dos palabras                         frío     12 ms   mediana     11 ms   objetivo 300 ms
búsqueda: prefijo                              frío     44 ms   mediana     45 ms   objetivo 300 ms
detalle: la fuente con más chunks              frío      1 ms   mediana      0 ms   objetivo 200 ms
detalle: una nota con enlaces                  frío      0 ms   mediana      0 ms   objetivo 200 ms
detalle: el elemento más conectado             frío     60 ms   mediana     77 ms
grafo local: panel, elemento típico            frío      1 ms   mediana      0 ms   objetivo 500 ms
grafo local: panel, el más conectado           frío     20 ms   mediana     28 ms   objetivo 500 ms
grafo local: pantalla, el más conectado        frío     77 ms   mediana     77 ms   objetivo 500 ms
línea de tiempo: leer los eventos              frío     56 ms   mediana     55 ms   objetivo 1000 ms
panel de salud: todos los indicadores          frío     24 ms   mediana     24 ms   objetivo 600 ms
filtro: tema raíz grande (con subtemas)        frío     15 ms   mediana     15 ms   objetivo 300 ms
filtro: una hoja (sin subtemas)                frío      6 ms   mediana      3 ms   objetivo 300 ms
filtro: los ids de todo el tema raíz grande    frío     16 ms   mediana     16 ms
D3: CTE recursiva, elementos del tema raíz grande frío      9 ms   mediana      8 ms
D3: cierre materializado, lo mismo             frío      6 ms   mediana      7 ms
Atlas: abrir (agregados + armado del árbol)    frío    120 ms   mediana    124 ms   objetivo 500 ms
Atlas: reabrir con la caché                    frío    137 ms   mediana      0 ms
Atlas: leer los elementos y las notas mapa (SQL) frío     77 ms   mediana     73 ms
Atlas: buscar un tema (letras sueltas)         frío     15 ms   mediana      4 ms
Atlas: exportar a Markdown                     frío     30 ms   mediana     30 ms
vocabulario: estadísticas + candidatos         frío     93 ms   mediana     89 ms   objetivo 3000 ms
```
