# Benchmark del mapa de conocimiento

Esquema v21
Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM
Bóveda: 10000 elementos, 2000 temas en la categoría «Tema»

```
Mapa (base): leer elementos, valores y vínculos frío    201 ms   mediana    167 ms
Mapa (base): armar el grafo de temas           frío    172 ms   mediana    152 ms
Mapa (base): comunidades en frío               frío     32 ms   mediana     26 ms
Mapa (base): el tablero                        frío     53 ms   mediana     39 ms
Mapa (base): esquema, los vínculos de la rama mayor frío      6 ms   mediana      5 ms
Mapa (base): esquema, las notas mapa           frío      3 ms   mediana      2 ms
Mapa (base): los elementos de la rama mayor    frío     12 ms   mediana     10 ms
Mapa (base): los elementos de una hoja         frío      0 ms   mediana      0 ms
Mapa (base): leer con un filtro por tipo       frío    128 ms   mediana    149 ms
Mapa (base): armar y detectar con el filtro    frío     58 ms   mediana     44 ms
Mapa: armar el grafo de temas                  frío    133 ms   mediana    148 ms
Mapa: comunidades en frío                      frío     22 ms   mediana     19 ms
Mapa: recalcular tras una captura (grafo + comunidades) frío    146 ms   mediana    158 ms
Mapa: recalcular tras importar 200 elementos   frío    161 ms   mediana    170 ms
Mapa: acomodar el panorama (49), en frío       frío      3 ms   mediana      3 ms
Mapa: acomodar el panorama, en caliente        frío      1 ms   mediana      0 ms
Mapa: acomodar los temas (300), en frío        frío     69 ms   mediana     69 ms
Mapa: acomodar los temas, en caliente          frío     17 ms   mediana     16 ms
Mapa: acomodar los elementos (200), en frío    frío     30 ms   mediana     31 ms
```

- Con los temas de la base, asignados al azar: 2164 temas, 94506 uniones, 1 comunidad en 3 pasadas. Es el peor caso de coste de armar el grafo, y no dice nada de cómo salen las comunidades de una bóveda real.
- Con los temas con estructura: 2164 temas, 77281 uniones, 49 comunidades (la mayor, de 304; la menor, de 3) en 3 pasadas; el panorama dibuja 49 nodos.
- Tras una captura se reasignan 0 temas de 2164, en 1 pasadas.
- Tras importar 200 elementos se reasignan 0 temas, en 1 pasadas.
- El panorama tiene 49 nodos y 881 uniones; el nivel de temas, 300 y 1196; el de elementos, 200 y 166.
- Motor entero, con el isolate: el primer mapa tarda 247 ms desde que se pide hasta que llega (leer 0 ms, armar 169 ms, comunidades 38 ms, total 246 ms); tras una escritura, 341 ms, con la espera de 100 ms incluida (leer 0 ms, armar 166 ms, comunidades 29 ms, total 237 ms).
