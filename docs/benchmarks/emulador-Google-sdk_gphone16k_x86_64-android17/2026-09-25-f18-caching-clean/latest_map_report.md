# Benchmark del mapa de conocimiento

Esquema v28
Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM
Bóveda: 10000 elementos, 2000 temas en la categoría «Tema»

```
Mapa (base): leer elementos, valores y vínculos frío    137 ms   mediana    147 ms
Mapa (base): armar el grafo de temas           frío    197 ms   mediana    150 ms
Mapa (base): comunidades en frío               frío     16 ms   mediana     16 ms
Mapa (base): el tablero                        frío     91 ms   mediana     40 ms
Mapa (base): esquema, los vínculos de la rama mayor frío      6 ms   mediana      4 ms
Mapa (base): esquema, las notas mapa           frío      2 ms   mediana      2 ms
Mapa (base): los elementos de la rama mayor    frío     11 ms   mediana     11 ms
Mapa (base): los elementos de una hoja         frío      1 ms   mediana      0 ms
Mapa (base): leer con un filtro por tipo       frío    179 ms   mediana    141 ms
Mapa (base): armar y detectar con el filtro    frío     62 ms   mediana     49 ms
Mapa: armar el grafo de temas                  frío    124 ms   mediana    131 ms
Mapa: comunidades en frío                      frío     18 ms   mediana     17 ms
Mapa: recalcular tras una captura (grafo + comunidades) frío    139 ms   mediana    143 ms
Mapa: recalcular tras importar 200 elementos   frío    123 ms   mediana    143 ms
Mapa: acomodar el panorama (49), en frío       frío      3 ms   mediana      3 ms
Mapa: acomodar el panorama, en caliente        frío      0 ms   mediana      0 ms
Mapa: acomodar los temas (300), en frío        frío     68 ms   mediana     67 ms
Mapa: acomodar los temas, en caliente          frío     15 ms   mediana     15 ms
Mapa: acomodar los elementos (200), en frío    frío     31 ms   mediana     30 ms
```

- Con los temas de la base, asignados al azar: 2164 temas, 94506 uniones, 1 comunidad en 3 pasadas. Es el peor caso de coste de armar el grafo, y no dice nada de cómo salen las comunidades de una bóveda real.
- Con los temas con estructura: 2164 temas, 77281 uniones, 49 comunidades (la mayor, de 304; la menor, de 3) en 3 pasadas; el panorama dibuja 49 nodos.
- Tras una captura se reasignan 0 temas de 2164, en 1 pasadas.
- Tras importar 200 elementos se reasignan 0 temas, en 1 pasadas.
- El panorama tiene 49 nodos y 881 uniones; el nivel de temas, 300 y 1196; el de elementos, 200 y 166.
- Motor entero, con el isolate: el primer mapa tarda 163 ms desde que se pide hasta que llega (leer 0 ms, armar 131 ms, comunidades 14 ms, total 163 ms); tras una escritura, 288 ms, con la espera de 100 ms incluida (leer 0 ms, armar 123 ms, comunidades 27 ms, total 185 ms).
