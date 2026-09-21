# Benchmark de la bóveda sintética

Esquema v21
Equipo: escritorio, Windows 11 (10.0.26200), Intel Core i5-10300H, modo profile (flutter drive -d windows), PC enchufada
Umbral: objetivo del encargo

```
búsqueda: palabra rara                         frío     32 ms   mediana     23 ms   objetivo 300 ms
búsqueda: palabra mediana                      frío     38 ms   mediana     37 ms   objetivo 300 ms
búsqueda: palabra en casi todo                 frío     54 ms   mediana     50 ms   objetivo 300 ms
búsqueda: dos palabras                         frío     19 ms   mediana     18 ms   objetivo 300 ms
búsqueda: prefijo                              frío     59 ms   mediana     59 ms   objetivo 300 ms
detalle: la fuente con más chunks              frío      2 ms   mediana      0 ms   objetivo 200 ms
detalle: una nota con enlaces                  frío      1 ms   mediana      0 ms   objetivo 200 ms
detalle: el elemento más conectado             frío    169 ms   mediana    171 ms
grafo local: panel, elemento típico            frío      3 ms   mediana      1 ms   objetivo 500 ms
grafo local: panel, el más conectado           frío     40 ms   mediana     37 ms   objetivo 500 ms
grafo local: pantalla, el más conectado        frío    108 ms   mediana    105 ms   objetivo 500 ms
línea de tiempo: leer los eventos              frío     64 ms   mediana     66 ms   objetivo 1000 ms
panel de salud: todos los indicadores          frío     40 ms   mediana     40 ms   objetivo 600 ms
filtro: tema raíz grande (con subtemas)        frío     28 ms   mediana     27 ms   objetivo 300 ms
filtro: una hoja (sin subtemas)                frío      7 ms   mediana      5 ms   objetivo 300 ms
filtro: los ids de todo el tema raíz grande    frío     23 ms   mediana     23 ms
D3: CTE recursiva, elementos del tema raíz grande frío     16 ms   mediana     16 ms
D3: cierre materializado, lo mismo             frío     15 ms   mediana     15 ms
Atlas: abrir (agregados + armado del árbol)    frío    186 ms   mediana    192 ms   objetivo 500 ms
Atlas: reabrir con la caché                    frío    187 ms   mediana      0 ms
Atlas: leer los elementos y las notas mapa (SQL) frío    100 ms   mediana    100 ms
Atlas: buscar un tema (letras sueltas)         frío      4 ms   mediana      4 ms
Atlas: exportar a Markdown                     frío     30 ms   mediana     31 ms
vocabulario: estadísticas + candidatos         frío    111 ms   mediana    103 ms   objetivo 3000 ms
```
