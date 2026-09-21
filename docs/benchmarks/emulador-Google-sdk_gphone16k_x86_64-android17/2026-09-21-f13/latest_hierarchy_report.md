# D3: CTE recursiva o cierre materializado

Bóveda: 2164 valores de «Tema»; el tema raíz grande tiene 303 valores (él y sus descendientes) y 4934 elementos.

```
D3: CTE recursiva, elementos del tema raíz grande frío      9 ms   mediana      8 ms
D3: cierre materializado, lo mismo             frío      6 ms   mediana      7 ms
```

El cierre tiene 6873 filas para 2164 valores y se armó en 26 ms (tabla temporal, solo para medir).