# Benchmark del mapa de conocimiento

Esquema v21
Equipo: escritorio Windows i5-10300H, enchufada
Bóveda: 10000 elementos, 2000 temas en la categoría «Tema»

```
Mapa (base): leer elementos, valores y vínculos frío    155 ms   mediana    149 ms
Mapa (base): armar el grafo de temas           frío    145 ms   mediana    176 ms
Mapa (base): comunidades en frío               frío     12 ms   mediana     19 ms
Mapa (base): el tablero                        frío     92 ms   mediana     91 ms
Mapa (base): esquema, los vínculos de la rama mayor frío      8 ms   mediana      9 ms
Mapa (base): esquema, las notas mapa           frío      2 ms   mediana      4 ms
Mapa (base): los elementos de la rama mayor    frío     32 ms   mediana     19 ms
Mapa (base): los elementos de una hoja         frío      1 ms   mediana      0 ms
Mapa (base): leer con un filtro por tipo       frío    124 ms   mediana    155 ms
Mapa (base): armar y detectar con el filtro    frío     47 ms   mediana     45 ms
Mapa: armar el grafo de temas                  frío    112 ms   mediana    116 ms
Mapa: comunidades en frío                      frío     12 ms   mediana     18 ms
Mapa: recalcular tras una captura (grafo + comunidades) frío    133 ms   mediana    136 ms
Mapa: recalcular tras importar 200 elementos   frío    134 ms   mediana    134 ms
Mapa: acomodar el panorama (49), en frío       frío      3 ms   mediana      3 ms
Mapa: acomodar el panorama, en caliente        frío      0 ms   mediana      0 ms
Mapa: acomodar los temas (300), en frío        frío     63 ms   mediana     65 ms
Mapa: acomodar los temas, en caliente          frío     15 ms   mediana     15 ms
Mapa: acomodar los elementos (200), en frío    frío     28 ms   mediana     28 ms
```

- Con los temas de la base, asignados al azar: 2164 temas, 94506 uniones, 1 comunidad en 3 pasadas. Es el peor caso de coste de armar el grafo, y no dice nada de cómo salen las comunidades de una bóveda real.
- Con los temas con estructura: 2164 temas, 77281 uniones, 49 comunidades (la mayor, de 304; la menor, de 3) en 3 pasadas; el panorama dibuja 49 nodos.
- Tras una captura se reasignan 0 temas de 2164, en 1 pasadas.
- Tras importar 200 elementos se reasignan 0 temas, en 1 pasadas.
- El panorama tiene 49 nodos y 881 uniones; el nivel de temas, 300 y 1196; el de elementos, 200 y 166.
- Motor entero, con el isolate: el primer mapa tarda 176 ms desde que se pide hasta que llega (leer 0 ms, armar 140 ms, comunidades 13 ms, total 176 ms); tras una escritura, 331 ms, con la espera de 100 ms incluida (leer 0 ms, armar 160 ms, comunidades 12 ms, total 229 ms).
